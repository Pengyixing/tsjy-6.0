import Foundation
import Network

struct ModbusTCPFrameBuffer {
    private var buffer = Data()

    mutating func append(_ data: Data) {
        buffer.append(data)
    }

    mutating func popNextFrame() -> Data? {
        guard buffer.count >= 6 else { return nil }

        let bytes = [UInt8](buffer)
        let payloadLength = Int(bytes[4]) << 8 | Int(bytes[5])
        let frameLength = 6 + payloadLength

        guard buffer.count >= frameLength else { return nil }

        let frame = buffer.prefix(frameLength)
        buffer.removeFirst(frameLength)
        return Data(frame)
    }
}

class ModbusTCPServer {
    private var listener: NWListener?
    private var registers: [UInt16]
    private let queue = DispatchQueue(label: "com.tsjy.modbusServer")
    private let queueKey = DispatchSpecificKey<Void>()
    private var receiveBuffers: [ObjectIdentifier: ModbusTCPFrameBuffer] = [:]
    var onDiagnosticLog: ((String) -> Void)?
    var onRegistersWritten: (([(address: Int, value: UInt16)]) -> Void)?
    
    init(port: UInt16, registerCount: Int) {
        self.registers = Array(repeating: 0, count: registerCount)
        queue.setSpecific(key: queueKey, value: ())
        
        do {
            let portNW = NWEndpoint.Port(rawValue: port)!
            
            // Listen on the requested port without restricting the network interface.
            // PLC 现场通常走有线网卡，如果把 requiredInterfaceType 设成 .other，
            // 会把 wiredEthernet / Wi-Fi 之类正常接口排除掉。
            let tcpOptions = NWProtocolTCP.Options()
            tcpOptions.enableKeepalive = true
            let parameters = NWParameters(tls: nil, tcp: tcpOptions)
            parameters.allowLocalEndpointReuse = true
            
            listener = try NWListener(using: parameters, on: portNW)
            listener?.stateUpdateHandler = { state in
                switch state {
                case .setup:
                    self.emitDiagnosticLog("ModbusTCPServer setup on port \(port)")
                case .waiting(let error):
                    self.emitDiagnosticLog("ModbusTCPServer waiting on port \(port): \(error)")
                case .ready:
                    self.emitDiagnosticLog("ModbusTCPServer ready on port \(port)")
                case .failed(let error):
                    self.emitDiagnosticLog("ModbusTCPServer failed on port \(port): \(error)")
                case .cancelled:
                    self.emitDiagnosticLog("ModbusTCPServer cancelled on port \(port)")
                default:
                    break
                }
            }
            
            listener?.newConnectionHandler = { [weak self] connection in
                self?.emitDiagnosticLog("ModbusTCPServer accepted connection from PLC: \(String(describing: connection.endpoint))")
                self?.handleConnection(connection)
            }
            
            listener?.start(queue: queue)
            emitDiagnosticLog("ModbusTCPServer started on port \(port), listening on all available interfaces")
        } catch {
            emitDiagnosticLog("Failed to start ModbusTCPServer: \(error)")
        }
    }
    
    func stop() {
        listener?.cancel()
        listener = nil
    }

    func executeOnServerQueue(_ work: @escaping () -> Void) {
        queue.async(execute: work)
    }
    
    func setRegister(address: Int, value: UInt16) {
        withRegisterAccess {
            guard address >= 0 && address < registers.count else { return }
            registers[address] = value
            
            if address == 100 || address == 101 {
                self.emitDiagnosticLog("🚨🚨 [拦截] PLC 成功写入了寄存器地址 \(address) (\(address == 100 ? "40101" : "40102")), 值为: \(value) 🚨🚨")
            }
        }
    }
    
    func getRegister(address: Int) -> UInt16 {
        withRegisterAccess {
            guard address >= 0 && address < registers.count else { return 0 }
            return registers[address]
        }
    }
    
    private func handleConnection(_ connection: NWConnection) {
        receiveBuffers[ObjectIdentifier(connection)] = ModbusTCPFrameBuffer()
        connection.start(queue: queue)
        receiveLoop(on: connection)
    }
    
    private func receiveLoop(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 7, maximumLength: 256) { [weak self] content, context, isComplete, error in
            guard let self = self, let data = content, !data.isEmpty else {
                if let error = error {
                    self?.emitDiagnosticLog("Modbus connection error: \(error)")
                } else if isComplete {
                    self?.emitDiagnosticLog("Modbus connection closed by PLC: \(String(describing: connection.endpoint))")
                }
                self?.receiveBuffers.removeValue(forKey: ObjectIdentifier(connection))
                connection.cancel()
                return
            }

            self.emitDiagnosticLog("ModbusTCPServer received \(data.count) bytes from \(String(describing: connection.endpoint))")

            let key = ObjectIdentifier(connection)
            var frameBuffer = self.receiveBuffers[key] ?? ModbusTCPFrameBuffer()
            frameBuffer.append(data)
            self.receiveBuffers[key] = frameBuffer

            self.processNextBufferedFrame(on: connection)
        }
    }
    
    func handleModbusRequest(data: Data) -> Data? {
        let bytes = [UInt8](data)
        guard bytes.count >= 8 else { return nil }
        
        let transactionID = [bytes[0], bytes[1]]
        let protocolID = [bytes[2], bytes[3]]
        let unitID = bytes[6]
        let functionCode = bytes[7]

        if functionCode == 0x03 {
            guard bytes.count >= 12 else {
                emitDiagnosticLog("ModbusTCPServer rejected FC3 request: bytes=\(bytes.count), reason=short_frame")
                return buildExceptionResponse(
                    transactionID: transactionID,
                    protocolID: protocolID,
                    unitID: unitID,
                    functionCode: functionCode,
                    exceptionCode: 0x03
                )
            }

            let rawStartAddress = Int(bytes[8]) << 8 | Int(bytes[9])
            let startAddress = normalizeRegisterAddress(rawStartAddress)
            emitDiagnosticLog("ModbusTCPServer parsed request FC\(functionCode), rawStart=\(rawStartAddress), normalizedStart=\(startAddress), bytes=\(bytes.count)")
            // Read Holding Registers
            let quantity = Int(bytes[10]) << 8 | Int(bytes[11])
            guard startAddress >= 0 && startAddress + quantity <= registers.count else {
                emitDiagnosticLog("ModbusTCPServer rejected FC3 request: rawStart=\(rawStartAddress), normalizedStart=\(startAddress), quantity=\(quantity), registerCount=\(registers.count)")
                return buildExceptionResponse(
                    transactionID: transactionID,
                    protocolID: protocolID,
                    unitID: unitID,
                    functionCode: functionCode,
                    exceptionCode: 0x02
                )
            }
            emitDiagnosticLog("ModbusTCPServer read request rawStart=\(rawStartAddress), normalizedStart=\(startAddress), quantity=\(quantity)")
            
            let byteCount = UInt8(quantity * 2)
            let newLength = UInt16(3 + byteCount)
            
            var response = [UInt8]()
            response.append(contentsOf: transactionID)
            response.append(contentsOf: protocolID)
            response.append(UInt8(newLength >> 8))
            response.append(UInt8(newLength & 0xFF))
            response.append(unitID)
            response.append(functionCode)
            response.append(byteCount)
            
            for i in 0..<quantity {
                let value = getRegister(address: startAddress + i)
                response.append(UInt8(value >> 8))
                response.append(UInt8(value & 0xFF))
            }
            return Data(response)
            
        } else if functionCode == 0x06 {
            guard bytes.count >= 12 else {
                emitDiagnosticLog("ModbusTCPServer rejected FC6 request: bytes=\(bytes.count), reason=short_frame")
                return buildExceptionResponse(
                    transactionID: transactionID,
                    protocolID: protocolID,
                    unitID: unitID,
                    functionCode: functionCode,
                    exceptionCode: 0x03
                )
            }

            let rawStartAddress = Int(bytes[8]) << 8 | Int(bytes[9])
            let startAddress = normalizeRegisterAddress(rawStartAddress)
            emitDiagnosticLog("ModbusTCPServer parsed request FC\(functionCode), rawStart=\(rawStartAddress), normalizedStart=\(startAddress), bytes=\(bytes.count)")
            // Write Single Register
            let value = UInt16(bytes[10]) << 8 | UInt16(bytes[11])
            guard startAddress >= 0 && startAddress < registers.count else {
                emitDiagnosticLog("ModbusTCPServer rejected FC6 request: rawStart=\(rawStartAddress), normalizedStart=\(startAddress), value=\(value), registerCount=\(registers.count)")
                return buildExceptionResponse(
                    transactionID: transactionID,
                    protocolID: protocolID,
                    unitID: unitID,
                    functionCode: functionCode,
                    exceptionCode: 0x02
                )
            }
            setRegister(address: startAddress, value: value)
            notifyRemoteRegisterWrites([(address: startAddress, value: value)], functionCode: functionCode)
            
            // Response for 06 is an echo of the request
            var response = [UInt8]()
            response.append(contentsOf: bytes[0..<12])
            return Data(response)
            
        } else if functionCode == 0x10 { // 0x10 is 16 in decimal (Write Multiple Registers)
            guard bytes.count >= 13 else {
                emitDiagnosticLog("ModbusTCPServer rejected FC16 request: bytes=\(bytes.count), reason=short_frame")
                return buildExceptionResponse(
                    transactionID: transactionID,
                    protocolID: protocolID,
                    unitID: unitID,
                    functionCode: functionCode,
                    exceptionCode: 0x03
                )
            }

            let rawStartAddress = Int(bytes[8]) << 8 | Int(bytes[9])
            let startAddress = normalizeRegisterAddress(rawStartAddress)
            emitDiagnosticLog("ModbusTCPServer parsed request FC\(functionCode), rawStart=\(rawStartAddress), normalizedStart=\(startAddress), bytes=\(bytes.count)")
            // Write Multiple Registers
            let quantity = Int(bytes[10]) << 8 | Int(bytes[11])
            let byteCount = Int(bytes[12])
            guard byteCount == quantity * 2, bytes.count >= 13 + byteCount else {
                emitDiagnosticLog("ModbusTCPServer rejected FC16 request: rawStart=\(rawStartAddress), normalizedStart=\(startAddress), quantity=\(quantity), byteCount=\(byteCount), bytes=\(bytes.count), reason=invalid_length")
                return buildExceptionResponse(
                    transactionID: transactionID,
                    protocolID: protocolID,
                    unitID: unitID,
                    functionCode: functionCode,
                    exceptionCode: 0x03
                )
            }
            guard startAddress >= 0 && startAddress + quantity <= registers.count else {
                emitDiagnosticLog("ModbusTCPServer rejected FC16 request: rawStart=\(rawStartAddress), normalizedStart=\(startAddress), quantity=\(quantity), byteCount=\(byteCount), registerCount=\(registers.count)")
                return buildExceptionResponse(
                    transactionID: transactionID,
                    protocolID: protocolID,
                    unitID: unitID,
                    functionCode: functionCode,
                    exceptionCode: 0x02
                )
            }
            emitDiagnosticLog("ModbusTCPServer write multiple request rawStart=\(rawStartAddress), normalizedStart=\(startAddress), quantity=\(quantity), byteCount=\(byteCount)")

            var writtenRegisters: [(address: Int, value: UInt16)] = []
            for i in 0..<quantity {
                let valueOffset = 13 + (i * 2)
                let value = UInt16(bytes[valueOffset]) << 8 | UInt16(bytes[valueOffset + 1])
                setRegister(address: startAddress + i, value: value)
                writtenRegisters.append((address: startAddress + i, value: value))
            }
            notifyRemoteRegisterWrites(writtenRegisters, functionCode: functionCode)
            
            // Response for 16 is echoing address and quantity
            let newLength = UInt16(6)
            var response = [UInt8]()
            response.append(contentsOf: transactionID)
            response.append(contentsOf: protocolID)
            response.append(UInt8(newLength >> 8))
            response.append(UInt8(newLength & 0xFF))
            response.append(unitID)
            response.append(functionCode)
            response.append(UInt8(rawStartAddress >> 8))
            response.append(UInt8(rawStartAddress & 0xFF))
            response.append(UInt8(quantity >> 8))
            response.append(UInt8(quantity & 0xFF))
            return Data(response)
        } else if functionCode == 0x17 {
            guard bytes.count >= 17 else {
                emitDiagnosticLog("ModbusTCPServer rejected FC23 request: bytes=\(bytes.count), reason=short_frame")
                return buildExceptionResponse(
                    transactionID: transactionID,
                    protocolID: protocolID,
                    unitID: unitID,
                    functionCode: functionCode,
                    exceptionCode: 0x03
                )
            }

            let rawReadStart = Int(bytes[8]) << 8 | Int(bytes[9])
            let readStart = normalizeRegisterAddress(rawReadStart)
            let readQuantity = Int(bytes[10]) << 8 | Int(bytes[11])
            let rawWriteStart = Int(bytes[12]) << 8 | Int(bytes[13])
            let writeStart = normalizeRegisterAddress(rawWriteStart)
            let writeQuantity = Int(bytes[14]) << 8 | Int(bytes[15])
            let byteCount = Int(bytes[16])

            emitDiagnosticLog("ModbusTCPServer parsed request FC\(functionCode), rawReadStart=\(rawReadStart), normalizedReadStart=\(readStart), rawWriteStart=\(rawWriteStart), normalizedWriteStart=\(writeStart), readQuantity=\(readQuantity), writeQuantity=\(writeQuantity), bytes=\(bytes.count)")

            guard byteCount == writeQuantity * 2, bytes.count >= 17 + byteCount else {
                emitDiagnosticLog("ModbusTCPServer rejected FC23 request: reason=invalid_length, readQuantity=\(readQuantity), writeQuantity=\(writeQuantity), byteCount=\(byteCount), bytes=\(bytes.count)")
                return buildExceptionResponse(
                    transactionID: transactionID,
                    protocolID: protocolID,
                    unitID: unitID,
                    functionCode: functionCode,
                    exceptionCode: 0x03
                )
            }

            guard readStart >= 0, readStart + readQuantity <= registers.count, writeStart >= 0, writeStart + writeQuantity <= registers.count else {
                emitDiagnosticLog("ModbusTCPServer rejected FC23 request: rawReadStart=\(rawReadStart), normalizedReadStart=\(readStart), rawWriteStart=\(rawWriteStart), normalizedWriteStart=\(writeStart), readQuantity=\(readQuantity), writeQuantity=\(writeQuantity), registerCount=\(registers.count)")
                return buildExceptionResponse(
                    transactionID: transactionID,
                    protocolID: protocolID,
                    unitID: unitID,
                    functionCode: functionCode,
                    exceptionCode: 0x02
                )
            }

            var writtenRegisters: [(address: Int, value: UInt16)] = []
            for i in 0..<writeQuantity {
                let valueOffset = 17 + (i * 2)
                let value = UInt16(bytes[valueOffset]) << 8 | UInt16(bytes[valueOffset + 1])
                setRegister(address: writeStart + i, value: value)
                writtenRegisters.append((address: writeStart + i, value: value))
            }
            notifyRemoteRegisterWrites(writtenRegisters, functionCode: functionCode)

            let responseByteCount = UInt8(readQuantity * 2)
            let newLength = UInt16(3 + responseByteCount)
            var response = [UInt8]()
            response.append(contentsOf: transactionID)
            response.append(contentsOf: protocolID)
            response.append(UInt8(newLength >> 8))
            response.append(UInt8(newLength & 0xFF))
            response.append(unitID)
            response.append(functionCode)
            response.append(responseByteCount)
            for i in 0..<readQuantity {
                let value = getRegister(address: readStart + i)
                response.append(UInt8(value >> 8))
                response.append(UInt8(value & 0xFF))
            }
            return Data(response)
        }
        emitDiagnosticLog("ModbusTCPServer unsupported function code FC\(functionCode)")

        return buildExceptionResponse(
            transactionID: transactionID,
            protocolID: protocolID,
            unitID: unitID,
            functionCode: functionCode,
            exceptionCode: 0x01
        )
    }

    private func withRegisterAccess<T>(_ block: () -> T) -> T {
        if DispatchQueue.getSpecific(key: queueKey) != nil {
            return block()
        }

        return queue.sync(execute: block)
    }

    private func normalizeRegisterAddress(_ rawAddress: Int) -> Int {
        // Accept both Modbus PDU offsets (e.g. 100) and absolute 4x addresses (e.g. 40101).
        if (40001...49999).contains(rawAddress) {
            return rawAddress - 40001
        }
        return rawAddress
    }

    private func buildExceptionResponse(
        transactionID: [UInt8],
        protocolID: [UInt8],
        unitID: UInt8,
        functionCode: UInt8,
        exceptionCode: UInt8
    ) -> Data {
        Data([
            transactionID[0], transactionID[1],
            protocolID[0], protocolID[1],
            0x00, 0x03,
            unitID,
            functionCode | 0x80,
            exceptionCode
        ])
    }

    private func notifyRemoteRegisterWrites(_ writes: [(address: Int, value: UInt16)], functionCode: UInt8) {
        guard !writes.isEmpty else { return }
        let summary = writes.map { "\($0.address)=\($0.value)" }.joined(separator: ", ")
        emitDiagnosticLog("ModbusTCPServer remote write FC\(functionCode): \(summary)")
        onRegistersWritten?(writes)
    }

    private func emitDiagnosticLog(_ message: String) {
        print(message)
        onDiagnosticLog?(message)
    }

    private func processNextBufferedFrame(on connection: NWConnection) {
        let key = ObjectIdentifier(connection)
        guard var frameBuffer = receiveBuffers[key] else {
            receiveLoop(on: connection)
            return
        }

        guard let frame = frameBuffer.popNextFrame() else {
            receiveBuffers[key] = frameBuffer
            emitDiagnosticLog("ModbusTCPServer waiting for complete frame from \(String(describing: connection.endpoint))")
            receiveLoop(on: connection)
            return
        }

        receiveBuffers[key] = frameBuffer
        emitDiagnosticLog("ModbusTCPServer assembled complete frame (\(frame.count) bytes)")

        guard let responseData = handleModbusRequest(data: frame) else {
            processNextBufferedFrame(on: connection)
            return
        }

        connection.send(content: responseData, completion: .contentProcessed({ [weak self] sendError in
            guard let self = self else { return }
            if let sendError = sendError {
                self.emitDiagnosticLog("Failed to send Modbus response: \(sendError)")
                self.receiveBuffers.removeValue(forKey: key)
                connection.cancel()
                return
            }
            self.emitDiagnosticLog("ModbusTCPServer sent response (\(responseData.count) bytes)")
            self.processNextBufferedFrame(on: connection)
        }))
    }
}

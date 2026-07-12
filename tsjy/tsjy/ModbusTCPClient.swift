import Foundation
import Network

class ModbusTCPClient {
    private var connection: NWConnection?
    private let queue = DispatchQueue(label: "com.tsjy.modbusClient")
    private var transactionId: UInt16 = 0
    private var pendingRequests: [UInt16: (Result<[UInt16], Error>) -> Void] = [:]
    
    var isConnected = false
    var onConnectionStateChanged: ((Bool) -> Void)?
    var onConnectionError: ((String) -> Void)?
    
    func connect(host: String, port: UInt16) {
        let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: port)!)
        let tcpOptions = NWProtocolTCP.Options()
        tcpOptions.connectionTimeout = 5
        let parameters = NWParameters(tls: nil, tcp: tcpOptions)
        
        connection = NWConnection(to: endpoint, using: parameters)
        
        connection?.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            switch state {
            case .ready:
                self.isConnected = true
                self.onConnectionStateChanged?(true)
                self.receiveLoop()
            case .failed(let error), .waiting(let error):
                print("Modbus Client connection error: \(error)")
                self.isConnected = false
                self.onConnectionError?(error.localizedDescription)
                self.onConnectionStateChanged?(false)
                self.failAllPendingRequests(error: error)
            case .cancelled:
                self.isConnected = false
                self.onConnectionError?("Connection cancelled")
                self.onConnectionStateChanged?(false)
                self.failAllPendingRequests(error: NSError(domain: "ModbusTCPClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "Connection cancelled"]))
            default:
                break
            }
        }
        
        connection?.start(queue: queue)
    }
    
    func disconnect() {
        connection?.cancel()
        connection = nil
        isConnected = false
    }
    
    // Read Holding Registers (FC 03)
    func readHoldingRegisters(startAddress: UInt16, count: UInt16) async throws -> [UInt16] {
        return try await withCheckedThrowingContinuation { continuation in
            queue.async {
                guard self.isConnected, let connection = self.connection else {
                    continuation.resume(throwing: NSError(domain: "ModbusTCPClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "Not connected"]))
                    return
                }
                
                self.transactionId &+= 1
                let tid = self.transactionId
                
                var request = [UInt8]()
                // Transaction ID
                request.append(UInt8(tid >> 8))
                request.append(UInt8(tid & 0xFF))
                // Protocol ID
                request.append(0)
                request.append(0)
                // Length
                request.append(0)
                request.append(6)
                // Unit ID
                request.append(1)
                // Function Code (03)
                request.append(3)
                // Start Address
                request.append(UInt8(startAddress >> 8))
                request.append(UInt8(startAddress & 0xFF))
                // Quantity
                request.append(UInt8(count >> 8))
                request.append(UInt8(count & 0xFF))
                
                self.pendingRequests[tid] = { result in
                    switch result {
                    case .success(let data):
                        continuation.resume(returning: data)
                    case .failure(let error):
                        continuation.resume(throwing: error)
                    }
                }
                
                connection.send(content: Data(request), completion: .contentProcessed({ error in
                    if let error = error {
                        self.queue.async {
                            if let handler = self.pendingRequests.removeValue(forKey: tid) {
                                handler(.failure(error))
                            }
                        }
                    }
                }))
            }
        }
    }
    
    // Write Single Register (FC 06)
    func writeSingleRegister(address: UInt16, value: UInt16) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                guard self.isConnected, let connection = self.connection else {
                    continuation.resume(throwing: NSError(domain: "ModbusTCPClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "Not connected"]))
                    return
                }
                
                self.transactionId &+= 1
                let tid = self.transactionId
                
                var request = [UInt8]()
                request.append(UInt8(tid >> 8))
                request.append(UInt8(tid & 0xFF))
                request.append(0)
                request.append(0)
                request.append(0)
                request.append(6)
                request.append(1)
                request.append(6) // FC 06
                request.append(UInt8(address >> 8))
                request.append(UInt8(address & 0xFF))
                request.append(UInt8(value >> 8))
                request.append(UInt8(value & 0xFF))
                
                self.pendingRequests[tid] = { result in
                    switch result {
                    case .success:
                        continuation.resume(returning: ())
                    case .failure(let error):
                        continuation.resume(throwing: error)
                    }
                }
                
                connection.send(content: Data(request), completion: .contentProcessed({ error in
                    if let error = error {
                        self.queue.async {
                            if let handler = self.pendingRequests.removeValue(forKey: tid) {
                                handler(.failure(error))
                            }
                        }
                    }
                }))
            }
        }
    }
    
    private func receiveLoop() {
        connection?.receive(minimumIncompleteLength: 9, maximumLength: 256) { [weak self] content, context, isComplete, error in
            guard let self = self else { return }
            
            if let error = error {
                print("Modbus Client receive error: \(error)")
                self.disconnect()
                return
            }
            
            if let data = content, data.count >= 9 {
                let bytes = [UInt8](data)
                let tid = UInt16(bytes[0]) << 8 | UInt16(bytes[1])
                let functionCode = bytes[7]
                
                if functionCode == 0x03 {
                    let byteCount = Int(bytes[8])
                    if bytes.count >= 9 + byteCount {
                        var registers = [UInt16]()
                        for i in 0..<(byteCount / 2) {
                            let val = UInt16(bytes[9 + i * 2]) << 8 | UInt16(bytes[10 + i * 2])
                            registers.append(val)
                        }
                        self.queue.async {
                            if let handler = self.pendingRequests.removeValue(forKey: tid) {
                                handler(.success(registers))
                            }
                        }
                    }
                } else if functionCode == 0x06 {
                    self.queue.async {
                        if let handler = self.pendingRequests.removeValue(forKey: tid) {
                            handler(.success([]))
                        }
                    }
                }
            }
            
            if self.isConnected {
                self.receiveLoop()
            }
        }
    }
    
    private func failAllPendingRequests(error: Error) {
        queue.async {
            for (_, handler) in self.pendingRequests {
                handler(.failure(error))
            }
            self.pendingRequests.removeAll()
        }
    }
}

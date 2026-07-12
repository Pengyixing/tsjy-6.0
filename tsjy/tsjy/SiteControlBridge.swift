import Foundation

@MainActor
final class SiteControlBridge {
    var onStateChanged: ((String) -> Void)?
    var onLog: ((String) -> Void)?
    var onPLCFeedback: ((String) -> Void)?
    var onSimulatorLifecycle: ((SimulatorLifecycleReport) -> Void)?

    private let addressMap: [String: UInt16] = [
        "pumpStartCmd": 10,
        "pumpStopCmd": 11,
        "travelEnable": 12,
        "cylinderEnable": 13,
        "travelDirectionAN1": 14,
        "rotationDirectionAN2": 15
    ]

    private var websocket: URLSessionWebSocketTask?
    private var modbusServer: ModbusTCPServer?
    private var modbusClient: ModbusTCPClient?
    private var endpointURL: URL?
    private var isPolling = false
    private var devices = GatewaySnapshot.placeholder.devices
    private var currentState = "未启动本地 PLC 服务端，当前使用内置模拟设备"

    private struct LocalAssemblerFeedbackState {
        var pumpRunning: UInt16
        var travelEnable: UInt16
        var cylinderEnable: UInt16
        var travelDirection: UInt16
        var rotationDirection: UInt16
        var pumpFault: UInt16
    }

    func connect(to endpoint: String) async throws {
        let trimmed = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            currentState = "未配置本地监听地址，当前使用内置模拟设备"
            onStateChanged?(currentState)
            return
        }
        guard let url = URL(string: trimmed) else {
            throw NSError(domain: "tsjy.site", code: 1, userInfo: [NSLocalizedDescriptionKey: "现场接口地址无效"])
        }
        disconnect()
        endpointURL = url
        
        if url.scheme == "ws" || url.scheme == "wss" {
            let task = URLSession.shared.webSocketTask(with: url)
            websocket = task
            task.resume()
            currentState = "已连接现场 WebSocket 接口: \(trimmed)"
            onLog?("现场 WebSocket 接口已连接: \(trimmed)")
            receiveLoop()
        } else if url.scheme == "http" || url.scheme == "https" {
            currentState = "已连接现场 HTTP 接口: \(trimmed)"
            onLog?("现场 HTTP 接口已连接: \(trimmed)")
            isPolling = true
            startHTTPPolling()
        } else if url.scheme == "modbus" {
            // "modbus://0.0.0.0:5020" -> Mac 作为 Server 监听，等待 PLC 主动连接
            let resolvedPort = url.port ?? Int(SiteConnectionConfig.defaultModbusPort)
            let port = UInt16(resolvedPort)
            let server = ModbusTCPServer(port: port, registerCount: 200)
            server.onDiagnosticLog = { [weak self] message in
                Task { @MainActor in
                    self?.onLog?(message)
                }
            }
            server.onRegistersWritten = { [weak self] writes in
                Task { @MainActor in
                    self?.handleModbusRegistersWritten(writes)
                }
            }
            modbusServer = server
            currentState = SiteConnectionConfig.modbusServerListeningMessage(port: port)
            onLog?(currentState)
            isPolling = true
            startModbusPolling()
        } else {
            throw NSError(domain: "tsjy.site", code: 2, userInfo: [NSLocalizedDescriptionKey: "不支持的协议: \(url.scheme ?? "")"])
        }
        onStateChanged?(currentState)
    }

    func disconnect() {
        websocket?.cancel(with: .goingAway, reason: nil)
        websocket = nil
        modbusServer?.stop()
        modbusServer = nil
        modbusClient?.disconnect()
        modbusClient = nil
        isPolling = false
        endpointURL = nil
        currentState = "未启动本地 PLC 服务端，当前使用内置模拟设备"
        onStateChanged?(currentState)
    }

    func snapshot() -> GatewaySnapshot {
        GatewaySnapshot(
            gatewayName: "tsjy-gateway",
            gatewayStatus: "已启动",
            siteStatus: currentState,
            videoStatus: "暂无视频帧",
            lockState: "未锁定",
            videoPort: Int(TSJYNetwork.videoPort),
            controlPort: Int(TSJYNetwork.controlPort),
            videoClientCount: 0,
            controlClientCount: 0,
            devices: devices,
            contentSources: [],
            defaultSourceIDs: []
        )
    }

    func debugControlRegisterMap() -> [String: UInt16] {
        addressMap
    }

    func execute(deviceID: String, action: String, parameters: [String: Double], commandID: String) async -> SiteCommandResult {
        let payload = ControlClientMessage(
            type: "siteCommand",
            clientID: "tsjy-gateway",
            sessionID: nil,
            commandID: commandID,
            deviceID: deviceID,
            action: action,
            parameters: parameters,
            reason: nil,
            clientSendTimestamp: Date().timeIntervalSince1970
        )

        if let websocket {
            do {
                let data = try JSONEncoder.tsjy.encode(payload)
                try await websocket.send(.string(String(decoding: data, as: UTF8.self)))
                applyMockMutation(deviceID: deviceID, action: action, parameters: parameters)
                onStateChanged?(currentState)
                return SiteCommandResult(accepted: true, message: "命令已转发到现场 WebSocket 接口")
            } catch {
                onLog?("现场 WebSocket 发送失败: \(error.localizedDescription)")
            }
        } else if let modbusServer = modbusServer {
            if deviceID == "assembler" {
                let feedbackState = localAssemblerFeedbackState(from: modbusServer)
                if let rejection = localSimulatorRejectionResult(
                    for: action,
                    parameters: parameters,
                    state: feedbackState
                ) {
                    onLog?(rejection.message)
                    return rejection
                }
                var registerWrites: [RegisterWriteEvent] = []
                if action == "startPump" {
                    modbusServer.setRegister(address: Int(addressMap["pumpStartCmd"]!), value: 1)
                    modbusServer.setRegister(address: Int(addressMap["pumpStopCmd"]!), value: 0)
                    registerWrites.append(RegisterWriteEvent(address: Int(addressMap["pumpStartCmd"]!), value: 1))
                    registerWrites.append(RegisterWriteEvent(address: Int(addressMap["pumpStopCmd"]!), value: 0))
                    onLog?("已下发启动拼装机泵指令")
                } else if action == "stopPump" {
                    modbusServer.setRegister(address: Int(addressMap["pumpStartCmd"]!), value: 0)
                    modbusServer.setRegister(address: Int(addressMap["pumpStopCmd"]!), value: 1)
                    registerWrites.append(RegisterWriteEvent(address: Int(addressMap["pumpStartCmd"]!), value: 0))
                    registerWrites.append(RegisterWriteEvent(address: Int(addressMap["pumpStopCmd"]!), value: 1))
                    onLog?("已下发停止拼装机泵指令")
                } else if action == "moveForward" {
                    modbusServer.setRegister(address: Int(addressMap["travelDirectionAN1"]!), value: 1)
                    registerWrites.append(RegisterWriteEvent(address: Int(addressMap["travelDirectionAN1"]!), value: 1))
                    onLog?("已下发前进指令 (AN1=1)")
                } else if action == "moveBackward" {
                    modbusServer.setRegister(address: Int(addressMap["travelDirectionAN1"]!), value: 2)
                    registerWrites.append(RegisterWriteEvent(address: Int(addressMap["travelDirectionAN1"]!), value: 2))
                    onLog?("已下发后退指令 (AN1=2)")
                } else if action == "stopTravel" {
                    modbusServer.setRegister(address: Int(addressMap["travelDirectionAN1"]!), value: 0)
                    registerWrites.append(RegisterWriteEvent(address: Int(addressMap["travelDirectionAN1"]!), value: 0))
                    onLog?("已下发停止行走指令 (AN1=0)")
                } else if action == "rotateClockwise" {
                    modbusServer.setRegister(address: Int(addressMap["rotationDirectionAN2"]!), value: 1)
                    registerWrites.append(RegisterWriteEvent(address: Int(addressMap["rotationDirectionAN2"]!), value: 1))
                    onLog?("已下发顺时针旋转指令 (AN2=1)")
                } else if action == "rotateCounterclockwise" {
                    modbusServer.setRegister(address: Int(addressMap["rotationDirectionAN2"]!), value: 2)
                    registerWrites.append(RegisterWriteEvent(address: Int(addressMap["rotationDirectionAN2"]!), value: 2))
                    onLog?("已下发逆时针旋转指令 (AN2=2)")
                } else if action == "stopRotation" {
                    modbusServer.setRegister(address: Int(addressMap["rotationDirectionAN2"]!), value: 0)
                    registerWrites.append(RegisterWriteEvent(address: Int(addressMap["rotationDirectionAN2"]!), value: 0))
                    onLog?("已下发停止旋转指令 (AN2=0)")
                } else if action == "setParameter" {
                    for (key, value) in parameters {
                        if let addr = addressMap[key] {
                            modbusServer.setRegister(address: Int(addr), value: UInt16(value))
                            registerWrites.append(RegisterWriteEvent(address: Int(addr), value: UInt16(value)))
                            onLog?("已将拼装机参数 \(key) (\(value)) 写入本地 Modbus 寄存器 \(addr)")
                        }
                    }
                }
                applyMockMutation(deviceID: deviceID, action: action, parameters: parameters)
                return SiteCommandResult(
                    accepted: true,
                    message: "拼装机指令已写入本地 Modbus Server",
                    registerWrites: registerWrites,
                    simulatorAccepted: true,
                    simulatorResultCode: 1,
                    simulatorRejectReason: "",
                    simulatorExecutedAction: action
                )
            }
        } else if let url = endpointURL, url.scheme == "http" || url.scheme == "https" {
            do {
                var request = URLRequest(url: url.appendingPathComponent("api/command"))
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = try JSONEncoder.tsjy.encode(payload)
                
                let (_, response) = try await URLSession.shared.data(for: request)
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                    applyMockMutation(deviceID: deviceID, action: action, parameters: parameters)
                    return SiteCommandResult(accepted: true, message: "命令已转发到现场 HTTP 接口")
                } else {
                    onLog?("现场 HTTP 接口返回错误状态码: \((response as? HTTPURLResponse)?.statusCode ?? -1)")
                }
            } catch {
                onLog?("现场 HTTP 发送失败: \(error.localizedDescription)")
            }
        }

        applyMockMutation(deviceID: deviceID, action: action, parameters: parameters)
        return SiteCommandResult(accepted: true, message: "已在本地模拟设备上执行 \(deviceID).\(action)")
    }

    func emergencyStop(reason: String) -> SiteCommandResult {
        if let modbusServer = modbusServer {
            modbusServer.setRegister(address: 10, value: 0)
            modbusServer.setRegister(address: 11, value: 0)
            modbusServer.setRegister(address: 12, value: 0)
            modbusServer.setRegister(address: 13, value: 0)
            modbusServer.setRegister(address: 14, value: 0)
            modbusServer.setRegister(address: 15, value: 0)
        }

        devices = devices.map { device in
            switch device.id {
            case "auxPump":
                return SiteDeviceState(id: device.id, name: device.name, summary: "已急停", isRunning: false, rpm: nil, minRPM: nil, maxRPM: nil, properties: device.properties)
            case "assembler":
                var newProps = device.properties ?? [:]
                newProps["travelEnable"] = 0
                newProps["cylinderEnable"] = 0
                newProps["travelDirectionAN1"] = 0
                newProps["rotationDirectionAN2"] = 0
                return SiteDeviceState(id: device.id, name: device.name, summary: "已急停", isRunning: false, rpm: nil, minRPM: nil, maxRPM: nil, properties: newProps)
            default:
                return device
            }
        }
        onLog?("执行急停: \(reason)")
        return SiteCommandResult(accepted: true, message: "已执行急停")
    }

    private func applyMockMutation(deviceID: String, action: String, parameters: [String: Double]) {
        devices = devices.map { device in
            guard device.id == deviceID else { return device }
            switch (deviceID, action) {
            case ("auxPump", "start"):
                return SiteDeviceState(id: device.id, name: device.name, summary: "运行中", isRunning: true, rpm: nil, minRPM: nil, maxRPM: nil, properties: device.properties)
            case ("auxPump", "stop"):
                return SiteDeviceState(id: device.id, name: device.name, summary: "已停止", isRunning: false, rpm: nil, minRPM: nil, maxRPM: nil, properties: device.properties)
            case ("assembler", "startPump"):
                var newProps = device.properties ?? [:]
                newProps["pumpStartCmd"] = 1
                newProps["pumpStopCmd"] = 0
                return SiteDeviceState(id: device.id, name: device.name, summary: "泵启动", isRunning: true, rpm: nil, minRPM: nil, maxRPM: nil, properties: newProps)
            case ("assembler", "stopPump"):
                var newProps = device.properties ?? [:]
                newProps["pumpStartCmd"] = 0
                newProps["pumpStopCmd"] = 1
                return SiteDeviceState(id: device.id, name: device.name, summary: "泵停止", isRunning: false, rpm: nil, minRPM: nil, maxRPM: nil, properties: newProps)
            case ("assembler", "moveForward"):
                var newProps = device.properties ?? [:]
                newProps["travelDirectionAN1"] = 1
                return SiteDeviceState(id: device.id, name: device.name, summary: "前进中", isRunning: device.isRunning, rpm: nil, minRPM: nil, maxRPM: nil, properties: newProps)
            case ("assembler", "moveBackward"):
                var newProps = device.properties ?? [:]
                newProps["travelDirectionAN1"] = 2
                return SiteDeviceState(id: device.id, name: device.name, summary: "后退中", isRunning: device.isRunning, rpm: nil, minRPM: nil, maxRPM: nil, properties: newProps)
            case ("assembler", "stopTravel"):
                var newProps = device.properties ?? [:]
                newProps["travelDirectionAN1"] = 0
                return SiteDeviceState(id: device.id, name: device.name, summary: "行走停止", isRunning: device.isRunning, rpm: nil, minRPM: nil, maxRPM: nil, properties: newProps)
            case ("assembler", "rotateClockwise"):
                var newProps = device.properties ?? [:]
                newProps["rotationDirectionAN2"] = 1
                return SiteDeviceState(id: device.id, name: device.name, summary: "顺时针旋转", isRunning: device.isRunning, rpm: nil, minRPM: nil, maxRPM: nil, properties: newProps)
            case ("assembler", "rotateCounterclockwise"):
                var newProps = device.properties ?? [:]
                newProps["rotationDirectionAN2"] = 2
                return SiteDeviceState(id: device.id, name: device.name, summary: "逆时针旋转", isRunning: device.isRunning, rpm: nil, minRPM: nil, maxRPM: nil, properties: newProps)
            case ("assembler", "stopRotation"):
                var newProps = device.properties ?? [:]
                newProps["rotationDirectionAN2"] = 0
                return SiteDeviceState(id: device.id, name: device.name, summary: "旋转停止", isRunning: device.isRunning, rpm: nil, minRPM: nil, maxRPM: nil, properties: newProps)
            case ("assembler", "setParameter"):
                var newProps = device.properties ?? [:]
                for (k, v) in parameters {
                    newProps[k] = v
                }
                return SiteDeviceState(id: device.id, name: device.name, summary: "参数已下发", isRunning: device.isRunning, rpm: device.rpm, minRPM: device.minRPM, maxRPM: device.maxRPM, properties: newProps)
            default:
                return device
            }
        }
        onStateChanged?(currentState)
    }

    private func localAssemblerFeedbackState(from modbusServer: ModbusTCPServer) -> LocalAssemblerFeedbackState {
        LocalAssemblerFeedbackState(
            pumpRunning: modbusServer.getRegister(address: 101),
            travelEnable: modbusServer.getRegister(address: 12),
            cylinderEnable: modbusServer.getRegister(address: 13),
            travelDirection: modbusServer.getRegister(address: 14),
            rotationDirection: modbusServer.getRegister(address: 15),
            pumpFault: modbusServer.getRegister(address: 104)
        )
    }

    private func localSimulatorRejectionResult(
        for action: String,
        parameters: [String: Double],
        state: LocalAssemblerFeedbackState
    ) -> SiteCommandResult? {
        if state.pumpFault == 1 {
            return SiteCommandResult(
                accepted: false,
                message: "本地模拟器拒绝执行: 泵站故障",
                simulatorAccepted: false,
                simulatorResultCode: 10,
                simulatorRejectReason: "泵站故障",
                simulatorExecutedAction: "none",
                blockLayer: "SOFTWARE_PLC_INTERLOCK"
            )
        }

        switch action {
        case "moveForward", "moveBackward", "rotateClockwise", "rotateCounterclockwise":
            if state.pumpRunning == 0 {
                return SiteCommandResult(
                    accepted: false,
                    message: "本地模拟器拒绝执行: 泵未启动",
                    simulatorAccepted: false,
                    simulatorResultCode: 6,
                    simulatorRejectReason: "泵未启动",
                    simulatorExecutedAction: "none",
                    blockLayer: "SOFTWARE_PLC_INTERLOCK"
                )
            }
            if state.travelEnable == 0 {
                return SiteCommandResult(
                    accepted: false,
                    message: "本地模拟器拒绝执行: 行走允许无效",
                    simulatorAccepted: false,
                    simulatorResultCode: 7,
                    simulatorRejectReason: "行走允许无效",
                    simulatorExecutedAction: "none",
                    blockLayer: "SOFTWARE_PLC_INTERLOCK"
                )
            }
        case "setParameter":
            if let cylinderEnable = parameters["cylinderEnable"],
               cylinderEnable >= 1,
               state.pumpRunning == 0 {
                return SiteCommandResult(
                    accepted: false,
                    message: "本地模拟器拒绝执行: 泵未启动",
                    simulatorAccepted: false,
                    simulatorResultCode: 6,
                    simulatorRejectReason: "泵未启动",
                    simulatorExecutedAction: "none",
                    blockLayer: "SOFTWARE_PLC_INTERLOCK"
                )
            }
        default:
            break
        }

        return nil
    }

    private func receiveLoop() {
        guard let websocket else { return }
        Task {
            do {
                let message = try await websocket.receive()
                switch message {
                case .string(let text):
                    handleIncomingText(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        handleIncomingText(text)
                    }
                @unknown default:
                    break
                }
                receiveLoop()
            } catch {
                currentState = "现场 WebSocket 接口已断开，当前使用内置模拟设备"
                onStateChanged?(currentState)
                onLog?("现场 WebSocket 接口接收失败: \(error.localizedDescription)")
                self.websocket = nil
            }
        }
    }

    private func startHTTPPolling() {
        guard let url = endpointURL else { return }
        Task {
            while isPolling {
                do {
                    let request = URLRequest(url: url.appendingPathComponent("api/snapshot"))
                    let (data, _) = try await URLSession.shared.data(for: request)
                    if let serverMessage = try? JSONDecoder.tsjy.decode(ControlServerMessage.self, from: data) {
                        self.applyServerMessage(serverMessage)
                    }
                } catch {
                    // poll failed, ignore or log
                }
                try? await Task.sleep(nanoseconds: 1_000_000_000) // 1s polling
            }
        }
    }

    private func handleIncomingText(_ text: String) {
        guard let data = text.data(using: .utf8),
              let serverMessage = try? JSONDecoder.tsjy.decode(ControlServerMessage.self, from: data) else {
            onLog?("现场接口原始消息: \(text)")
            return
        }

        applyServerMessage(serverMessage)
    }

    private func startModbusPolling() {
        Task {
            while isPolling {
                guard let modbusServer = self.modbusServer else {
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    continue
                }
                refreshModbusFeedback(from: modbusServer)
                self.onStateChanged?(self.currentState)
                try? await Task.sleep(nanoseconds: 1_000_000_000) // 1s polling
            }
        }
    }

    private func handleModbusRegistersWritten(_ writes: [(address: Int, value: UInt16)]) {
        let summary = writes.map { "\($0.address)=\($0.value)" }.joined(separator: ", ")
        onLog?("PLC 写入本地 Modbus 寄存器: \(summary)")
        onPLCFeedback?(summary)

        guard let modbusServer else { return }
        refreshModbusFeedback(from: modbusServer)
        onStateChanged?(currentState)
    }

    private func refreshModbusFeedback(from modbusServer: ModbusTCPServer) {
        let pumpStartCmd = modbusServer.getRegister(address: 10)
        let pumpStopCmd = modbusServer.getRegister(address: 11)
        let travelEnable = modbusServer.getRegister(address: 12)
        let cylinderEnable = modbusServer.getRegister(address: 13)
        let travelDirectionAN1 = modbusServer.getRegister(address: 14)
        let rotationDirectionAN2 = modbusServer.getRegister(address: 15)
        let heartbeatPLC = modbusServer.getRegister(address: 100)

        let assemblerRunning = modbusServer.getRegister(address: 101)
        let vacuumBoxReady = modbusServer.getRegister(address: 102)
        let vacuumFault = modbusServer.getRegister(address: 103)
        let pumpFault = modbusServer.getRegister(address: 104)

        devices = devices.map { device in
            if device.id == "assembler" {
                var newProps = device.properties ?? [:]
                newProps["pumpStartCmd"] = Double(pumpStartCmd)
                newProps["pumpStopCmd"] = Double(pumpStopCmd)
                newProps["travelEnable"] = Double(travelEnable)
                newProps["cylinderEnable"] = Double(cylinderEnable)
                newProps["travelDirectionAN1"] = Double(travelDirectionAN1)
                newProps["rotationDirectionAN2"] = Double(rotationDirectionAN2)
                newProps["heartbeatPLC"] = Double(heartbeatPLC)
                newProps["assemblerRunning"] = Double(assemblerRunning)
                newProps["vacuumBoxReady"] = Double(vacuumBoxReady)
                newProps["vacuumFault"] = Double(vacuumFault)
                newProps["pumpFault"] = Double(pumpFault)

                let hasPendingCommand =
                    pumpStartCmd == 1 ||
                    pumpStopCmd == 1 ||
                    travelDirectionAN1 != 0 ||
                    rotationDirectionAN2 != 0

                let summary: String
                if assemblerRunning == 1 {
                    summary = "运行中"
                } else if vacuumFault == 1 || pumpFault == 1 {
                    summary = "故障报警"
                } else if hasPendingCommand {
                    summary = "等待PLC反馈"
                } else {
                    summary = "待命"
                }
                return SiteDeviceState(id: device.id, name: device.name, summary: summary, isRunning: assemblerRunning == 1, rpm: device.rpm, minRPM: device.minRPM, maxRPM: device.maxRPM, properties: newProps)
            }
            return device
        }
    }

    private func applyServerMessage(_ serverMessage: ControlServerMessage) {
        if let snapshot = serverMessage.snapshot {
            devices = snapshot.devices
        }
        currentState = serverMessage.message
        onStateChanged?(currentState)

        if let report = makeSimulatorLifecycleReport(from: serverMessage) {
            onSimulatorLifecycle?(report)
        }
    }

    private func makeSimulatorLifecycleReport(from serverMessage: ControlServerMessage) -> SimulatorLifecycleReport? {
        guard let commandID = serverMessage.commandID else { return nil }
        let hasLifecycleStage =
            serverMessage.simulatorReadTimestamp != nil ||
            serverMessage.logicFinishTimestamp != nil ||
            serverMessage.feedbackWriteTimestamp != nil
        guard hasLifecycleStage else { return nil }
        return SimulatorLifecycleReport(
            commandID: commandID,
            simulatorReadTimestamp: serverMessage.simulatorReadTimestamp,
            logicFinishTimestamp: serverMessage.logicFinishTimestamp,
            feedbackWriteTimestamp: serverMessage.feedbackWriteTimestamp,
            feedbackSummary: makeLifecycleFeedbackSummary(from: serverMessage.snapshot),
            detail: serverMessage.message,
            accepted: serverMessage.simulatorAccepted,
            resultCode: serverMessage.simulatorResultCode,
            rejectReason: serverMessage.simulatorRejectReason ?? "",
            executedAction: serverMessage.simulatorExecutedAction ?? ""
        )
    }

    private func makeLifecycleFeedbackSummary(from snapshot: GatewaySnapshot?) -> String {
        guard let assembler = snapshot?.devices.first(where: { $0.id == "assembler" }),
              let properties = assembler.properties else {
            return ""
        }
        let orderedKeys = [
            "pumpStartCmd",
            "pumpStopCmd",
            "travelEnable",
            "cylinderEnable",
            "travelDirectionAN1",
            "rotationDirectionAN2",
            "heartbeatPLC",
            "assemblerRunning",
            "vacuumBoxReady",
            "vacuumFault",
            "pumpFault"
        ]
        return orderedKeys.compactMap { key in
            guard let value = properties[key] else { return nil }
            return "\(key)=\(Int(value.rounded()))"
        }
        .joined(separator: ", ")
    }
}

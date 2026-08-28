import Foundation

@MainActor
final class ControlClient {
    var onStatus: ((String) -> Void)?
    var onServerMessage: ((ControlServerMessage) -> Void)?
    var onCommandSent: ((String, String) -> Void)?

    private let session = makeDirectWebSocketSession()
    private let clientID = UUID().uuidString
    private var task: URLSessionWebSocketTask?
    private var heartbeatTask: Task<Void, Never>?
    private(set) var sessionID: String?
    private var currentURL: URL?
    private var hasConfirmedConnection = false

    func connect(url: URL) {
        disconnect()
        let task = session.webSocketTask(with: url)
        self.task = task
        currentURL = url
        hasConfirmedConnection = false
        task.resume()
        onStatus?("控制通道连接中: \(url.absoluteString)")
        receiveLoop()
        send(
            ControlClientMessage(
                type: "hello",
                clientID: clientID,
                sessionID: nil,
                commandID: nil,
                deviceID: nil,
                action: nil,
                parameters: nil,
                reason: nil,
                clientSendTimestamp: Date().timeIntervalSince1970
            )
        )

        heartbeatTask = Task { [weak self] in
            while let self, !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                self.send(
                    ControlClientMessage(
                        type: "heartbeat",
                        clientID: self.clientID,
                        sessionID: self.sessionID,
                        commandID: nil,
                        deviceID: nil,
                        action: nil,
                        parameters: nil,
                        reason: nil,
                        clientSendTimestamp: Date().timeIntervalSince1970
                    )
                )
            }
        }
    }

    func disconnect() {
        heartbeatTask?.cancel()
        heartbeatTask = nil
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        sessionID = nil
        currentURL = nil
        hasConfirmedConnection = false
        onStatus?("控制通道未连接")
    }

    func arm() {
        send(
            ControlClientMessage(
                type: "arm",
                clientID: clientID,
                sessionID: sessionID,
                commandID: UUID().uuidString,
                deviceID: nil,
                action: nil,
                parameters: nil,
                reason: nil,
                clientSendTimestamp: Date().timeIntervalSince1970
            )
        )
    }

    func emergencyStop(reason: String) {
        send(
            ControlClientMessage(
                type: "emergencyStop",
                clientID: clientID,
                sessionID: sessionID,
                commandID: UUID().uuidString,
                deviceID: nil,
                action: nil,
                parameters: nil,
                reason: reason,
                clientSendTimestamp: Date().timeIntervalSince1970
            )
        )
    }

    func releaseEmergencyStop() {
        send(
            ControlClientMessage(
                type: "releaseEmergencyStop",
                clientID: clientID,
                sessionID: sessionID,
                commandID: UUID().uuidString,
                deviceID: nil,
                action: nil,
                parameters: nil,
                reason: nil,
                clientSendTimestamp: Date().timeIntervalSince1970
            )
        )
    }

    func startPump() {
        sendCommand(deviceID: "assembler", action: "startPump", parameters: nil)
    }

    func stopPump() {
        sendCommand(deviceID: "assembler", action: "stopPump", parameters: nil)
    }

    func moveForward() {
        sendCommand(deviceID: "assembler", action: "moveForward", parameters: nil)
    }

    func moveBackward() {
        sendCommand(deviceID: "assembler", action: "moveBackward", parameters: nil)
    }

    func stopTravel() {
        sendCommand(deviceID: "assembler", action: "stopTravel", parameters: nil)
    }

    func rotateClockwise() {
        sendCommand(deviceID: "assembler", action: "rotateClockwise", parameters: nil)
    }

    func rotateCounterclockwise() {
        sendCommand(deviceID: "assembler", action: "rotateCounterclockwise", parameters: nil)
    }

    func stopRotation() {
        sendCommand(deviceID: "assembler", action: "stopRotation", parameters: nil)
    }

    func setTravelEnable(_ enable: Bool) {
        sendCommand(deviceID: "assembler", action: "setParameter", parameters: ["travelEnable": enable ? 1.0 : 0.0])
    }

    func setCylinderEnable(_ enable: Bool) {
        sendCommand(deviceID: "assembler", action: "setParameter", parameters: ["cylinderEnable": enable ? 1.0 : 0.0])
    }

    func connect(to urlString: String) {
        guard let url = URL(string: urlString) else { return }
        connect(url: url)
    }

    func sendVideoMetricBatch(_ batch: VideoMetricBatchPayload) {
        send(
            ControlClientMessage(
                type: "videoMetricBatch",
                clientID: clientID,
                sessionID: sessionID,
                commandID: nil,
                deviceID: nil,
                action: nil,
                parameters: nil,
                reason: nil,
                clientSendTimestamp: Date().timeIntervalSince1970,
                videoMetricBatch: batch
            )
        )
    }

    func sendFeedbackRendered(for commandID: String) {
        send(
            ControlClientMessage(
                type: "vpFeedbackRendered",
                clientID: clientID,
                sessionID: sessionID,
                commandID: commandID,
                deviceID: nil,
                action: nil,
                parameters: nil,
                reason: nil,
                clientSendTimestamp: Date().timeIntervalSince1970
            )
        )
    }

    private func sendCommand(deviceID: String, action: String, parameters: [String: Double]?) {
        let commandID = UUID().uuidString
        onCommandSent?(commandID, action)
        send(
            ControlClientMessage(
                type: "command",
                clientID: clientID,
                sessionID: sessionID,
                commandID: commandID,
                deviceID: deviceID,
                action: action,
                parameters: parameters,
                reason: nil,
                clientSendTimestamp: Date().timeIntervalSince1970
            )
        )
    }

    private func send(_ message: ControlClientMessage) {
        guard let task else { return }
        guard let data = try? JSONEncoder.tsjy.encode(message) else { return }
        Task {
            do {
                try await task.send(.string(String(decoding: data, as: UTF8.self)))
            } catch {
                onStatus?("控制消息发送失败: \(error.localizedDescription)")
            }
        }
    }

    private func receiveLoop() {
        guard let task else { return }
        Task {
            do {
                let message = try await task.receive()
                switch message {
                case .string(let text):
                    handleText(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        handleText(text)
                    }
                @unknown default:
                    break
                }
                receiveLoop()
            } catch {
                onStatus?("控制通道断开: \(error.localizedDescription)")
                self.task = nil
                heartbeatTask?.cancel()
            }
        }
    }

    private func handleText(_ text: String) {
        guard let data = text.data(using: .utf8),
              let message = try? JSONDecoder.tsjy.decode(ControlServerMessage.self, from: data) else {
            onStatus?("控制消息解析失败")
            return
        }
        confirmConnectedIfNeeded()
        if let sessionID = message.sessionID {
            self.sessionID = sessionID
        }
        onServerMessage?(message)
    }

    private func confirmConnectedIfNeeded() {
        guard !hasConfirmedConnection else { return }
        hasConfirmedConnection = true
        let target = currentURL?.absoluteString ?? "控制地址"
        onStatus?("控制通道已连接: \(target)")
    }
}

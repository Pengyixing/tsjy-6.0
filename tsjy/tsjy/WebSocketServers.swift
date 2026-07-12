import Foundation
import Network

final class VideoPeer {
    let id = UUID()
    let connection: NWConnection
    var isSending = false
    var pendingPacket: Data?

    init(connection: NWConnection) {
        self.connection = connection
    }
}

final class ControlPeer: Hashable {
    let id = UUID()
    fileprivate let connection: NWConnection

    init(connection: NWConnection) {
        self.connection = connection
    }

    static func == (lhs: ControlPeer, rhs: ControlPeer) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

final class VideoWebSocketServer {
    var onClientCountChanged: ((Int) -> Void)?
    var onLog: ((String) -> Void)?

    private var listener: NWListener?
    private let queue = DispatchQueue(label: "tsjy.video.server")
    private var peers: [UUID: VideoPeer] = [:]
    private var currentConfiguration: VideoConfiguration?

    func start(port: UInt16) throws {
        stop()
        let parameters = websocketParameters()
        listener = try NWListener(using: parameters, on: NWEndpoint.Port(rawValue: port)!)
        listener?.stateUpdateHandler = { [weak self] state in
            self?.onLog?("视频 WebSocket 状态: \(state)")
        }
        listener?.newConnectionHandler = { [weak self] connection in
            self?.accept(connection)
        }
        listener?.start(queue: queue)
    }

    func stop() {
        peers.values.forEach { $0.connection.cancel() }
        peers.removeAll()
        listener?.cancel()
        listener = nil
    }

    func update(configuration: VideoConfiguration) {
        queue.async {
            self.currentConfiguration = configuration
            guard let data = try? JSONEncoder.tsjy.encode(configuration),
                  let text = String(data: data, encoding: .utf8) else {
                return
            }
            for peer in self.peers.values {
                _ = self.sendText(text, to: peer.connection)
            }
        }
    }

    func broadcast(frame: EncodedVideoFrame) {
        queue.async {
            let header = VideoFrameHeader(
                sequence: frame.sequence,
                timestamp: frame.timestamp,
                width: frame.width,
                height: frame.height,
                codec: frame.codec,
                isKeyframe: frame.isKeyframe
            )
            guard let headerData = try? JSONEncoder.tsjy.encode(header) else { return }
            var packet = Data()
            packet.append(headerData)
            packet.append(0x0A)
            packet.append(frame.payload)
            for peer in self.peers.values {
                self.enqueue(packet, for: peer)
            }
        }
    }

    private func accept(_ connection: NWConnection) {
        let peer = VideoPeer(connection: connection)
        peers[peer.id] = peer
        onClientCountChanged?(peers.count)
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.onLog?("视频客户端已连接")
                if let config = self?.currentConfiguration,
                   let data = try? JSONEncoder.tsjy.encode(config),
                   let text = String(data: data, encoding: .utf8) {
                    _ = self?.sendText(text, to: connection)
                }
                self?.receiveLoop(peer)
            case .failed(let error):
                self?.onLog?("视频客户端断开: \(error.localizedDescription)")
                self?.peers.removeValue(forKey: peer.id)
                self?.onClientCountChanged?(self?.peers.count ?? 0)
            case .cancelled:
                self?.peers.removeValue(forKey: peer.id)
                self?.onClientCountChanged?(self?.peers.count ?? 0)
            default:
                break
            }
        }
        connection.start(queue: queue)
    }

    private func receiveLoop(_ peer: VideoPeer) {
        peer.connection.receiveMessage { [weak self] _, _, _, error in
            if error != nil {
                self?.peers.removeValue(forKey: peer.id)
                self?.onClientCountChanged?(self?.peers.count ?? 0)
                return
            }
            self?.receiveLoop(peer)
        }
    }

    private func enqueue(_ packet: Data, for peer: VideoPeer) {
        if peer.isSending {
            peer.pendingPacket = packet
            return
        }
        send(packet, for: peer)
    }

    private func send(_ packet: Data, for peer: VideoPeer) {
        peer.isSending = true
        let metadata = NWProtocolWebSocket.Metadata(opcode: .binary)
        let context = NWConnection.ContentContext(identifier: "binary", metadata: [metadata])
        peer.connection.send(content: packet, contentContext: context, isComplete: true, completion: .contentProcessed { [weak self] error in
            self?.queue.async {
                if error != nil {
                    peer.connection.cancel()
                    self?.peers.removeValue(forKey: peer.id)
                    self?.onClientCountChanged?(self?.peers.count ?? 0)
                    return
                }
                peer.isSending = false
                if let pending = peer.pendingPacket {
                    peer.pendingPacket = nil
                    self?.send(pending, for: peer)
                }
            }
        })
    }

    private func sendText(_ text: String, to connection: NWConnection) -> Bool {
        guard let data = text.data(using: .utf8) else { return false }
        let metadata = NWProtocolWebSocket.Metadata(opcode: .text)
        let context = NWConnection.ContentContext(identifier: "text", metadata: [metadata])
        connection.send(content: data, contentContext: context, isComplete: true, completion: .idempotent)
        return true
    }
}

final class ControlWebSocketServer {
    var onMessage: ((String, ControlPeer) -> Void)?
    var onClientCountChanged: ((Int) -> Void)?
    var onLog: ((String) -> Void)?

    private var listener: NWListener?
    private let queue = DispatchQueue(label: "tsjy.control.server")
    private var peers: [UUID: ControlPeer] = [:]

    func start(port: UInt16) throws {
        stop()
        let parameters = websocketParameters()
        listener = try NWListener(using: parameters, on: NWEndpoint.Port(rawValue: port)!)
        listener?.stateUpdateHandler = { [weak self] state in
            self?.onLog?("控制 WebSocket 状态: \(state)")
        }
        listener?.newConnectionHandler = { [weak self] connection in
            self?.accept(connection)
        }
        listener?.start(queue: queue)
    }

    func stop() {
        peers.values.forEach { $0.connection.cancel() }
        peers.removeAll()
        listener?.cancel()
        listener = nil
    }

    func send(_ message: ControlServerMessage, to peer: ControlPeer) throws {
        let data = try JSONEncoder.tsjy.encode(message)
        _ = sendText(String(decoding: data, as: UTF8.self), to: peer.connection)
    }

    func broadcast(_ message: ControlServerMessage) {
        guard let data = try? JSONEncoder.tsjy.encode(message) else { return }
        let text = String(decoding: data, as: UTF8.self)
        for peer in peers.values {
            _ = sendText(text, to: peer.connection)
        }
    }

    private func accept(_ connection: NWConnection) {
        let peer = ControlPeer(connection: connection)
        peers[peer.id] = peer
        onClientCountChanged?(peers.count)
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.onLog?("控制客户端已连接")
                self?.receiveLoop(peer)
            case .failed(let error):
                self?.onLog?("控制客户端断开: \(error.localizedDescription)")
                self?.peers.removeValue(forKey: peer.id)
                self?.onClientCountChanged?(self?.peers.count ?? 0)
            case .cancelled:
                self?.peers.removeValue(forKey: peer.id)
                self?.onClientCountChanged?(self?.peers.count ?? 0)
            default:
                break
            }
        }
        connection.start(queue: queue)
    }

    private func receiveLoop(_ peer: ControlPeer) {
        peer.connection.receiveMessage { [weak self] data, _, _, error in
            if let data, let text = String(data: data, encoding: .utf8) {
                self?.onMessage?(text, peer)
            }
            if error != nil {
                self?.peers.removeValue(forKey: peer.id)
                self?.onClientCountChanged?(self?.peers.count ?? 0)
                return
            }
            self?.receiveLoop(peer)
        }
    }

    private func sendText(_ text: String, to connection: NWConnection) -> Bool {
        guard let data = text.data(using: .utf8) else { return false }
        let metadata = NWProtocolWebSocket.Metadata(opcode: .text)
        let context = NWConnection.ContentContext(identifier: "text", metadata: [metadata])
        connection.send(content: data, contentContext: context, isComplete: true, completion: .idempotent)
        return true
    }
}

final class StaticFileHTTPServer {
    var onLog: ((String) -> Void)?

    private let queue = DispatchQueue(label: "tsjy.media.http")
    private var listener: NWListener?
    private var rootDirectory: URL?

    func start(port: UInt16, rootDirectory: URL) throws {
        stop()
        self.rootDirectory = rootDirectory.standardizedFileURL
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        listener = try NWListener(using: parameters, on: NWEndpoint.Port(rawValue: port)!)
        listener?.stateUpdateHandler = { [weak self] state in
            self?.onLog?("素材 HTTP 服务状态: \(state)")
        }
        listener?.newConnectionHandler = { [weak self] connection in
            self?.accept(connection)
        }
        listener?.start(queue: queue)
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    private func accept(_ connection: NWConnection) {
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.receiveRequest(on: connection, buffer: Data())
            case .failed(let error):
                self?.onLog?("素材 HTTP 客户端断开: \(error.localizedDescription)")
            default:
                break
            }
        }
        connection.start(queue: queue)
    }

    private func receiveRequest(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            var requestBuffer = buffer
            if let data {
                requestBuffer.append(data)
            }

            if let headerRange = requestBuffer.range(of: Data("\r\n\r\n".utf8)) {
                let headerData = requestBuffer.subdata(in: 0..<headerRange.lowerBound)
                self.handleRequest(headerData, on: connection)
                return
            }

            if let error {
                self.onLog?("素材 HTTP 读取失败: \(error.localizedDescription)")
                connection.cancel()
                return
            }

            if isComplete || requestBuffer.count >= 64 * 1024 {
                self.sendSimpleResponse(
                    connection: connection,
                    status: 400,
                    reason: "Bad Request",
                    body: Data("Bad Request".utf8),
                    contentType: "text/plain; charset=utf-8"
                )
                return
            }

            self.receiveRequest(on: connection, buffer: requestBuffer)
        }
    }

    private func handleRequest(_ headerData: Data, on connection: NWConnection) {
        guard let headerText = String(data: headerData, encoding: .utf8) else {
            sendSimpleResponse(
                connection: connection,
                status: 400,
                reason: "Bad Request",
                body: Data("Bad Request".utf8),
                contentType: "text/plain; charset=utf-8"
            )
            return
        }

        let lines = headerText.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else {
            sendSimpleResponse(
                connection: connection,
                status: 400,
                reason: "Bad Request",
                body: Data("Bad Request".utf8),
                contentType: "text/plain; charset=utf-8"
            )
            return
        }

        let requestParts = requestLine.split(separator: " ", omittingEmptySubsequences: true)
        guard requestParts.count >= 2 else {
            sendSimpleResponse(
                connection: connection,
                status: 400,
                reason: "Bad Request",
                body: Data("Bad Request".utf8),
                contentType: "text/plain; charset=utf-8"
            )
            return
        }

        let method = String(requestParts[0]).uppercased()
        let rawPath = String(requestParts[1])
        let headers: [String: String] = Dictionary(
            uniqueKeysWithValues: lines.dropFirst().compactMap { line in
                guard let separator = line.firstIndex(of: ":") else { return nil }
                let key = line[..<separator].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                let value = line[line.index(after: separator)...].trimmingCharacters(in: .whitespacesAndNewlines)
                return (key, value)
            }
        )

        guard method == "GET" || method == "HEAD" else {
            sendSimpleResponse(
                connection: connection,
                status: 405,
                reason: "Method Not Allowed",
                body: Data("Method Not Allowed".utf8),
                contentType: "text/plain; charset=utf-8",
                extraHeaders: ["Allow: GET, HEAD"]
            )
            return
        }

        guard let fileURL = resolveFileURL(rawPath) else {
            sendSimpleResponse(
                connection: connection,
                status: 404,
                reason: "Not Found",
                body: Data("Not Found".utf8),
                contentType: "text/plain; charset=utf-8"
            )
            return
        }

        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
            let fileSize = (attributes[.size] as? NSNumber)?.int64Value ?? 0
            let mimeType = Self.mimeType(for: fileURL.pathExtension)
            let range = Self.parseByteRange(headers["range"], fileSize: fileSize)
            try sendFile(
                at: fileURL,
                method: method,
                mimeType: mimeType,
                range: range,
                fileSize: fileSize,
                to: connection
            )
        } catch {
            sendSimpleResponse(
                connection: connection,
                status: 500,
                reason: "Internal Server Error",
                body: Data("Internal Server Error".utf8),
                contentType: "text/plain; charset=utf-8"
            )
        }
    }

    private func resolveFileURL(_ rawPath: String) -> URL? {
        guard let rootDirectory else { return nil }
        guard var components = URLComponents(string: "http://localhost\(rawPath)") else { return nil }
        guard let path = components.percentEncodedPath.removingPercentEncoding else { return nil }
        let normalized = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard normalized.hasPrefix("media/") else { return nil }
        let relativePath = String(normalized.dropFirst("media/".count))
        let resolved = rootDirectory.appendingPathComponent(relativePath).standardizedFileURL
        guard resolved.path.hasPrefix(rootDirectory.path) else { return nil }
        guard FileManager.default.fileExists(atPath: resolved.path) else { return nil }
        components = URLComponents()
        return resolved
    }

    private func sendFile(
        at fileURL: URL,
        method: String,
        mimeType: String,
        range: ClosedRange<Int64>?,
        fileSize: Int64,
        to connection: NWConnection
    ) throws {
        let responseRange: ClosedRange<Int64>
        let status: Int
        let reason: String
        var extraHeaders = ["Accept-Ranges: bytes"]

        if let range {
            responseRange = range
            status = 206
            reason = "Partial Content"
            extraHeaders.append("Content-Range: bytes \(range.lowerBound)-\(range.upperBound)/\(fileSize)")
        } else {
            responseRange = 0...max(0, fileSize - 1)
            status = 200
            reason = "OK"
        }

        let contentLength = fileSize == 0 ? 0 : max(0, responseRange.upperBound - responseRange.lowerBound + 1)
        let body: Data
        if method == "HEAD" || fileSize == 0 {
            body = Data()
        } else {
            let handle = try FileHandle(forReadingFrom: fileURL)
            defer { try? handle.close() }
            try handle.seek(toOffset: UInt64(responseRange.lowerBound))
            body = try handle.read(upToCount: Int(contentLength)) ?? Data()
        }

        sendSimpleResponse(
            connection: connection,
            status: status,
            reason: reason,
            body: body,
            contentType: mimeType,
            contentLengthOverride: contentLength,
            extraHeaders: extraHeaders
        )
    }

    private func sendSimpleResponse(
        connection: NWConnection,
        status: Int,
        reason: String,
        body: Data,
        contentType: String,
        contentLengthOverride: Int64? = nil,
        extraHeaders: [String] = []
    ) {
        var response = "HTTP/1.1 \(status) \(reason)\r\n"
        response += "Content-Type: \(contentType)\r\n"
        response += "Content-Length: \(contentLengthOverride ?? Int64(body.count))\r\n"
        response += "Connection: close\r\n"
        response += "Access-Control-Allow-Origin: *\r\n"
        for header in extraHeaders {
            response += "\(header)\r\n"
        }
        response += "\r\n"

        var payload = Data(response.utf8)
        payload.append(body)
        connection.send(content: payload, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private static func parseByteRange(_ header: String?, fileSize: Int64) -> ClosedRange<Int64>? {
        guard let header,
              header.lowercased().hasPrefix("bytes="),
              fileSize > 0 else {
            return nil
        }

        let rangeText = header.dropFirst("bytes=".count)
        let parts = rangeText.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2 else { return nil }

        let lowerText = String(parts[0])
        let upperText = String(parts[1])

        if lowerText.isEmpty, let suffixLength = Int64(upperText) {
            let clampedLength = min(max(1, suffixLength), fileSize)
            return (fileSize - clampedLength)...(fileSize - 1)
        }

        guard let lower = Int64(lowerText), lower >= 0, lower < fileSize else {
            return nil
        }

        let upper = Int64(upperText) ?? (fileSize - 1)
        let clampedUpper = min(max(lower, upper), fileSize - 1)
        return lower...clampedUpper
    }

    private static func mimeType(for pathExtension: String) -> String {
        switch pathExtension.lowercased() {
        case "jpg", "jpeg":
            return "image/jpeg"
        case "png":
            return "image/png"
        case "heic":
            return "image/heic"
        case "webp":
            return "image/webp"
        case "mp4":
            return "video/mp4"
        case "mov":
            return "video/quicktime"
        case "m4v":
            return "video/x-m4v"
        default:
            return "application/octet-stream"
        }
    }
}

private func websocketParameters() -> NWParameters {
    let tcp = NWProtocolTCP.Options()
    let parameters = NWParameters(tls: nil, tcp: tcp)
    parameters.allowLocalEndpointReuse = true
    let websocket = NWProtocolWebSocket.Options()
    websocket.autoReplyPing = true
    parameters.defaultProtocolStack.applicationProtocols.insert(websocket, at: 0)
    return parameters
}
import Foundation
import Network

final class VideoRelayProvider {
    var onLog: ((String) -> Void)?
    var onStatusChanged: ((String) -> Void)?

    private let session = makeDirectWebSocketSession()
    private var task: URLSessionWebSocketTask?
    private var currentConfiguration: VideoConfiguration?
    private var isSending = false
    private var pendingPacket: Data?
    private let sendQueue = DispatchQueue(label: "tsjy.video.relay.send")

    func start(url: URL) {
        stop(notify: false)
        let task = session.webSocketTask(with: url)
        self.task = task
        task.resume()
        onStatusChanged?("连接中")
        onLog?("连接到视频中继服务: \(url.absoluteString)")
        task.sendPing { [weak self] error in
            if let error {
                self?.onStatusChanged?("连接失败")
                self?.onLog?("视频中继连接失败: \(error.localizedDescription)")
            } else {
                self?.onStatusChanged?("已连接")
            }
        }
        receiveLoop()

        if let config = currentConfiguration {
            update(configuration: config)
        }
    }

    func stop(notify: Bool = true) {
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        if notify {
            onStatusChanged?("已断开")
            onLog?("已断开视频中继服务")
        }
    }

    func update(configuration: VideoConfiguration) {
        currentConfiguration = configuration
        guard let data = try? JSONEncoder.tsjy.encode(configuration),
              let text = String(data: data, encoding: .utf8) else {
            return
        }
        sendQueue.async {
            self.task?.send(.string(text)) { _ in }
        }
    }

    func broadcast(frame: EncodedVideoFrame) {
        let header = VideoFrameHeader(
            sequence: frame.sequence,
            timestamp: frame.timestamp,
            width: frame.width,
            height: frame.height,
            codec: frame.codec,
            isKeyframe: frame.isKeyframe
        )
        guard let headerData = try? JSONEncoder.tsjy.encode(header) else { return }
        var packet = Data()
        packet.append(headerData)
        packet.append(0x0A)
        packet.append(frame.payload)

        sendQueue.async {
            self.enqueue(packet)
        }
    }

    private func enqueue(_ packet: Data) {
        if isSending {
            pendingPacket = packet
            return
        }
        send(packet)
    }

    private func send(_ packet: Data) {
        isSending = true
        task?.send(.data(packet)) { [weak self] error in
            self?.sendQueue.async {
                self?.isSending = false
                if error != nil {
                    self?.onStatusChanged?("发送失败")
                    return
                }
                if let pending = self?.pendingPacket {
                    self?.pendingPacket = nil
                    self?.send(pending)
                }
            }
        }
    }

    private func receiveLoop() {
        guard let task else { return }
        task.receive { [weak self] result in
            switch result {
            case .success:
                self?.receiveLoop()
            case .failure(let error):
                self?.onStatusChanged?("连接失败")
                self?.onLog?("视频中继断开: \(error.localizedDescription)")
            }
        }
    }
}

final class ControlRelayProvider {
    var onMessage: ((String) -> Void)?
    var onLog: ((String) -> Void)?
    var onStatusChanged: ((String) -> Void)?

    private let session = makeDirectWebSocketSession()
    private var task: URLSessionWebSocketTask?

    func start(url: URL) {
        stop(notify: false)
        let task = session.webSocketTask(with: url)
        self.task = task
        task.resume()
        onStatusChanged?("连接中")
        onLog?("连接到控制中继服务: \(url.absoluteString)")
        task.sendPing { [weak self] error in
            if let error {
                self?.onStatusChanged?("连接失败")
                self?.onLog?("控制中继连接失败: \(error.localizedDescription)")
            } else {
                self?.onStatusChanged?("已连接")
            }
        }
        receiveLoop()
    }

    func stop(notify: Bool = true) {
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        if notify {
            onStatusChanged?("已断开")
            onLog?("已断开控制中继服务")
        }
    }

    func send(_ message: ControlServerMessage) throws {
        let data = try JSONEncoder.tsjy.encode(message)
        let text = String(decoding: data, as: UTF8.self)
        task?.send(.string(text)) { _ in }
    }

    private func receiveLoop() {
        guard let task else { return }
        task.receive { [weak self] result in
            switch result {
            case .success(let message):
                if case .string(let text) = message {
                    self?.onMessage?(text)
                }
                self?.receiveLoop()
            case .failure(let error):
                self?.onStatusChanged?("连接失败")
                self?.onLog?("控制中继断开: \(error.localizedDescription)")
            }
        }
    }
}

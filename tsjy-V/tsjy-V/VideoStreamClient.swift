import CoreGraphics
import Foundation

final class VideoStreamClient {
    var onFrame: ((FrameSnapshot) -> Void)?
    var onStatus: ((String) -> Void)?
    var onConfiguration: ((VideoConfiguration) -> Void)?

    private let session = makeDirectWebSocketSession()
    private var task: URLSessionWebSocketTask?
    private var currentURL: URL?
    private var hasConfirmedConnection = false

    func connect(url: URL) {
        disconnect()
        let task = session.webSocketTask(with: url)
        self.task = task
        currentURL = url
        hasConfirmedConnection = false
        task.resume()
        Task { @MainActor in
            self.onStatus?("视频通道连接中: \(url.absoluteString)")
        }
        receiveLoop()
    }

    func disconnect() {
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        currentURL = nil
        hasConfirmedConnection = false
        Task { @MainActor in
            self.onStatus?("视频通道未连接")
        }
    }

    private func receiveLoop() {
        guard let task else { return }
        Task {
            do {
                let message = try await task.receive()
                switch message {
                case .string(let text):
                    if let data = text.data(using: .utf8),
                       let configuration = try? JSONDecoder.tsjy.decode(VideoConfiguration.self, from: data) {
                        Task { @MainActor in
                            self.confirmConnectedIfNeeded()
                            self.onConfiguration?(configuration)
                        }
                    }
                case .data(let data):
                    Task { @MainActor in
                        self.confirmConnectedIfNeeded()
                    }
                    handleBinaryFrame(data)
                @unknown default:
                    break
                }
                receiveLoop()
            } catch {
                Task { @MainActor in
                    self.onStatus?("视频通道断开: \(error.localizedDescription)")
                }
                self.task = nil
            }
        }
    }

    @MainActor
    private func confirmConnectedIfNeeded() {
        guard !hasConfirmedConnection else { return }
        hasConfirmedConnection = true
        let target = currentURL?.absoluteString ?? "视频地址"
        onStatus?("视频通道已连接: \(target)")
    }

    private func handleBinaryFrame(_ data: Data) {
        guard let separatorIndex = data.firstIndex(of: 0x0A) else { return }
        let headerData = data.prefix(upTo: separatorIndex)
        let payload = data.suffix(from: data.index(after: separatorIndex))
        guard let header = try? JSONDecoder.tsjy.decode(VideoFrameHeader.self, from: headerData) else { return }

        onFrame?(
            FrameSnapshot(
                sequence: header.sequence,
                timestamp: header.timestamp,
                receiveTimestamp: Date().timeIntervalSince1970,
                size: CGSize(width: header.width, height: header.height),
                codec: header.codec,
                isKeyframe: header.isKeyframe,
                payload: Data(payload)
            )
        )
    }
}

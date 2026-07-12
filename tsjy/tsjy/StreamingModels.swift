import Foundation

func makeDirectWebSocketSessionConfiguration() -> URLSessionConfiguration {
    let configuration = URLSessionConfiguration.default
    configuration.connectionProxyDictionary = [:]
    return configuration
}

func makeDirectWebSocketSession() -> URLSession {
    URLSession(configuration: makeDirectWebSocketSessionConfiguration())
}

enum TSJYNetwork {
    static let videoPort: UInt16 = 8800
    static let controlPort: UInt16 = 8801
    static let mediaPort: UInt16 = 8802
    static let bonjourType = "_tsjy._tcp"
}

struct CameraDeviceInfo: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
}

struct CameraFormatInfo: Identifiable, Hashable, Sendable {
    let width: Int
    let height: Int
    let pixelFormat: String
    let maxFPS: Double

    var id: String {
        "\(width)x\(height)-\(pixelFormat)-\(Int(maxFPS.rounded()))"
    }

    var aspectRatio: Double {
        guard height > 0 else { return 0 }
        return Double(width) / Double(height)
    }

    var isPanoramaCandidate: Bool {
        abs(aspectRatio - 2.0) < 0.05
    }

    var displayText: String {
        let fpsText = maxFPS > 0 ? String(format: "%.0f", maxFPS) : "-"
        let ratioText = String(format: "%.3f", aspectRatio)
        let suffix = isPanoramaCandidate ? "  2:1候选" : ""
        return "\(width)x\(height)  \(pixelFormat)  \(fpsText)fps  比例\(ratioText)\(suffix)"
    }
}

enum VideoQualityMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case fullHD
    case twoPointSevenK
    case fourK

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .fullHD:
            return "1920x960"
        case .twoPointSevenK:
            return "2880x1440"
        case .fourK:
            return "3840x1920"
        }
    }

    var captureWidth: Int {
        switch self {
        case .fullHD:
            return 2880
        case .twoPointSevenK:
            return 2880
        case .fourK:
            return 3840
        }
    }

    var captureHeight: Int {
        switch self {
        case .fullHD:
            return 1440
        case .twoPointSevenK:
            return 1440
        case .fourK:
            return 1920
        }
    }

    var outputWidth: Int {
        switch self {
        case .fullHD:
            return 1920
        case .twoPointSevenK:
            return 2880
        case .fourK:
            return 3840
        }
    }

    var outputHeight: Int {
        switch self {
        case .fullHD:
            return 960
        case .twoPointSevenK:
            return 1440
        case .fourK:
            return 1920
        }
    }

    var targetFPS: Int {
        30
    }

    var targetBitrate: Int {
        switch self {
        case .fullHD:
            return 10_000_000
        case .twoPointSevenK:
            return 16_000_000
        case .fourK:
            return 22_000_000
        }
    }

    static func matchingOutputDimensions(width: Int, height: Int) -> VideoQualityMode? {
        allCases.first { $0.outputWidth == width && $0.outputHeight == height }
    }
}

enum PanoramaSourceLayout: String, CaseIterable, Identifiable, Sendable {
    case passthrough
    case sideBySideFisheye
    case topBottomFisheye

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .passthrough:
            return "原始直通"
        case .sideBySideFisheye:
            return "左右双鱼眼"
        case .topBottomFisheye:
            return "上下双半景"
        }
    }
}

struct PanoramaProjectionSettings {
    var sourceLayout: PanoramaSourceLayout = .passthrough

    static let `default` = PanoramaProjectionSettings(
        sourceLayout: .passthrough
    )
}

struct VideoConfiguration: Codable, Sendable {
    var codec: String
    var width: Int
    var height: Int
    var targetFPS: Int
    var bitrate: Int
    var nalUnitHeaderLength: Int
    var parameterSets: [String]
    var streamName: String
}

struct EncodedVideoFrame: Sendable {
    let sequence: UInt64
    let timestamp: TimeInterval
    let width: Int
    let height: Int
    let codec: String
    let isKeyframe: Bool
    let payload: Data
}

struct VideoFrameHeader: Codable {
    var type = "videoFrame"
    var sequence: UInt64
    var timestamp: TimeInterval
    var width: Int
    var height: Int
    var codec: String
    var isKeyframe: Bool
}

struct SiteDeviceState: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var summary: String
    var isRunning: Bool
    var rpm: Double?
    var minRPM: Double?
    var maxRPM: Double?
    var properties: [String: Double]?
}

enum ContentSourceType: String, Codable, CaseIterable, Hashable, Sendable {
    case url
    case video
    case panoramaPhoto
    case panoramaVideo

    var displayName: String {
        switch self {
        case .url:
            return "URL"
        case .video:
            return "VIDEO"
        case .panoramaPhoto:
            return "全景照片"
        case .panoramaVideo:
            return "全景视频"
        }
    }

    var symbolName: String {
        switch self {
        case .url:
            return "globe"
        case .video:
            return "video"
        case .panoramaPhoto:
            return "photo.on.rectangle.angled"
        case .panoramaVideo:
            return "visionpro.fill"
        }
    }

    var isPanoramaScene: Bool {
        self == .panoramaPhoto || self == .panoramaVideo
    }
}

struct ContentSourceItem: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var name: String
    var type: ContentSourceType
    var enabled: Bool
    var showOnVisionPro: Bool
    var sortOrder: Int
    var group: String
    var icon: String
    var description: String
    var displayMode: String
    var createdAt: String
    var updatedAt: String
    var url: String?
    var openMode: String?
    var streamUrl: String?
    var streamProtocol: String?
    var width: Int?
    var height: Int?
    var allowRefresh: Bool?
    var requiresAuth: Bool?
    var proxyThroughMac: Bool?
    var defaultVisible: Bool?
    var username: String?
    var password: String?
    var muted: Bool?
    var lastStatus: String?
    var lastCheckedAt: String?
    var localFilePath: String?
    var mediaRelativePath: String?
    var mediaMimeType: String?

    static func nowISO() -> String {
        ISO8601DateFormatter().string(from: Date())
    }

    static func makeURL(
        id: String,
        name: String,
        url: String,
        sortOrder: Int,
        group: String,
        description: String = ""
    ) -> ContentSourceItem {
        let ts = nowISO()
        return ContentSourceItem(
            id: id,
            name: name,
            type: .url,
            enabled: true,
            showOnVisionPro: true,
            sortOrder: sortOrder,
            group: group,
            icon: "globe",
            description: description,
            displayMode: "window",
            createdAt: ts,
            updatedAt: ts,
            url: url,
            openMode: "embedded-webview",
            streamUrl: nil,
            streamProtocol: nil,
            width: 1280,
            height: 800,
            allowRefresh: true,
            requiresAuth: false,
            proxyThroughMac: false,
            defaultVisible: false,
            username: nil,
            password: nil,
            muted: nil,
            lastStatus: "unknown",
            lastCheckedAt: nil,
            localFilePath: nil,
            mediaRelativePath: nil,
            mediaMimeType: nil
        )
    }

    static func makeVideo(
        id: String,
        name: String,
        streamUrl: String,
        sortOrder: Int,
        group: String,
        description: String = ""
    ) -> ContentSourceItem {
        let ts = nowISO()
        return ContentSourceItem(
            id: id,
            name: name,
            type: .video,
            enabled: true,
            showOnVisionPro: true,
            sortOrder: sortOrder,
            group: group,
            icon: "video",
            description: description,
            displayMode: "window",
            createdAt: ts,
            updatedAt: ts,
            url: nil,
            openMode: nil,
            streamUrl: streamUrl,
            streamProtocol: "hls",
            width: 960,
            height: 540,
            allowRefresh: nil,
            requiresAuth: nil,
            proxyThroughMac: nil,
            defaultVisible: false,
            username: nil,
            password: nil,
            muted: true,
            lastStatus: "unknown",
            lastCheckedAt: nil,
            localFilePath: nil,
            mediaRelativePath: nil,
            mediaMimeType: nil
        )
    }

    static func makePanoramaPhoto(
        id: String,
        name: String,
        mediaURL: String,
        localFilePath: String,
        mediaRelativePath: String,
        mediaMimeType: String,
        sortOrder: Int,
        group: String,
        description: String = ""
    ) -> ContentSourceItem {
        let ts = nowISO()
        return ContentSourceItem(
            id: id,
            name: name,
            type: .panoramaPhoto,
            enabled: true,
            showOnVisionPro: true,
            sortOrder: sortOrder,
            group: group,
            icon: ContentSourceType.panoramaPhoto.symbolName,
            description: description,
            displayMode: "immersive",
            createdAt: ts,
            updatedAt: ts,
            url: nil,
            openMode: nil,
            streamUrl: mediaURL,
            streamProtocol: "http-file",
            width: 4096,
            height: 2048,
            allowRefresh: nil,
            requiresAuth: false,
            proxyThroughMac: true,
            defaultVisible: false,
            username: nil,
            password: nil,
            muted: nil,
            lastStatus: "unknown",
            lastCheckedAt: nil,
            localFilePath: localFilePath,
            mediaRelativePath: mediaRelativePath,
            mediaMimeType: mediaMimeType
        )
    }

    static func makePanoramaVideo(
        id: String,
        name: String,
        mediaURL: String,
        localFilePath: String,
        mediaRelativePath: String,
        mediaMimeType: String,
        sortOrder: Int,
        group: String,
        description: String = ""
    ) -> ContentSourceItem {
        let ts = nowISO()
        return ContentSourceItem(
            id: id,
            name: name,
            type: .panoramaVideo,
            enabled: true,
            showOnVisionPro: true,
            sortOrder: sortOrder,
            group: group,
            icon: ContentSourceType.panoramaVideo.symbolName,
            description: description,
            displayMode: "immersive",
            createdAt: ts,
            updatedAt: ts,
            url: nil,
            openMode: nil,
            streamUrl: mediaURL,
            streamProtocol: "http-file",
            width: 4096,
            height: 2048,
            allowRefresh: nil,
            requiresAuth: false,
            proxyThroughMac: true,
            defaultVisible: false,
            username: nil,
            password: nil,
            muted: true,
            lastStatus: "unknown",
            lastCheckedAt: nil,
            localFilePath: localFilePath,
            mediaRelativePath: mediaRelativePath,
            mediaMimeType: mediaMimeType
        )
    }
}

struct ContentSourceStoreFile: Codable {
    var version: Int
    var lastUpdated: String
    var sources: [ContentSourceItem]
}

struct MonitoringSessionSummary: Codable, Hashable {
    var sessionID: String
    var trialID: String
    var conditionName: String
    var actionName: String
    var operatorID: String
    var notes: String
    var mode: String
    var isRecording: Bool
    var commandCount: Int
    var commandSuccessCount: Int
    var lastCommandRoundTripMs: Int
    var receivedFrameCount: Int
    var decodedFrameCount: Int
    var displayedFrameCount: Int
    var networkMissingFrameCount: Int
    var decodeDroppedFrameCount: Int
    var displayDroppedFrameCount: Int
    var latestEndToEndLatencyMs: Int

    static let empty = MonitoringSessionSummary(
        sessionID: "",
        trialID: "",
        conditionName: "默认工况",
        actionName: "未指定",
        operatorID: "",
        notes: "",
        mode: "simulation",
        isRecording: false,
        commandCount: 0,
        commandSuccessCount: 0,
        lastCommandRoundTripMs: 0,
        receivedFrameCount: 0,
        decodedFrameCount: 0,
        displayedFrameCount: 0,
        networkMissingFrameCount: 0,
        decodeDroppedFrameCount: 0,
        displayDroppedFrameCount: 0,
        latestEndToEndLatencyMs: 0
    )
}

struct VideoReceiverFrameMetric: Codable, Hashable {
    var sequence: UInt64
    var captureTimestamp: TimeInterval?
    var encodeStartTimestamp: TimeInterval?
    var encodeFinishTimestamp: TimeInterval?
    var sendTimestamp: TimeInterval?
    var receiveTimestamp: TimeInterval
    var decodeFinishTimestamp: TimeInterval?
    var displayTimestamp: TimeInterval?
    var endToEndLatencyMs: Int?
}

struct VideoMetricBatchPayload: Codable, Hashable {
    var sessionID: String
    var frames: [VideoReceiverFrameMetric]
    var receivedFrameCount: Int
    var decodedFrameCount: Int
    var displayedFrameCount: Int
    var networkMissingFrameCount: Int
    var decodeDroppedFrameCount: Int
    var displayDroppedFrameCount: Int
    var latestEndToEndLatencyMs: Int
    var clockOffsetMs: Int?
    var clockRoundTripMs: Int?
    var clockSyncValid: Bool?
    var stallCount: Int?
    var maxFrameIntervalMs: Int?
}

struct RegisterWriteEvent: Codable, Hashable {
    var address: Int
    var value: UInt16
}

struct GatewaySnapshot: Codable, Hashable {
    var gatewayName: String
    var gatewayStatus: String
    var siteStatus: String
    var videoStatus: String
    var lockState: String
    var videoPort: Int
    var controlPort: Int
    var videoClientCount: Int
    var controlClientCount: Int
    var devices: [SiteDeviceState]
    var contentSources: [ContentSourceItem]
    var defaultSourceIDs: [String]
    var monitoring: MonitoringSessionSummary?

    init(
        gatewayName: String,
        gatewayStatus: String,
        siteStatus: String,
        videoStatus: String,
        lockState: String,
        videoPort: Int,
        controlPort: Int,
        videoClientCount: Int,
        controlClientCount: Int,
        devices: [SiteDeviceState],
        contentSources: [ContentSourceItem],
        defaultSourceIDs: [String],
        monitoring: MonitoringSessionSummary? = nil
    ) {
        self.gatewayName = gatewayName
        self.gatewayStatus = gatewayStatus
        self.siteStatus = siteStatus
        self.videoStatus = videoStatus
        self.lockState = lockState
        self.videoPort = videoPort
        self.controlPort = controlPort
        self.videoClientCount = videoClientCount
        self.controlClientCount = controlClientCount
        self.devices = devices
        self.contentSources = contentSources
        self.defaultSourceIDs = defaultSourceIDs
        self.monitoring = monitoring
    }

    static let placeholder = GatewaySnapshot(
        gatewayName: "tsjy-gateway",
        gatewayStatus: "未启动",
        siteStatus: "未连接",
        videoStatus: "暂无视频帧",
        lockState: "未锁定",
        videoPort: Int(TSJYNetwork.videoPort),
        controlPort: Int(TSJYNetwork.controlPort),
        videoClientCount: 0,
        controlClientCount: 0,
        devices: [
            SiteDeviceState(id: "auxPump", name: "辅助泵", summary: "待命", isRunning: false, rpm: nil, minRPM: nil, maxRPM: nil),
            SiteDeviceState(id: "assembler", name: "管片拼装机", summary: "待命", isRunning: false, rpm: nil, minRPM: nil, maxRPM: nil, properties: [
                "assemblerRunning": 0,
                "vacuumBoxReady": 0,
                "vacuumFault": 0,
                "pumpFault": 0,
                "pumpStartCmd": 0,
                "pumpStopCmd": 0,
                "travelEnable": 0,
                "cylinderEnable": 0,
                "travelDirectionAN1": 0,
                "rotationDirectionAN2": 0
            ])
        ],
        contentSources: [],
        defaultSourceIDs: [],
        monitoring: nil
    )
}

struct ControlClientMessage: Codable {
    var type: String
    var clientID: String?
    var sessionID: String?
    var commandID: String?
    var deviceID: String?
    var action: String?
    var parameters: [String: Double]?
    var reason: String?
    var clientSendTimestamp: TimeInterval?
    var videoMetricBatch: VideoMetricBatchPayload?

    init(
        type: String,
        clientID: String?,
        sessionID: String?,
        commandID: String?,
        deviceID: String?,
        action: String?,
        parameters: [String: Double]?,
        reason: String?,
        clientSendTimestamp: TimeInterval? = nil,
        videoMetricBatch: VideoMetricBatchPayload? = nil
    ) {
        self.type = type
        self.clientID = clientID
        self.sessionID = sessionID
        self.commandID = commandID
        self.deviceID = deviceID
        self.action = action
        self.parameters = parameters
        self.reason = reason
        self.clientSendTimestamp = clientSendTimestamp
        self.videoMetricBatch = videoMetricBatch
    }
}

struct ControlServerMessage: Codable {
    var type: String
    var accepted: Bool
    var message: String
    var sessionID: String?
    var snapshot: GatewaySnapshot?
    var commandID: String?
    var gatewayReceiveTimestamp: TimeInterval?
    var validationFinishTimestamp: TimeInterval?
    var registerWriteTimestamp: TimeInterval?
    var simulatorReadTimestamp: TimeInterval?
    var logicFinishTimestamp: TimeInterval?
    var feedbackWriteTimestamp: TimeInterval?
    var plcFeedbackTimestamp: TimeInterval?
    var deviceFeedbackTimestamp: TimeInterval?
    var resultSendTimestamp: TimeInterval?
    var simulatorAccepted: Bool?
    var simulatorResultCode: Int?
    var simulatorRejectReason: String?
    var simulatorExecutedAction: String?

    init(
        type: String,
        accepted: Bool,
        message: String,
        sessionID: String?,
        snapshot: GatewaySnapshot?,
        commandID: String?,
        gatewayReceiveTimestamp: TimeInterval? = nil,
        validationFinishTimestamp: TimeInterval? = nil,
        registerWriteTimestamp: TimeInterval? = nil,
        simulatorReadTimestamp: TimeInterval? = nil,
        logicFinishTimestamp: TimeInterval? = nil,
        feedbackWriteTimestamp: TimeInterval? = nil,
        plcFeedbackTimestamp: TimeInterval? = nil,
        deviceFeedbackTimestamp: TimeInterval? = nil,
        resultSendTimestamp: TimeInterval? = nil,
        simulatorAccepted: Bool? = nil,
        simulatorResultCode: Int? = nil,
        simulatorRejectReason: String? = nil,
        simulatorExecutedAction: String? = nil
    ) {
        self.type = type
        self.accepted = accepted
        self.message = message
        self.sessionID = sessionID
        self.snapshot = snapshot
        self.commandID = commandID
        self.gatewayReceiveTimestamp = gatewayReceiveTimestamp
        self.validationFinishTimestamp = validationFinishTimestamp
        self.registerWriteTimestamp = registerWriteTimestamp
        self.simulatorReadTimestamp = simulatorReadTimestamp
        self.logicFinishTimestamp = logicFinishTimestamp
        self.feedbackWriteTimestamp = feedbackWriteTimestamp
        self.plcFeedbackTimestamp = plcFeedbackTimestamp
        self.deviceFeedbackTimestamp = deviceFeedbackTimestamp
        self.resultSendTimestamp = resultSendTimestamp
        self.simulatorAccepted = simulatorAccepted
        self.simulatorResultCode = simulatorResultCode
        self.simulatorRejectReason = simulatorRejectReason
        self.simulatorExecutedAction = simulatorExecutedAction
    }
}

struct SiteCommandResult {
    var accepted: Bool
    var message: String
    var registerWrites: [RegisterWriteEvent]
    var simulatorAccepted: Bool?
    var simulatorResultCode: Int?
    var simulatorRejectReason: String
    var simulatorExecutedAction: String
    var blockLayer: String

    init(
        accepted: Bool,
        message: String,
        registerWrites: [RegisterWriteEvent] = [],
        simulatorAccepted: Bool? = nil,
        simulatorResultCode: Int? = nil,
        simulatorRejectReason: String = "",
        simulatorExecutedAction: String = "",
        blockLayer: String = ""
    ) {
        self.accepted = accepted
        self.message = message
        self.registerWrites = registerWrites
        self.simulatorAccepted = simulatorAccepted
        self.simulatorResultCode = simulatorResultCode
        self.simulatorRejectReason = simulatorRejectReason
        self.simulatorExecutedAction = simulatorExecutedAction
        self.blockLayer = blockLayer
    }
}

struct SimulatorLifecycleReport: Hashable {
    var commandID: String
    var simulatorReadTimestamp: TimeInterval?
    var logicFinishTimestamp: TimeInterval?
    var feedbackWriteTimestamp: TimeInterval?
    var feedbackSummary: String
    var detail: String
    var accepted: Bool?
    var resultCode: Int?
    var rejectReason: String
    var executedAction: String
}

final class ControlSafetyManager {
    struct SessionState {
        var sessionID: String
        var clientID: String
        var isArmed: Bool
        var lastHeartbeat: Date
        var emergencyStopped: Bool
    }

    private var session: SessionState?
    private let timeout: TimeInterval = 5

    var activeSessionID: String? { session?.sessionID }

    var lockStateDescription: String {
        guard let session else { return "未锁定" }
        if session.emergencyStopped { return "急停中" }
        return session.isArmed ? "已授权给 \(session.clientID)" : "已连接 \(session.clientID)"
    }

    func register(clientID: String) -> SessionState {
        if let current = session, current.clientID == clientID {
            return current
        }
        let newSession = SessionState(
            sessionID: UUID().uuidString,
            clientID: clientID,
            isArmed: false,
            lastHeartbeat: .now,
            emergencyStopped: false
        )
        session = newSession
        return newSession
    }

    func heartbeat(sessionID: String) {
        guard var current = session, current.sessionID == sessionID else { return }
        current.lastHeartbeat = .now
        session = current
    }

    func touch(sessionID: String?) {
        guard let sessionID else { return }
        heartbeat(sessionID: sessionID)
    }

    func arm(sessionID: String?) -> (accepted: Bool, message: String) {
        expireIfNeeded()
        guard var current = session else {
            return (false, "尚未建立控制会话")
        }
        guard current.sessionID == sessionID else {
            return (false, "控制会话不匹配")
        }
        guard !current.emergencyStopped else {
            return (false, "系统处于急停状态")
        }
        current.isArmed = true
        current.lastHeartbeat = .now
        session = current
        return (true, "控制权限已解锁")
    }

    func validateCommand(sessionID: String?, message: ControlClientMessage) -> (accepted: Bool, message: String) {
        expireIfNeeded()
        guard let current = session else {
            return (false, "尚未建立控制会话")
        }
        guard current.sessionID == sessionID else {
            return (false, "控制会话不匹配")
        }
        guard current.isArmed else {
            return (false, "请先执行授权 Arm")
        }
        guard !current.emergencyStopped else {
            return (false, "系统处于急停状态")
        }

        if message.deviceID == "cutterhead", message.action == "setRPM" {
            let rpm = message.parameters?["rpm"] ?? -1
            guard rpm >= 0 && rpm <= 6 else {
                return (false, "刀盘转速超出允许范围 0-6 rpm")
            }
        }
        return (true, "校验通过")
    }

    func forceEmergencyStop(reason: String) {
        guard var current = session else { return }
        current.emergencyStopped = true
        current.isArmed = false
        current.lastHeartbeat = .now
        session = current
        _ = reason
    }

    func reset() {
        session = nil
    }

    private func expireIfNeeded() {
        guard let current = session else { return }
        if Date().timeIntervalSince(current.lastHeartbeat) > timeout {
            session = nil
        }
    }
}

extension JSONEncoder {
    static let tsjy: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        return encoder
    }()
}

extension JSONDecoder {
    static let tsjy = JSONDecoder()
}

extension DateFormatter {
    static let logTimestamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}

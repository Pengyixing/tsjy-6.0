import CoreGraphics
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
    static let bonjourType = "_tsjy._tcp"
    static let videoPort = 8800
    static let controlPort = 8801
    static let mediaPort = 8802
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

struct VideoFrameHeader: Codable {
    var type: String
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
            return "video.fill"
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
        videoStatus: String,
        siteStatus: String,
        videoPort: Int,
        controlPort: Int,
        videoClientCount: Int,
        controlClientCount: Int,
        lockState: String,
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

struct DiscoveredGateway: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let host: String
    let controlPort: Int
    let videoPort: Int

    var controlURL: URL? { socketURL(port: controlPort) }
    var videoURL: URL? { socketURL(port: videoPort) }

    private func socketURL(port: Int) -> URL? {
        var components = URLComponents()
        components.scheme = "ws"
        components.host = host
        components.port = port
        return components.url
    }
}

struct FrameSnapshot {
    var sequence: UInt64
    var timestamp: TimeInterval
    var receiveTimestamp: TimeInterval
    var size: CGSize
    var codec: String
    var isKeyframe: Bool
    var payload: Data

    init(
        sequence: UInt64,
        timestamp: TimeInterval,
        receiveTimestamp: TimeInterval = Date().timeIntervalSince1970,
        size: CGSize,
        codec: String,
        isKeyframe: Bool,
        payload: Data
    ) {
        self.sequence = sequence
        self.timestamp = timestamp
        self.receiveTimestamp = receiveTimestamp
        self.size = size
        self.codec = codec
        self.isKeyframe = isKeyframe
        self.payload = payload
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

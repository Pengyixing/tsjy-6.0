import AVFoundation
import Darwin
import Foundation
import Observation
import CoreGraphics

struct SiteConnectionConfig {
    static let defaultModbusHost = "0.0.0.0"
    static let defaultModbusPort: UInt16 = 5020
    static let defaultModbusEndpoint = "modbus://\(defaultModbusHost):\(defaultModbusPort)"

    static func resolveConnectPLCURL(explicitURL: String?, siteEndpointText: String) -> String {
        let explicit = explicitURL?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !explicit.isEmpty {
            return explicit
        }

        let stored = siteEndpointText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !stored.isEmpty {
            return stored
        }

        return defaultModbusEndpoint
    }

    static func modbusFailureMessage(host: String, port: UInt16, errorDescription: String) -> String {
        "PLC 连接失败 (\(host):\(port)): \(errorDescription)"
    }

    static func modbusServerListeningMessage(port: UInt16) -> String {
        "已启动本地 Modbus TCP Server，监听端口: \(port)，等待 PLC 连接"
    }
}

@MainActor
@Observable
final class AppModel {
    struct LogEntry: Identifiable {
        let id = UUID()
        let timestamp: String
        let message: String
    }

    struct CommandLifecycleOutcome {
        var actualFeedback: String
        var feedbackMatched: Bool?
        var finalResult: String
    }

    private struct FeedbackExpectation {
        var name: String
        var expectedValue: String
    }

    private struct ActiveJogCycle {
        var jogCycleID: String
        var direction: String
        var startCommandID: String
        var startClientSendTimestamp: TimeInterval?
    }

    private struct CommandLifecycleRecord {
        var sessionID: String
        var trialID: String
        var commandID: String
        var action: String
        var commandSemantic: String
        var repeatIndex: Int
        var scenarioID: String
        var jogCycleID: String
        var clientSendTimestamp: TimeInterval?
        var gatewayReceiveTimestamp: TimeInterval?
        var validationFinishTimestamp: TimeInterval?
        var registerWriteTimestamp: TimeInterval?
        var simulatorReadTimestamp: TimeInterval?
        var logicFinishTimestamp: TimeInterval?
        var feedbackWriteTimestamp: TimeInterval?
        var plcFeedbackTimestamp: TimeInterval?
        var deviceFeedbackTimestamp: TimeInterval?
        var resultSendTimestamp: TimeInterval?
        var vpFeedbackRenderTimestamp: TimeInterval?
        var accepted: Bool
        var rejectionReason: String
        var expectedFeedback: String
        var targetFeedbackName: String
        var targetFeedbackExpectedValue: String
        var targetFeedbackBeforeValue: String
        var targetFeedbackCurrentValue: String
        var feedbackBefore: String
        var actualFeedback: String
        var feedbackAfter: String
        var feedbackChanged: Bool?
        var feedbackChangeTimestamp: TimeInterval?
        var feedbackMatched: Bool?
        var feedbackWaitStartTimestamp: TimeInterval?
        var feedbackMatchedTimestamp: TimeInterval?
        var feedbackTimeoutTimestamp: TimeInterval?
        var feedbackWaitDurationMs: Int?
        var finalResult: String
        var failureStage: String
        var responseTimeoutMs: Int
        var validSample: Bool
        var invalidReason: String
        var blockLayer: String
        var blockReason: String
        var simulatorAccepted: Bool?
        var simulatorResultCode: Int?
        var simulatorRejectReason: String
        var simulatorExecutedAction: String
        var unexpectedMotion: Bool
        var startCommandID: String
        var stopCommandID: String
        var holdDurationMs: Int?
        var startResponseMs: Int?
        var stopResponseMs: Int?
        var stopSuccessful: Bool?
    }

    private struct VideoSenderMetric {
        var sequence: UInt64
        var captureTimestamp: TimeInterval
        var sendTimestamp: TimeInterval
        var width: Int
        var height: Int
        var payloadBytes: Int
        var isKeyframe: Bool
        var connectedClients: Int
    }

    private struct MonitoringProcessEvent: Identifiable {
        let id = UUID()
        var sessionID: String
        var recordID: String
        var repeatIndex: Int
        var conditionName: String
        var operatorID: String
        var mode: String
        var scenarioID: String
        var jogCycleID: String
        var networkCondition: String
        var simulatorScanCycleMs: Int
        var artificialDelayMs: Int
        var recordingStartedAt: Date
        var eventAt: Date
        var eventType: String
        var actionName: String
        var phase: String
        var commandID: String
        var clientSendTimeText: String
        var gatewayReceiveTimeText: String
        var registerWriteTimeText: String
        var simulatorReadTimeText: String
        var feedbackWriteTimeText: String
        var gatewayFeedbackTimeText: String
        var vpFeedbackRenderTimeText: String
        var commandSemantic: String
        var expectedFeedback: String
        var targetFeedbackName: String
        var targetFeedbackExpectedValue: String
        var targetFeedbackBeforeValue: String
        var targetFeedbackCurrentValue: String
        var feedbackBefore: String
        var actualFeedback: String
        var feedbackAfter: String
        var feedbackChangedText: String
        var feedbackChangeTimeText: String
        var feedbackMatchedText: String
        var feedbackWaitStartTimeText: String
        var feedbackMatchedTimeText: String
        var feedbackTimeoutTimeText: String
        var feedbackWaitDurationMsText: String
        var finalResult: String
        var failureStage: String
        var blockLayer: String
        var blockReason: String
        var simulatorAcceptedText: String
        var simulatorResultCodeText: String
        var simulatorRejectReason: String
        var simulatorExecutedAction: String
        var validSampleText: String
        var invalidReason: String
        var unexpectedMotionText: String
        var startResponseMsText: String
        var controlLoopMsText: String
        var stopResponseMsText: String
        var stopSuccessfulText: String
        var startCommandID: String
        var stopCommandID: String
        var holdDurationMsText: String
        var clockOffsetMsText: String
        var clockRoundTripMsText: String
        var clockSyncValidText: String
        var stallCountText: String
        var maxFrameIntervalMsText: String
        var videoLatencyText: String
        var videoLatencyValidText: String
        var videoLatencyInvalidReason: String
        var detail: String
        var commandRoundTripMs: Int?
        var endToEndLatencyMs: Int
        var startReceivedFrameCount: Int
        var startDecodedFrameCount: Int
        var startDisplayedFrameCount: Int
        var endReceivedFrameCount: Int
        var endDecodedFrameCount: Int
        var endDisplayedFrameCount: Int
        var receivedFrameCount: Int
        var decodedFrameCount: Int
        var displayedFrameCount: Int
        var networkMissingFrameCount: Int
        var decodeDroppedFrameCount: Int
        var displayDroppedFrameCount: Int
        var gatewayStatus: String
        var siteStatus: String
        var lockState: String
        var heartbeatPLC: Int
        var assemblerRunning: Bool
        var vacuumBoxReady: Bool
        var vacuumFault: Bool
        var pumpFault: Bool
        var notes: String
    }

    struct MonitoringTrialRecord: Identifiable {
        let id = UUID()
        var sessionID: String
        var trialID: String
        var conditionName: String
        var actionName: String
        var operatorID: String
        var mode: String
        var startedAt: Date
        var finishedAt: Date
        var validSample: Bool
        var success: Bool
        var commandRoundTripMs: Int
        var endToEndLatencyMs: Int
        var receivedFrameCount: Int
        var decodedFrameCount: Int
        var displayedFrameCount: Int
        var networkMissingFrameCount: Int
        var decodeDroppedFrameCount: Int
        var displayDroppedFrameCount: Int
        var gatewayStatus: String
        var siteStatus: String
        var lockState: String
        var heartbeatPLC: Int
        var assemblerRunning: Bool
        var vacuumBoxReady: Bool
        var vacuumFault: Bool
        var pumpFault: Bool
        var notes: String
    }

    private enum PanoramaAssetKind {
        case photo
        case video
    }

    var gatewayName = Host.current().localizedName ?? "tsjy-gateway"
    var isGatewayRunning = false
    var gatewayStatus = "未启动"

    var availableCameras: [CameraDeviceInfo] = []
    var selectedCameraID: String?
    var selectedCameraName = "未选择"
    var selectedVideoQualityMode: VideoQualityMode {
        get {
            let rawValue = UserDefaults.standard.string(forKey: "SelectedVideoQualityMode") ?? VideoQualityMode.fullHD.rawValue
            return VideoQualityMode(rawValue: rawValue) ?? .fullHD
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "SelectedVideoQualityMode")
        }
    }

    var siteEndpointText: String {
        get { UserDefaults.standard.string(forKey: "SiteEndpointURL") ?? SiteConnectionConfig.defaultModbusEndpoint }
        set { UserDefaults.standard.set(newValue, forKey: "SiteEndpointURL") }
    }
    var siteStatus = "未启动本地 PLC 服务端，当前使用内置模拟设备"

    var connectedVideoClients = 0
    var connectedControlClients = 0
    var lastFrameInfo = "暂无视频帧"
    var latestSnapshot = GatewaySnapshot.placeholder
    var logEntries: [LogEntry] = []
    var monitoringSessionID = AppModel.makeMonitoringSessionID()
    var monitoringTrialID = "trial-001"
    var monitoringConditionName = "默认工况"
    var monitoringActionName = "未指定"
    var monitoringOperatorID = ""
    var monitoringNotes = ""
    var isMonitoringRecording = true
    var monitoringMode = "SIL"
    var monitoringRepeatIndex = 1
    var monitoringScenarioID = "normal_operation"
    var monitoringJogCycleID = ""
    var monitoringNetworkCondition = "局域网"
    var monitoringSimulatorScanCycleMs = 50
    var monitoringArtificialDelayMs = 0
    var monitoringResponseTimeoutMs = 3000
    var monitoringCommandCount = 0
    var monitoringCommandSuccessCount = 0
    var monitoringLastCommandRoundTripMs = 0
    var monitoringReceivedFrameCount = 0
    var monitoringDecodedFrameCount = 0
    var monitoringDisplayedFrameCount = 0
    var monitoringStartReceivedFrameCount = 0
    var monitoringStartDecodedFrameCount = 0
    var monitoringStartDisplayedFrameCount = 0
    var monitoringNetworkMissingFrameCount = 0
    var monitoringDecodeDroppedFrameCount = 0
    var monitoringDisplayDroppedFrameCount = 0
    var monitoringStartNetworkMissingFrameCount = 0
    var monitoringStartDecodeDroppedFrameCount = 0
    var monitoringStartDisplayDroppedFrameCount = 0
    var monitoringLatestEndToEndLatencyMs = 0
    var monitoringClockOffsetMs = 0
    var monitoringClockRoundTripMs = 0
    var monitoringClockSyncValid = false
    var monitoringStallCount = 0
    var monitoringMaxFrameIntervalMs = 0
    var monitoringLastBatchSummary = "尚未收到 Vision Pro 监测数据"
    var monitoringCurrentTrialStartedAt: Date?
    var monitoringCurrentTrialState = "未录制"
    var monitoringTrialHistory: [MonitoringTrialRecord] = []
    var panoramaSettings = PanoramaProjectionSettings.default
    var supportedFormats: [CameraFormatInfo] = []
    var rawPreviewImage: CGImage?
    var processedPreviewImage: CGImage?
    var rawFrameWidth = 0
    var rawFrameHeight = 0
    var rawFrameAspectRatio = 0.0
    var rawFrameType = "未知"
    var projectionMode = "Raw"
    var isSpherePreviewEnabled = false
    var rawFramesDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("tsjy-raw-frames", isDirectory: true).path
    var videoRecordingDirectoryPath = ""
    var videoRecordingStatus = "未录制"
    var isVideoRecording = false
    var activeVideoRecordingFilePath = "未开始"
    var contentSources: [ContentSourceItem] = AppModel.defaultContentSources
    var selectedContentSourceID: String?
    var gatewayReachableHosts: [String] = []
    var manualGatewayHost = ""
    var relayServerHost = ""
    var relayTargetDescription = "未配置"
    var relayVideoStatus = "未配置"
    var relayControlStatus = "未配置"
    var relayLastError = "无"
    private var currentVideoConfiguration = VideoConfiguration(
        codec: "h264",
        width: VideoQualityMode.fullHD.outputWidth,
        height: VideoQualityMode.fullHD.outputHeight,
        targetFPS: VideoQualityMode.fullHD.targetFPS,
        bitrate: VideoQualityMode.fullHD.targetBitrate,
        nalUnitHeaderLength: 4,
        parameterSets: [],
        streamName: "Insta360 Panorama"
    )

    static let defaultContentSources: [ContentSourceItem] = [
        .makeURL(
            id: "site-dashboard",
            name: "管理平台",
            url: "https://yz.yangzhoumetro.com:16000",
            sortOrder: 0,
            group: "现场系统",
            description: "现场管理平台网页"
        ),
        .makeURL(
            id: "tunnel-status",
            name: "掘进平台",
            url: "https://www.apple.com",
            sortOrder: 1,
            group: "测试页面",
            description: "内容窗口联调占位源"
        )
    ]

    private let cameraService = CameraCaptureService()
    private let videoServer = VideoWebSocketServer()
    private let controlServer = ControlWebSocketServer()
    private let videoRelay = VideoRelayProvider()
    private let controlRelay = ControlRelayProvider()
    private let mediaServer = StaticFileHTTPServer()
    private let discoveryPublisher = DiscoveryPublisher()
    private let siteBridge = SiteControlBridge()
    private let safetyManager = ControlSafetyManager()
    private var contentSourceHealthTimer: Timer?
    private var activeTravelJogCycle: ActiveJogCycle?
    private var activeRotationJogCycle: ActiveJogCycle?
    private let sourceStoreURL: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("tsjy", isDirectory: true)
        return dir.appendingPathComponent("sources.json")
    }()
    private static let stateExportDirectoryDefaultsKey = "StateExportDirectoryPath"
    private let panoramaLibraryRootURL: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("tsjy/panorama-library", isDirectory: true)
        return dir
    }()
    private let suggestedPanoramaImportURL = URL(
        fileURLWithPath: "/Users/pengyixing/Desktop/远程管控/360素材",
        isDirectory: true
    )
    private var activeStateExportFileURL: URL?
    private let modbusFeedbackAddressNames: [Int: String] = [
        10: "pumpStartCmd",
        11: "pumpStopCmd",
        12: "travelEnableFeedback",
        13: "cylinderEnableFeedback",
        14: "travelActualDirection",
        15: "rotationActualDirection",
        100: "heartbeatPLC",
        101: "pumpRunningFeedback",
        102: "vacuumBoxReady",
        103: "vacuumFault",
        104: "pumpFault",
        105: "travelEnableFeedback",
        106: "cylinderEnableFeedback",
        107: "travelActualDirection",
        108: "rotationActualDirection",
        109: "actionCounter"
    ]
    private static let stateExportTimestampFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    private static let stateExportFileFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        return formatter
    }()
    private var commandLifecycleRecords: [String: CommandLifecycleRecord] = [:]
    private var pendingPLCFeedbackCommandIDs: [String] = []
    private var monitoringNextTrialIndex = 1
    private var monitoringProcessEvents: [MonitoringProcessEvent] = []

    private func refreshGatewayReachableHosts() {
        gatewayReachableHosts = Self.discoverLocalIPv4Hosts()
        if gatewayReachableHosts.isEmpty {
            gatewayReachableHosts = ["127.0.0.1"]
        }
    }

    private static func discoverLocalIPv4Hosts() -> [String] {
        var addresses: [String] = []
        var pointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&pointer) == 0, let first = pointer else {
            return []
        }
        defer { freeifaddrs(pointer) }

        // Only advertise physical or cellular-style interfaces.
        // Tunnel/virtual adapters (for example utun) produce IPs that Vision Pro
        // usually cannot reach directly, so they should not be suggested here.
        let preferredPrefixes = ["en", "pdp_ip"]
        for interface in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let flags = Int32(interface.pointee.ifa_flags)
            let isUp = (flags & IFF_UP) != 0
            let isLoopback = (flags & IFF_LOOPBACK) != 0
            guard isUp, !isLoopback,
                  let address = interface.pointee.ifa_addr,
                  address.pointee.sa_family == UInt8(AF_INET) else {
                continue
            }

            let name = String(cString: interface.pointee.ifa_name)
            guard preferredPrefixes.contains(where: { name.hasPrefix($0) }) else {
                continue
            }

            var hostBuffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let result = getnameinfo(
                address,
                socklen_t(address.pointee.sa_len),
                &hostBuffer,
                socklen_t(hostBuffer.count),
                nil,
                0,
                NI_NUMERICHOST
            )
            guard result == 0 else { continue }
            let host = String(cString: hostBuffer)
            if !addresses.contains(host) {
                addresses.append(host)
            }
        }
        return addresses
    }

    private static func makeMonitoringSessionID(date: Date = .now) -> String {
        "session_" + stateExportFileFormatter.string(from: date) + "_" + UUID().uuidString.prefix(6)
    }

    private static func makeMonitoringTrialID(index: Int) -> String {
        String(format: "trial-%03d", index)
    }

    private var monitoringSummary: MonitoringSessionSummary {
        MonitoringSessionSummary(
            sessionID: monitoringSessionID,
            trialID: monitoringTrialID,
            conditionName: monitoringConditionName,
            actionName: monitoringActionName,
            operatorID: monitoringOperatorID,
            notes: monitoringNotes,
            mode: monitoringMode,
            isRecording: isMonitoringRecording,
            commandCount: monitoringCommandCount,
            commandSuccessCount: monitoringCommandSuccessCount,
            lastCommandRoundTripMs: monitoringLastCommandRoundTripMs,
            receivedFrameCount: monitoringReceivedFrameCount,
            decodedFrameCount: monitoringDecodedFrameCount,
            displayedFrameCount: monitoringDisplayedFrameCount,
            networkMissingFrameCount: monitoringNetworkMissingFrameCount,
            decodeDroppedFrameCount: monitoringDecodeDroppedFrameCount,
            displayDroppedFrameCount: monitoringDisplayDroppedFrameCount,
            latestEndToEndLatencyMs: monitoringLatestEndToEndLatencyMs
        )
    }

    var monitoringSummaryText: String {
        guard !monitoringTrialHistory.isEmpty else {
            return "暂无已完成过程记录"
        }
        let totalEvents = monitoringTrialHistory.reduce(0) { $0 + max($1.receivedFrameCount, 0) }
        return "已完成 \(monitoringTrialHistory.count) 次过程记录，最近记录编号 \(monitoringTrialHistory.last?.trialID ?? "-")，最近命令往返 \(monitoringLastCommandRoundTripMs) ms，累计接收帧 \(totalEvents)"
    }

    init() {
        loadContentSources()
        wireServices()
        applyVideoRecordingState(cameraService.recordingState)
        ensureDefaultStateExportDirectoryReady()
        refreshGatewayReachableHosts()
        refreshRelayStatusForConfiguration()
        ensurePanoramaLibraryReady()
        ensureMediaServerRunning()
        autoImportSuggestedPanoramaDirectoryIfNeeded()
        startContentSourceHealthCheck()
        Task {
            await refreshCameras()
            await refreshSnapshot(reason: "初始加载")
        }
    }

    func refreshCameras() async {
        do {
            let cameras = try await cameraService.refreshDevices()
            availableCameras = cameras
            if selectedCameraID == nil {
                selectedCameraID = cameras.first?.id
            }
            selectedCameraName = cameras.first(where: { $0.id == selectedCameraID })?.name ?? "未选择"
            refreshSupportedFormats()
        } catch {
            log("摄像头枚举失败: \(error.localizedDescription)")
        }
    }

    func startGateway() {
        guard !isGatewayRunning else { return }
        Task {
            do {
                activeStateExportFileURL = nil
                startNewMonitoringSession()
                monitoringMode = "SIL"
                refreshGatewayReachableHosts()
                ensureMediaServerRunning()
                try await refreshAndSelectDefaultCamera()
                try await cameraService.start(deviceID: selectedCameraID, qualityMode: selectedVideoQualityMode)
                try videoServer.start(port: TSJYNetwork.videoPort)
                try controlServer.start(port: TSJYNetwork.controlPort)
                
                let trimmedRelay = relayServerHost.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmedRelay.isEmpty {
                    relayTargetDescription = trimmedRelay
                    if let videoURL = makeSocketURL(host: trimmedRelay, port: 8800, path: "/provider"),
                       let controlURL = makeSocketURL(host: trimmedRelay, port: 8801, path: "/provider") {
                        relayVideoStatus = "连接中"
                        relayControlStatus = "连接中"
                        relayLastError = "无"
                        videoRelay.start(url: videoURL)
                        controlRelay.start(url: controlURL)
                    } else {
                        relayVideoStatus = "地址无效"
                        relayControlStatus = "地址无效"
                        relayLastError = "中继地址无法解析为有效 WebSocket 地址"
                    }
                } else {
                    refreshRelayStatusForConfiguration()
                }
                
                discoveryPublisher.start(
                    name: gatewayName,
                    serviceType: TSJYNetwork.bonjourType,
                    controlPort: TSJYNetwork.controlPort,
                    videoPort: TSJYNetwork.videoPort
                )
                isGatewayRunning = true
                gatewayStatus = "网关已启动"
                log("网关启动成功，视频端口 \(TSJYNetwork.videoPort)，控制端口 \(TSJYNetwork.controlPort)")
                
                // 自动启动本地 Modbus TCP Server，等待 PLC 主动连接
                connectSite()
                
                await refreshSnapshot(reason: "网关启动")
            } catch {
                let failure = "网关启动失败: \(error.localizedDescription)"
                gatewayStatus = failure
                log(failure)
                cameraService.stop(notify: false)
                videoServer.stop()
                controlServer.stop()
                videoRelay.stop()
                controlRelay.stop()
                discoveryPublisher.stop()
                isGatewayRunning = false
                connectedVideoClients = 0
                connectedControlClients = 0
                lastFrameInfo = "暂无视频帧"
                safetyManager.reset()
                await refreshSnapshot(reason: failure)
            }
        }
    }

    func stopGateway() {
        cameraService.stop()
        videoServer.stop()
        controlServer.stop()
        videoRelay.stop()
        controlRelay.stop()
        discoveryPublisher.stop()
        mediaServer.stop()
        isGatewayRunning = false
        connectedVideoClients = 0
        connectedControlClients = 0
        gatewayStatus = "已停止"
        lastFrameInfo = "暂无视频帧"
        safetyManager.reset()
        refreshRelayStatusForConfiguration()
        ensureMediaServerRunning()
        
        // 自动断开现场接口
        disconnectSite()
        
        Task { await refreshSnapshot(reason: "网关停止") }
    }

    func refreshRelayStatusForConfiguration() {
        let trimmed = relayServerHost.trimmingCharacters(in: .whitespacesAndNewlines)
        relayTargetDescription = trimmed.isEmpty ? "未配置" : trimmed
        if trimmed.isEmpty {
            relayVideoStatus = "未配置"
            relayControlStatus = "未配置"
            relayLastError = "无"
        } else if !isGatewayRunning {
            relayVideoStatus = "待连接"
            relayControlStatus = "待连接"
            relayLastError = "无"
        }
    }

    var preferredPublishedGatewayHost: String {
        let trimmed = manualGatewayHost.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return trimmed
        }
        return gatewayReachableHosts.first ?? "127.0.0.1"
    }

    var publishedVideoSocketURL: String {
        makeSocketURL(host: preferredPublishedGatewayHost, port: Int(TSJYNetwork.videoPort))?.absoluteString
            ?? "ws://127.0.0.1:\(TSJYNetwork.videoPort)"
    }

    var publishedControlSocketURL: String {
        makeSocketURL(host: preferredPublishedGatewayHost, port: Int(TSJYNetwork.controlPort))?.absoluteString
            ?? "ws://127.0.0.1:\(TSJYNetwork.controlPort)"
    }

    var publishedMediaBaseURL: String {
        makeHTTPURL(host: preferredPublishedGatewayHost, port: Int(TSJYNetwork.mediaPort))?.absoluteString
            ?? "http://127.0.0.1:\(TSJYNetwork.mediaPort)"
    }

    var panoramaLibraryDirectory: String {
        panoramaLibraryRootURL.path
    }

    var suggestedPanoramaImportPath: String? {
        FileManager.default.fileExists(atPath: suggestedPanoramaImportURL.path)
            ? suggestedPanoramaImportURL.path
            : nil
    }

    var stateExportDirectoryPath: String {
        let storedPath = UserDefaults.standard.string(forKey: Self.stateExportDirectoryDefaultsKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (storedPath?.isEmpty == false ? storedPath : Self.defaultStateExportDirectoryURL().path) ?? ""
    }

    var activeStateExportFileName: String {
        activeStateExportFileURL?.lastPathComponent ?? "未开始"
    }

    var activeStateExportFilePath: String {
        activeStateExportFileURL?.path ?? "未开始"
    }

    func startVideoRecording() {
        do {
            let fileURL = try cameraService.startRecording()
            applyVideoRecordingState(cameraService.recordingState)
            log("已开始视频录制: \(fileURL.path)")
        } catch {
            log("开始视频录制失败: \(error.localizedDescription)")
        }
    }

    func stopVideoRecording() async {
        do {
            let fileURL = try await cameraService.stopRecording()
            applyVideoRecordingState(cameraService.recordingState)
            if let fileURL {
                log("已结束视频录制: \(fileURL.path)")
            } else {
                log("已停止视频录制，但本次未写入有效视频帧")
            }
        } catch {
            log("结束视频录制失败: \(error.localizedDescription)")
        }
    }

    private var stateExportDirectoryURL: URL? {
        let path = stateExportDirectoryPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else { return nil }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    private static func defaultStateExportDirectoryURL(fileManager: FileManager = .default) -> URL {
        let desktopURL = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Desktop", isDirectory: true)
        return desktopURL.appendingPathComponent("数据记录", isDirectory: true)
    }

    func publishedVideoSocketURL(host: String) -> String {
        makeSocketURL(host: host, port: Int(TSJYNetwork.videoPort))?.absoluteString
            ?? "ws://127.0.0.1:\(TSJYNetwork.videoPort)"
    }

    func travelDirectionText(value: Int) -> String {
        switch value {
        case 1: return "前进"
        case 2: return "后退"
        default: return "停止"
        }
    }

    func rotationDirectionText(value: Int) -> String {
        switch value {
        case 1: return "顺时针"
        case 2: return "逆时针"
        default: return "停止"
        }
    }

    func configureStateExportDirectory(url: URL) {
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        UserDefaults.standard.set(url.path, forKey: Self.stateExportDirectoryDefaultsKey)
        activeStateExportFileURL = nil
        log("已设置状态导出目录: \(url.path)")
    }

    func clearStateExportDirectory() {
        UserDefaults.standard.removeObject(forKey: Self.stateExportDirectoryDefaultsKey)
        activeStateExportFileURL = nil
        ensureDefaultStateExportDirectoryReady()
        log("已恢复默认状态导出目录: \(stateExportDirectoryPath)")
    }

    func activeStateExportFileURLForTesting() -> URL? {
        activeStateExportFileURL
    }

    func exportMonitoringArtifactsForTesting(at date: Date) throws {
        try exportMonitoringArtifactsIfNeeded(at: date)
    }

    func startMonitoringRecordingForTesting(at date: Date) {
        startMonitoringRecording(at: date)
    }

    func stopMonitoringRecordingForTesting(notes: String, at date: Date) {
        stopMonitoringRecording(notes: notes, at: date)
    }

    func recordVisionOperationForTesting(
        actionName: String,
        phase: String,
        detail: String,
        commandID: String,
        roundTripMs: Int?,
        at date: Date
    ) {
        monitoringActionName = actionName
        if let roundTripMs {
            monitoringLastCommandRoundTripMs = roundTripMs
        }
        appendMonitoringProcessEvent(
            eventType: "Vision Pro 操作",
            actionName: actionName,
            phase: phase,
            detail: detail,
            commandID: commandID,
            commandRoundTripMs: roundTripMs,
            at: date
        )
    }

    func recordVideoMetricBatchForTesting(
        receivedFrameCount: Int,
        decodedFrameCount: Int,
        displayedFrameCount: Int,
        networkMissingFrameCount: Int,
        decodeDroppedFrameCount: Int,
        displayDroppedFrameCount: Int,
        latestEndToEndLatencyMs: Int,
        batchFrameCount: Int,
        at date: Date
    ) {
        monitoringReceivedFrameCount = receivedFrameCount
        monitoringDecodedFrameCount = decodedFrameCount
        monitoringDisplayedFrameCount = displayedFrameCount
        monitoringNetworkMissingFrameCount = networkMissingFrameCount
        monitoringDecodeDroppedFrameCount = decodeDroppedFrameCount
        monitoringDisplayDroppedFrameCount = displayDroppedFrameCount
        monitoringLatestEndToEndLatencyMs = latestEndToEndLatencyMs
        monitoringLastBatchSummary = "Vision Pro 已回传 \(batchFrameCount) 条视频指标"
        appendMonitoringProcessEvent(
            eventType: "视频指标",
            actionName: monitoringActionName,
            phase: "Vision Pro 回传",
            detail: monitoringLastBatchSummary,
            commandID: "",
            commandRoundTripMs: monitoringLastCommandRoundTripMs > 0 ? monitoringLastCommandRoundTripMs : nil,
            at: date
        )
    }

    func recordDetailedVideoMetricBatchForTesting(
        receivedFrameCount: Int,
        decodedFrameCount: Int,
        displayedFrameCount: Int,
        networkMissingFrameCount: Int,
        decodeDroppedFrameCount: Int,
        displayDroppedFrameCount: Int,
        latestEndToEndLatencyMs: Int,
        batchFrameCount: Int,
        clockOffsetMs: Int,
        clockRoundTripMs: Int,
        clockSyncValid: Bool,
        stallCount: Int,
        maxFrameIntervalMs: Int,
        at date: Date
    ) {
        monitoringClockOffsetMs = clockOffsetMs
        monitoringClockRoundTripMs = clockRoundTripMs
        monitoringClockSyncValid = clockSyncValid
        monitoringStallCount = stallCount
        monitoringMaxFrameIntervalMs = maxFrameIntervalMs
        recordVisionMetricBatch(
            VideoMetricBatchPayload(
                sessionID: monitoringSessionID,
                frames: [],
                receivedFrameCount: receivedFrameCount,
                decodedFrameCount: decodedFrameCount,
                displayedFrameCount: displayedFrameCount,
                networkMissingFrameCount: networkMissingFrameCount,
                decodeDroppedFrameCount: decodeDroppedFrameCount,
                displayDroppedFrameCount: displayDroppedFrameCount,
                latestEndToEndLatencyMs: latestEndToEndLatencyMs,
                clockOffsetMs: clockOffsetMs,
                clockRoundTripMs: clockRoundTripMs,
                clockSyncValid: clockSyncValid,
                stallCount: stallCount,
                maxFrameIntervalMs: maxFrameIntervalMs
            ),
            receivedAt: date
        )
        appendMonitoringProcessEvent(
            eventType: "视频监测批次",
            actionName: monitoringActionName,
            phase: "视频链路",
            detail: "批次帧数 \(batchFrameCount)，同步 \(clockSyncValid ? "有效" : "无效")",
            commandID: "",
            commandRoundTripMs: nil,
            at: date
        )
    }

    func recordCommandLifecycleForTesting(
        actionName: String,
        commandID: String,
        clientSendTime: Date?,
        gatewayReceiveTime: Date?,
        registerWriteTime: Date?,
        simulatorReadTime: Date?,
        feedbackWriteTime: Date?,
        vpFeedbackRenderTime: Date?,
        expectedFeedback: String,
        actualFeedback: String,
        feedbackMatched: Bool,
        finalResult: String,
        failureStage: String,
        blockLayer: String,
        scenarioID: String,
        validSample: Bool,
        invalidReason: String,
        repeatIndex: Int,
        jogCycleID: String,
        at date: Date
    ) {
        monitoringActionName = actionName
        monitoringScenarioID = scenarioID
        monitoringRepeatIndex = repeatIndex
        monitoringJogCycleID = jogCycleID
        let feedbackInfo = feedbackComponents(for: expectedFeedback)
        commandLifecycleRecords[commandID] = CommandLifecycleRecord(
            sessionID: monitoringSessionID,
            trialID: monitoringTrialID,
            commandID: commandID,
            action: actionName,
            commandSemantic: commandSemantic(for: actionName),
            repeatIndex: repeatIndex,
            scenarioID: scenarioID,
            jogCycleID: jogCycleID,
            clientSendTimestamp: clientSendTime?.timeIntervalSince1970,
            gatewayReceiveTimestamp: gatewayReceiveTime?.timeIntervalSince1970,
            validationFinishTimestamp: gatewayReceiveTime?.timeIntervalSince1970,
            registerWriteTimestamp: registerWriteTime?.timeIntervalSince1970,
            simulatorReadTimestamp: simulatorReadTime?.timeIntervalSince1970,
            logicFinishTimestamp: feedbackWriteTime?.timeIntervalSince1970,
            feedbackWriteTimestamp: feedbackWriteTime?.timeIntervalSince1970,
            plcFeedbackTimestamp: feedbackWriteTime?.timeIntervalSince1970,
            deviceFeedbackTimestamp: feedbackWriteTime?.timeIntervalSince1970,
            resultSendTimestamp: vpFeedbackRenderTime?.timeIntervalSince1970,
            vpFeedbackRenderTimestamp: vpFeedbackRenderTime?.timeIntervalSince1970,
            accepted: finalResult != "REJECTED",
            rejectionReason: invalidReason,
            expectedFeedback: expectedFeedback,
            targetFeedbackName: feedbackInfo.name,
            targetFeedbackExpectedValue: feedbackInfo.value,
            targetFeedbackBeforeValue: "",
            targetFeedbackCurrentValue: feedbackInfo.value,
            feedbackBefore: "",
            actualFeedback: actualFeedback,
            feedbackAfter: actualFeedback,
            feedbackChanged: !actualFeedback.isEmpty,
            feedbackChangeTimestamp: actualFeedback.isEmpty ? nil : date.timeIntervalSince1970,
            feedbackMatched: feedbackMatched,
            feedbackWaitStartTimestamp: registerWriteTime?.timeIntervalSince1970 ?? clientSendTime?.timeIntervalSince1970,
            feedbackMatchedTimestamp: feedbackMatched ? date.timeIntervalSince1970 : nil,
            feedbackTimeoutTimestamp: finalResult == "TIMEOUT" ? date.timeIntervalSince1970 : nil,
            feedbackWaitDurationMs: responseDurationMs(
                from: registerWriteTime?.timeIntervalSince1970 ?? clientSendTime?.timeIntervalSince1970,
                to: (feedbackMatched || finalResult == "TIMEOUT") ? date.timeIntervalSince1970 : nil
            ),
            finalResult: finalResult,
            failureStage: failureStage,
            responseTimeoutMs: monitoringResponseTimeoutMs,
            validSample: validSample,
            invalidReason: invalidReason,
            blockLayer: blockLayer,
            blockReason: invalidReason,
            simulatorAccepted: finalResult == "REJECTED" ? false : nil,
            simulatorResultCode: nil,
            simulatorRejectReason: invalidReason,
            simulatorExecutedAction: actionName,
            unexpectedMotion: false,
            startCommandID: "",
            stopCommandID: finalResult == "REJECTED" ? commandID : "",
            holdDurationMs: nil,
            startResponseMs: responseDurationMs(
                from: clientSendTime?.timeIntervalSince1970,
                to: feedbackWriteTime?.timeIntervalSince1970
            ),
            stopResponseMs: isStopAction(actionName) ? responseDurationMs(
                from: clientSendTime?.timeIntervalSince1970,
                to: feedbackWriteTime?.timeIntervalSince1970
            ) : nil,
            stopSuccessful: isStopAction(actionName) ? (finalResult == "SUCCESS") : nil
        )
        if let clientSendTime, let vpFeedbackRenderTime {
            monitoringLastCommandRoundTripMs = max(0, Int(vpFeedbackRenderTime.timeIntervalSince(clientSendTime) * 1000))
        }
        appendMonitoringProcessEvent(
            eventType: "命令判定",
            actionName: actionName,
            phase: finalResult,
            detail: actualFeedback.isEmpty ? expectedFeedback : "\(expectedFeedback) -> \(actualFeedback)",
            commandID: commandID,
            commandRoundTripMs: monitoringLastCommandRoundTripMs > 0 ? monitoringLastCommandRoundTripMs : nil,
            at: date
        )
    }

    func queuePendingCommandLifecycleForTesting(
        action: String,
        commandID: String,
        clientSendTime: Date?,
        gatewayReceiveTime: Date?
    ) {
        let actionCode = actionCode(forDisplayName: action)
        let jogCycleID = resolveJogCycleID(for: actionCode, commandID: commandID, clientSendTimestamp: clientSendTime?.timeIntervalSince1970)
        let expectedFeedback = expectedFeedbackText(for: actionCode)
        let feedbackInfo = feedbackComponents(for: expectedFeedback)
        commandLifecycleRecords[commandID] = CommandLifecycleRecord(
            sessionID: monitoringSessionID,
            trialID: monitoringTrialID,
            commandID: commandID,
            action: actionCode,
            commandSemantic: commandSemantic(for: actionCode),
            repeatIndex: monitoringRepeatIndex,
            scenarioID: monitoringScenarioID,
            jogCycleID: jogCycleID,
            clientSendTimestamp: clientSendTime?.timeIntervalSince1970,
            gatewayReceiveTimestamp: gatewayReceiveTime?.timeIntervalSince1970,
            validationFinishTimestamp: gatewayReceiveTime?.timeIntervalSince1970,
            registerWriteTimestamp: gatewayReceiveTime?.timeIntervalSince1970,
            simulatorReadTimestamp: nil,
            logicFinishTimestamp: nil,
            feedbackWriteTimestamp: nil,
            plcFeedbackTimestamp: nil,
            deviceFeedbackTimestamp: nil,
            resultSendTimestamp: nil,
            vpFeedbackRenderTimestamp: nil,
            accepted: true,
            rejectionReason: "",
            expectedFeedback: expectedFeedback,
            targetFeedbackName: feedbackInfo.name,
            targetFeedbackExpectedValue: feedbackInfo.value,
            targetFeedbackBeforeValue: "",
            targetFeedbackCurrentValue: "",
            feedbackBefore: currentFeedbackSnapshotSummary(),
            actualFeedback: "",
            feedbackAfter: "",
            feedbackChanged: nil,
            feedbackChangeTimestamp: nil,
            feedbackMatched: nil,
            feedbackWaitStartTimestamp: gatewayReceiveTime?.timeIntervalSince1970,
            feedbackMatchedTimestamp: nil,
            feedbackTimeoutTimestamp: nil,
            feedbackWaitDurationMs: nil,
            finalResult: "WAITING_FEEDBACK",
            failureStage: "",
            responseTimeoutMs: monitoringResponseTimeoutMs,
            validSample: true,
            invalidReason: "",
            blockLayer: "NOT_BLOCKED",
            blockReason: "",
            simulatorAccepted: nil,
            simulatorResultCode: nil,
            simulatorRejectReason: "",
            simulatorExecutedAction: actionCode,
            unexpectedMotion: false,
            startCommandID: actionCode == "stopTravel" || actionCode == "stopRotation" ? activeStartCommandID(for: actionCode) : commandID,
            stopCommandID: actionCode == "stopTravel" || actionCode == "stopRotation" ? commandID : "",
            holdDurationMs: holdDurationMs(for: actionCode, stopClientSendTimestamp: clientSendTime?.timeIntervalSince1970),
            startResponseMs: nil,
            stopResponseMs: nil,
            stopSuccessful: nil
        )
        pendingPLCFeedbackCommandIDs.append(commandID)
    }

    func recordPLCFeedbackForTesting(summary: String, at date: Date) {
        recordPLCFeedback(summary: summary, receivedAt: date.timeIntervalSince1970)
    }

    func applySimulatorLifecycleReportForTesting(
        commandID: String,
        simulatorReadTime: Date?,
        logicFinishTime: Date?,
        feedbackWriteTime: Date?,
        feedbackValues: [String: Double],
        detail: String,
        accepted: Bool? = nil,
        resultCode: Int? = nil,
        rejectReason: String = "",
        executedAction: String = "",
        at date: Date
    ) {
        applySimulatorLifecycleReport(
            SimulatorLifecycleReport(
                commandID: commandID,
                simulatorReadTimestamp: simulatorReadTime?.timeIntervalSince1970,
                logicFinishTimestamp: logicFinishTime?.timeIntervalSince1970,
                feedbackWriteTimestamp: feedbackWriteTime?.timeIntervalSince1970,
                feedbackSummary: makeFeedbackSummary(from: feedbackValues),
                detail: detail,
                accepted: accepted,
                resultCode: resultCode,
                rejectReason: rejectReason,
                executedAction: executedAction
            ),
            receivedAt: date.timeIntervalSince1970
        )
    }

    func commandLifecycleOutcomeForTesting(commandID: String) -> CommandLifecycleOutcome? {
        guard let record = commandLifecycleRecords[commandID] else { return nil }
        return CommandLifecycleOutcome(
            actualFeedback: record.actualFeedback,
            feedbackMatched: record.feedbackMatched,
            finalResult: record.finalResult
        )
    }

    func startNewMonitoringSession() {
        monitoringSessionID = Self.makeMonitoringSessionID()
        monitoringNextTrialIndex = 1
        monitoringTrialID = Self.makeMonitoringTrialID(index: monitoringNextTrialIndex)
        monitoringCurrentTrialStartedAt = nil
        monitoringCurrentTrialState = "未录制"
        monitoringMode = "SIL"
        monitoringRepeatIndex = 1
        monitoringScenarioID = "normal_operation"
        monitoringJogCycleID = ""
        monitoringTrialHistory.removeAll(keepingCapacity: true)
        monitoringCommandCount = 0
        monitoringCommandSuccessCount = 0
        monitoringLastCommandRoundTripMs = 0
        monitoringReceivedFrameCount = 0
        monitoringDecodedFrameCount = 0
        monitoringDisplayedFrameCount = 0
        monitoringStartReceivedFrameCount = 0
        monitoringStartDecodedFrameCount = 0
        monitoringStartDisplayedFrameCount = 0
        monitoringNetworkMissingFrameCount = 0
        monitoringDecodeDroppedFrameCount = 0
        monitoringDisplayDroppedFrameCount = 0
        monitoringStartNetworkMissingFrameCount = 0
        monitoringStartDecodeDroppedFrameCount = 0
        monitoringStartDisplayDroppedFrameCount = 0
        monitoringLatestEndToEndLatencyMs = 0
        monitoringLastBatchSummary = "尚未收到 Vision Pro 监测数据"
        commandLifecycleRecords.removeAll(keepingCapacity: true)
        pendingPLCFeedbackCommandIDs.removeAll(keepingCapacity: true)
        monitoringProcessEvents.removeAll(keepingCapacity: true)
        activeStateExportFileURL = nil
    }

    func startMonitoringRecording() {
        startMonitoringRecording(at: .now)
    }

    func stopMonitoringRecording(notes: String = "") {
        stopMonitoringRecording(notes: notes, at: .now)
    }

    func beginMonitoringTrial() {
        startMonitoringRecording()
    }

    func completeMonitoringTrial(success: Bool, notes: String = "") {
        let resultNote = success ? "过程结束：成功" : "过程结束：失败"
        stopMonitoringRecording(notes: notes.isEmpty ? resultNote : "\(resultNote)；\(notes)")
    }

    func invalidateMonitoringTrial(notes: String = "") {
        stopMonitoringRecording(notes: notes.isEmpty ? "过程结束：无效样本" : "过程结束：无效样本；\(notes)")
    }

    private func startMonitoringRecording(at date: Date) {
        guard monitoringCurrentTrialStartedAt == nil else { return }
        activeStateExportFileURL = nil
        monitoringCurrentTrialStartedAt = date
        monitoringCurrentTrialState = "录制中"
        monitoringStartReceivedFrameCount = monitoringReceivedFrameCount
        monitoringStartDecodedFrameCount = monitoringDecodedFrameCount
        monitoringStartDisplayedFrameCount = monitoringDisplayedFrameCount
        monitoringStartNetworkMissingFrameCount = monitoringNetworkMissingFrameCount
        monitoringStartDecodeDroppedFrameCount = monitoringDecodeDroppedFrameCount
        monitoringStartDisplayDroppedFrameCount = monitoringDisplayDroppedFrameCount
        monitoringProcessEvents.removeAll(keepingCapacity: true)
        appendMonitoringProcessEvent(
            eventType: "记录开始",
            actionName: monitoringActionName,
            phase: "开始",
            detail: "开始记录 Vision Pro 操作过程",
            commandID: "",
            commandRoundTripMs: nil,
            at: date
        )
        Task {
            await refreshSnapshot(reason: "开始试验记录")
            broadcastSnapshot(type: "status", message: "开始试验记录")
        }
    }

    private func stopMonitoringRecording(notes: String, at date: Date) {
        guard let startedAt = monitoringCurrentTrialStartedAt else { return }
        appendMonitoringProcessEvent(
            eventType: "记录结束",
            actionName: monitoringActionName,
            phase: "结束",
            detail: notes.isEmpty ? "结束记录" : notes,
            commandID: "",
            commandRoundTripMs: monitoringLastCommandRoundTripMs > 0 ? monitoringLastCommandRoundTripMs : nil,
            at: date
        )

        let assembler = latestSnapshot.devices.first(where: { $0.id == "assembler" })
        let props = assembler?.properties ?? [:]
        monitoringTrialHistory.append(
            MonitoringTrialRecord(
                sessionID: monitoringSessionID,
                trialID: monitoringTrialID,
                conditionName: monitoringConditionName,
                actionName: monitoringActionName,
                operatorID: monitoringOperatorID,
                mode: monitoringMode,
                startedAt: startedAt,
                finishedAt: date,
                validSample: true,
                success: true,
                commandRoundTripMs: monitoringLastCommandRoundTripMs,
                endToEndLatencyMs: monitoringLatestEndToEndLatencyMs,
                receivedFrameCount: deltaCount(current: monitoringReceivedFrameCount, start: monitoringStartReceivedFrameCount),
                decodedFrameCount: deltaCount(current: monitoringDecodedFrameCount, start: monitoringStartDecodedFrameCount),
                displayedFrameCount: deltaCount(current: monitoringDisplayedFrameCount, start: monitoringStartDisplayedFrameCount),
                networkMissingFrameCount: deltaCount(current: monitoringNetworkMissingFrameCount, start: monitoringStartNetworkMissingFrameCount),
                decodeDroppedFrameCount: deltaCount(current: monitoringDecodeDroppedFrameCount, start: monitoringStartDecodeDroppedFrameCount),
                displayDroppedFrameCount: deltaCount(current: monitoringDisplayDroppedFrameCount, start: monitoringStartDisplayDroppedFrameCount),
                gatewayStatus: latestSnapshot.gatewayStatus,
                siteStatus: latestSnapshot.siteStatus,
                lockState: latestSnapshot.lockState,
                heartbeatPLC: Int(props["heartbeatPLC"] ?? 0),
                assemblerRunning: props["assemblerRunning"] == 1.0,
                vacuumBoxReady: props["vacuumBoxReady"] == 1.0,
                vacuumFault: props["vacuumFault"] == 1.0,
                pumpFault: props["pumpFault"] == 1.0,
                notes: notes
            )
        )

        do {
            try exportMonitoringArtifactsIfNeeded(at: date)
            monitoringCurrentTrialState = "已结束并导出"
        } catch {
            monitoringCurrentTrialState = "结束但导出失败"
            log("试验记录导出失败: \(error.localizedDescription)")
        }

        monitoringCurrentTrialStartedAt = nil
        monitoringNextTrialIndex += 1
        monitoringTrialID = Self.makeMonitoringTrialID(index: monitoringNextTrialIndex)
        Task {
            await refreshSnapshot(reason: "结束试验记录")
            broadcastSnapshot(type: "status", message: "结束试验记录")
        }
    }

    func publishedControlSocketURL(host: String) -> String {
        makeSocketURL(host: host, port: Int(TSJYNetwork.controlPort))?.absoluteString
            ?? "ws://127.0.0.1:\(TSJYNetwork.controlPort)"
    }

    func publishedMediaFileURL(relativePath: String, host: String? = nil) -> String {
        let targetHost = (host?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 }
            ?? preferredPublishedGatewayHost
        guard var components = makeHTTPComponents(host: targetHost, port: Int(TSJYNetwork.mediaPort)) else {
            return "http://127.0.0.1:\(TSJYNetwork.mediaPort)/media"
        }
        let encodedPath = relativePath
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)
        components.percentEncodedPath = "/media/" + encodedPath.map {
            $0.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? $0
        }.joined(separator: "/")
        return components.url?.absoluteString ?? "http://127.0.0.1:\(TSJYNetwork.mediaPort)/media"
    }

    private func makeSocketURL(host: String, port: Int, path: String = "") -> URL? {
        var components = URLComponents()
        components.scheme = "ws"
        applyNormalizedHost(normalizedURLHost(host), to: &components)
        components.port = port
        components.path = path
        return components.url
    }

    private func makeHTTPURL(host: String, port: Int, path: String = "") -> URL? {
        var components = makeHTTPComponents(host: host, port: port)
        components?.path = path
        return components?.url
    }

    private func makeHTTPComponents(host: String, port: Int) -> URLComponents? {
        var components = URLComponents()
        components.scheme = "http"
        applyNormalizedHost(normalizedURLHost(host), to: &components)
        components.port = port
        return components.url == nil ? nil : components
    }

    private func normalizedURLHost(_ host: String) -> String {
        let trimmed = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }
        if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
            return String(trimmed.dropFirst().dropLast())
        }
        return trimmed
    }

    private func applyNormalizedHost(_ host: String, to components: inout URLComponents) {
        if looksLikeIPv6Literal(host) {
            components.percentEncodedHost = "[\(host)]"
        } else {
            components.host = host
        }
    }

    private func looksLikeIPv6Literal(_ host: String) -> Bool {
        host.filter { $0 == ":" }.count >= 2
    }

    func importSuggestedPanoramaDirectory() {
        guard let path = suggestedPanoramaImportPath else {
            log("默认 360 素材目录不存在")
            return
        }
        importPanoramaDirectory(url: URL(fileURLWithPath: path, isDirectory: true))
    }

    func importPanoramaDirectory(url: URL) {
        ensurePanoramaLibraryReady()
        do {
            let sources = try buildPanoramaSources(fromDirectory: url)
            applyImportedPanoramaSources(
                sources,
                reason: "已导入目录 \(url.lastPathComponent)"
            )
        } catch {
            log("导入全景目录失败: \(error.localizedDescription)")
        }
    }

    func importPanoramaFiles(urls: [URL]) {
        ensurePanoramaLibraryReady()
        do {
            let sources = try buildPanoramaSources(fromFiles: urls)
            applyImportedPanoramaSources(
                sources,
                reason: "已导入 \(sources.count) 个全景文件"
            )
        } catch {
            log("导入全景文件失败: \(error.localizedDescription)")
        }
    }

    func connectSite() {
        Task {
            do {
                try await siteBridge.connect(to: siteEndpointText)
            } catch {
                log("连接现场接口失败，将继续使用模拟设备: \(error.localizedDescription)")
            }
            await refreshSnapshot(reason: "现场连接变化")
        }
    }

    func disconnectSite() {
        Task {
            await siteBridge.disconnect()
            await refreshSnapshot(reason: "现场断开")
        }
    }

    func sendMockEmergencyStop() {
        Task {
            _ = await siteBridge.emergencyStop(reason: "来自 Mac 控制台")
            safetyManager.forceEmergencyStop(reason: "Mac 本地急停")
            await refreshSnapshot(reason: "Mac 急停")
            broadcastSnapshot(type: "alarm", message: "已触发急停")
        }
    }

    func releaseEmergencyStop() {
        Task {
            let result = safetyManager.releaseEmergencyStopLocally()
            _ = await siteBridge.releaseEmergencyStop(reason: "来自 Mac 控制台解除急停")
            await refreshSnapshot(reason: "Mac 解除急停")
            broadcastSnapshot(type: "status", message: result.message)
            log(result.message)
        }
    }

    func executeLocalSiteCommand(deviceID: String, action: String, parameters: [String: Double] = [:]) {
        Task {
            let commandID = UUID().uuidString
            let result = await siteBridge.execute(deviceID: deviceID, action: action, parameters: parameters, commandID: commandID)
            await refreshSnapshot(reason: "本地执行: " + result.message)
            broadcastSnapshot(type: "status", message: result.message)
        }
    }

    func updateSourceLayout(_ layout: PanoramaSourceLayout) {
        panoramaSettings.sourceLayout = layout
        log("输入布局切换为 \(layout.displayName)")
    }

    func selectCamera(id: String) {
        selectedCameraID = id
        selectedCameraName = availableCameras.first(where: { $0.id == id })?.name ?? "未选择"
        refreshSupportedFormats()
    }

    func updateVideoQualityMode(_ qualityMode: VideoQualityMode) {
        let previous = selectedVideoQualityMode
        guard previous != qualityMode else { return }
        selectedVideoQualityMode = qualityMode
        log("视频画质切换为 \(qualityMode.displayName)")

        guard isGatewayRunning else { return }
        Task {
            do {
                try await cameraService.start(deviceID: selectedCameraID, qualityMode: qualityMode)
                await refreshSnapshot(reason: "视频画质切换为 \(qualityMode.displayName)")
            } catch {
                selectedVideoQualityMode = previous
                log("视频画质切换失败: \(error.localizedDescription)")
            }
        }
    }

    func selectContentSource(id: String?) {
        selectedContentSourceID = id
    }

    func addContentSource(type: ContentSourceType) {
        let nextOrder = (contentSources.map(\.sortOrder).max() ?? 0) + 1
        let source: ContentSourceItem
        switch type {
        case .url:
            source = .makeURL(
                id: "source-\(UUID().uuidString.lowercased())",
                name: "新建URL源",
                url: "https://",
                sortOrder: nextOrder,
                group: "默认"
            )
        case .video:
            source = .makeVideo(
                id: "source-\(UUID().uuidString.lowercased())",
                name: "新建VIDEO源",
                streamUrl: "https://",
                sortOrder: nextOrder,
                group: "默认"
            )
        case .panoramaPhoto:
            source = .makePanoramaPhoto(
                id: "source-\(UUID().uuidString.lowercased())",
                name: "新建全景照片",
                mediaURL: "http://",
                localFilePath: "",
                mediaRelativePath: "",
                mediaMimeType: "image/jpeg",
                sortOrder: nextOrder,
                group: "全景素材"
            )
        case .panoramaVideo:
            source = .makePanoramaVideo(
                id: "source-\(UUID().uuidString.lowercased())",
                name: "新建全景视频",
                mediaURL: "http://",
                localFilePath: "",
                mediaRelativePath: "",
                mediaMimeType: "video/mp4",
                sortOrder: nextOrder,
                group: "全景素材"
            )
        }
        upsertContentSource(source)
        selectedContentSourceID = source.id
    }

    func upsertContentSource(_ source: ContentSourceItem) {
        if let index = contentSources.firstIndex(where: { $0.id == source.id }) {
            var updated = source
            updated.updatedAt = ContentSourceItem.nowISO()
            if updated.createdAt.isEmpty {
                updated.createdAt = contentSources[index].createdAt
            }
            contentSources[index] = updated
        } else {
            var inserted = source
            let ts = ContentSourceItem.nowISO()
            if inserted.createdAt.isEmpty { inserted.createdAt = ts }
            inserted.updatedAt = ts
            contentSources.append(inserted)
        }
        sortContentSources()
        saveContentSources()
        selectedContentSourceID = source.id
        syncContentSourcesToClients(reason: "内容源已保存：\(source.name)")
    }

    func removeSelectedContentSource() {
        guard let id = selectedContentSourceID else { return }
        contentSources.removeAll { $0.id == id }
        sortContentSources()
        saveContentSources()
        selectedContentSourceID = contentSources.first?.id
        syncContentSourcesToClients(reason: "内容源已删除")
    }

    func moveSelectedContentSourceUp() {
        guard let id = selectedContentSourceID,
              let index = contentSources.firstIndex(where: { $0.id == id }),
              index > 0 else { return }
        contentSources.swapAt(index, index - 1)
        normalizeContentSourceOrder()
        saveContentSources()
        syncContentSourcesToClients(reason: "内容源排序已更新")
    }

    func moveSelectedContentSourceDown() {
        guard let id = selectedContentSourceID,
              let index = contentSources.firstIndex(where: { $0.id == id }),
              index < contentSources.count - 1 else { return }
        contentSources.swapAt(index, index + 1)
        normalizeContentSourceOrder()
        saveContentSources()
        syncContentSourcesToClients(reason: "内容源排序已更新")
    }

    func refreshContentSourceStatus() {
        Task {
            var updated = contentSources
            for index in updated.indices {
                let source = updated[index]
                let target = distributedURLString(for: source)
                guard let target, let url = URL(string: target) else {
                    updated[index].lastStatus = "invalid-url"
                    updated[index].lastCheckedAt = ContentSourceItem.nowISO()
                    continue
                }
                var request = URLRequest(url: url)
                request.httpMethod = "HEAD"
                request.timeoutInterval = 3
                do {
                    let (_, response) = try await URLSession.shared.data(for: request)
                    if let http = response as? HTTPURLResponse, (200...399).contains(http.statusCode) {
                        updated[index].lastStatus = "ok"
                    } else {
                        updated[index].lastStatus = "http-error"
                    }
                } catch {
                    updated[index].lastStatus = "unreachable"
                }
                updated[index].lastCheckedAt = ContentSourceItem.nowISO()
            }
            contentSources = updated
            saveContentSources()
            syncContentSourcesToClients(reason: "内容源状态已刷新")
        }
    }

    func syncContentSourcesToVision() {
        saveContentSources()
        syncContentSourcesToClients(reason: "已同步内容源到 Vision Pro")
    }

    private func wireServices() {
        cameraService.onStatus = { [weak self] status in
            Task { @MainActor in
                self?.gatewayStatus = status
                self?.log(status)
            }
        }
        cameraService.onDevicesChanged = { [weak self] devices in
            Task { @MainActor in
                self?.availableCameras = devices
                if self?.selectedCameraID == nil {
                    self?.selectedCameraID = devices.first?.id
                }
                self?.selectedCameraName = devices.first(where: { $0.id == self?.selectedCameraID })?.name ?? "未选择"
                self?.refreshSupportedFormats()
            }
        }
        cameraService.onPreviewFrames = { [weak self] raw, processed in
            Task { @MainActor in
                self?.rawPreviewImage = raw
                self?.processedPreviewImage = processed
                self?.updateRawFrameMetadata(using: raw)
            }
        }
        cameraService.onRecordingStateChanged = { [weak self] state in
            Task { @MainActor in
                self?.applyVideoRecordingState(state)
            }
        }
        cameraService.onEncodedFrame = { [weak self] frame in
            guard let self else { return }
            videoServer.broadcast(frame: frame)
            videoRelay.broadcast(frame: frame)
            Task { @MainActor in
                self.lastFrameInfo = "已发送 H.264 帧 #\(frame.sequence)  \(frame.width)x\(frame.height)  \(frame.payload.count / 1024) KB"
                self.recordVideoSenderMetric(frame)
            }
        }
        cameraService.onVideoConfiguration = { [weak self] configuration in
            Task { @MainActor in
                self?.currentVideoConfiguration = configuration
                self?.videoServer.update(configuration: configuration)
                self?.videoRelay.update(configuration: configuration)
            }
        }

        videoServer.onClientCountChanged = { [weak self] count in
            Task { @MainActor in
                self?.connectedVideoClients = count
                self?.broadcastSnapshot(type: "status", message: "视频客户端数变化")
            }
        }
        videoServer.update(configuration: currentVideoConfiguration)
        videoServer.onLog = { [weak self] text in
            Task { @MainActor in self?.log(text) }
        }

        controlServer.onClientCountChanged = { [weak self] count in
            Task { @MainActor in
                self?.connectedControlClients = count
                self?.broadcastSnapshot(type: "status", message: "控制客户端数变化")
            }
        }
        controlServer.onMessage = { [weak self] text, peer in
            guard let self else { return }
            Task {
                await self.handleControlMessage(text, from: peer)
            }
        }
        controlServer.onLog = { [weak self] text in
            Task { @MainActor in self?.log(text) }
        }
        
        videoRelay.onLog = { [weak self] text in
            Task { @MainActor in
                if text.contains("失败") || text.contains("断开") {
                    self?.relayLastError = text
                }
                self?.log(text)
            }
        }
        videoRelay.onStatusChanged = { [weak self] status in
            Task { @MainActor in
                self?.relayVideoStatus = status
            }
        }
        controlRelay.onMessage = { [weak self] text in
            guard let self else { return }
            Task {
                await self.handleRelayControlMessage(text)
            }
        }
        controlRelay.onLog = { [weak self] text in
            Task { @MainActor in
                if text.contains("失败") || text.contains("断开") {
                    self?.relayLastError = text
                }
                self?.log(text)
            }
        }
        controlRelay.onStatusChanged = { [weak self] status in
            Task { @MainActor in
                self?.relayControlStatus = status
            }
        }
        
        mediaServer.onLog = { [weak self] text in
            Task { @MainActor in self?.log(text) }
        }

        siteBridge.onStateChanged = { [weak self] state in
            Task { @MainActor in
                self?.siteStatus = state
                self?.monitoringMode = "SIL"
                await self?.refreshSnapshot(reason: "现场状态更新")
                self?.broadcastSnapshot(type: "status", message: state)
            }
        }
        siteBridge.onLog = { [weak self] text in
            Task { @MainActor in
                self?.log(text)
                if text.contains("PLC 写入本地 Modbus 寄存器") {
                    self?.broadcastSnapshot(type: "status", message: "PLC 已反馈: \(text)")
                }
            }
        }
        siteBridge.onPLCFeedback = { [weak self] summary in
            Task { @MainActor in
                self?.recordPLCFeedback(summary: summary)
            }
        }
        siteBridge.onSimulatorLifecycle = { [weak self] report in
            Task { @MainActor in
                self?.applySimulatorLifecycleReport(report, receivedAt: Date().timeIntervalSince1970)
            }
        }
    }

    private func refreshAndSelectDefaultCamera() async throws {
        let cameras = try await cameraService.refreshDevices()
        availableCameras = cameras
        if selectedCameraID == nil || !cameras.contains(where: { $0.id == selectedCameraID }) {
            selectedCameraID = cameras.first?.id
        }
        selectedCameraName = cameras.first(where: { $0.id == selectedCameraID })?.name ?? "未选择"
        refreshSupportedFormats()
    }

    private func refreshSupportedFormats() {
        supportedFormats = cameraService.supportedFormats(deviceID: selectedCameraID)
    }

    private func ensurePanoramaLibraryReady() {
        do {
            try FileManager.default.createDirectory(at: panoramaLibraryRootURL, withIntermediateDirectories: true)
        } catch {
            log("创建全景素材库目录失败: \(error.localizedDescription)")
        }
    }

    private func ensureMediaServerRunning() {
        ensurePanoramaLibraryReady()
        do {
            try mediaServer.start(port: TSJYNetwork.mediaPort, rootDirectory: panoramaLibraryRootURL)
        } catch {
            log("启动素材 HTTP 服务失败: \(error.localizedDescription)")
        }
    }

    private func applyVideoRecordingState(_ state: VideoRecordingState) {
        videoRecordingDirectoryPath = state.directoryURL.path
        videoRecordingStatus = state.statusText
        isVideoRecording = state.isRecording
        activeVideoRecordingFilePath = state.currentFileURL?.path
            ?? state.lastCompletedFileURL?.path
            ?? "未开始"
    }

    private func autoImportSuggestedPanoramaDirectoryIfNeeded() {
        guard contentSources.allSatisfy({ !$0.type.isPanoramaScene }),
              FileManager.default.fileExists(atPath: suggestedPanoramaImportURL.path) else {
            return
        }
        importPanoramaDirectory(url: suggestedPanoramaImportURL)
    }

    private func ensureDefaultStateExportDirectoryReady() {
        guard let directoryURL = stateExportDirectoryURL else { return }
        try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }

    private func distributedURLString(for source: ContentSourceItem) -> String? {
        switch source.type {
        case .url:
            return source.url
        case .video, .panoramaPhoto, .panoramaVideo:
            if let relativePath = source.mediaRelativePath, !relativePath.isEmpty {
                return publishedMediaFileURL(relativePath: relativePath)
            }
            return source.streamUrl
        }
    }

    private func resolvedContentSourceForDistribution(_ source: ContentSourceItem) -> ContentSourceItem {
        var resolved = source
        if let distributed = distributedURLString(for: source) {
            resolved.streamUrl = distributed
        }
        if source.type == .url {
            resolved.streamUrl = nil
        }
        return resolved
    }

    private func applyImportedPanoramaSources(_ sources: [ContentSourceItem], reason: String) {
        guard !sources.isEmpty else {
            log("未发现可导入的全景素材")
            return
        }

        var merged = contentSources
        for source in sources {
            if let index = merged.firstIndex(where: { $0.id == source.id || ($0.localFilePath == source.localFilePath && source.localFilePath != nil) }) {
                var updated = source
                updated.createdAt = merged[index].createdAt
                updated.updatedAt = ContentSourceItem.nowISO()
                merged[index] = updated
            } else {
                merged.append(source)
            }
        }

        contentSources = merged
        sortContentSources()
        saveContentSources()
        selectedContentSourceID = sources.last?.id
        syncContentSourcesToClients(reason: reason)
    }

    private func buildPanoramaSources(fromDirectory directoryURL: URL) throws -> [ContentSourceItem] {
        let fileManager = FileManager.default
        var importedSources: [ContentSourceItem] = []
        let importRootName = sanitizedImportFolderName(directoryURL.lastPathComponent, fallback: "360素材")
        guard let enumerator = fileManager.enumerator(
            at: directoryURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        for case let fileURL as URL in enumerator {
            let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
            guard values.isRegularFile == true else { continue }
            guard isSupportedPanoramaFile(fileURL) else { continue }

            let relativeInputPath = fileURL.path.replacingOccurrences(of: directoryURL.path + "/", with: "")
            let relativeLibraryPath = importRootName + "/" + relativeInputPath
            if let source = try buildPanoramaSource(
                fromFile: fileURL,
                relativeLibraryPath: relativeLibraryPath,
                group: directoryURL.lastPathComponent
            ) {
                importedSources.append(source)
            }
        }
        return importedSources.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private func buildPanoramaSources(fromFiles urls: [URL]) throws -> [ContentSourceItem] {
        var importedSources: [ContentSourceItem] = []
        let importRootName = "手动导入"
        for fileURL in urls {
            guard isSupportedPanoramaFile(fileURL) else { continue }
            let relativeLibraryPath = importRootName + "/" + fileURL.lastPathComponent
            if let source = try buildPanoramaSource(
                fromFile: fileURL,
                relativeLibraryPath: relativeLibraryPath,
                group: "全景素材"
            ) {
                importedSources.append(source)
            }
        }
        return importedSources.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private func buildPanoramaSource(
        fromFile fileURL: URL,
        relativeLibraryPath: String,
        group: String
    ) throws -> ContentSourceItem? {
        guard let kind = panoramaKind(for: fileURL) else {
            return nil
        }

        let destinationURL = panoramaLibraryRootURL.appendingPathComponent(relativeLibraryPath)
        try FileManager.default.createDirectory(
            at: destinationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }
        try FileManager.default.copyItem(at: fileURL, to: destinationURL)

        let mediaRelativePath = relativeLibraryPath
            .split(separator: "/", omittingEmptySubsequences: true)
            .joined(separator: "/")
        let existing = contentSources.first { $0.localFilePath == destinationURL.path }
        let sourceID = existing?.id ?? makePanoramaSourceID(relativePath: mediaRelativePath)
        let nextOrder = existing?.sortOrder ?? ((contentSources.map(\.sortOrder).max() ?? 0) + 1 + max(0, contentSources.count / 1000))
        let mediaURL = publishedMediaFileURL(relativePath: mediaRelativePath)
        let mimeType = Self.mediaMimeType(for: fileURL)
        let description = "来自 Mac 本地导入的 360 \(kind == .photo ? "照片" : "视频")"

        switch kind {
        case .photo:
            return ContentSourceItem.makePanoramaPhoto(
                id: sourceID,
                name: fileURL.deletingPathExtension().lastPathComponent,
                mediaURL: mediaURL,
                localFilePath: destinationURL.path,
                mediaRelativePath: mediaRelativePath,
                mediaMimeType: mimeType,
                sortOrder: nextOrder,
                group: group,
                description: description
            )
        case .video:
            return ContentSourceItem.makePanoramaVideo(
                id: sourceID,
                name: fileURL.deletingPathExtension().lastPathComponent,
                mediaURL: mediaURL,
                localFilePath: destinationURL.path,
                mediaRelativePath: mediaRelativePath,
                mediaMimeType: mimeType,
                sortOrder: nextOrder,
                group: group,
                description: description
            )
        }
    }

    private func panoramaKind(for fileURL: URL) -> PanoramaAssetKind? {
        switch fileURL.pathExtension.lowercased() {
        case "jpg", "jpeg", "png", "heic", "webp":
            return .photo
        case "mp4", "mov", "m4v":
            return .video
        default:
            return nil
        }
    }

    private func isSupportedPanoramaFile(_ fileURL: URL) -> Bool {
        panoramaKind(for: fileURL) != nil
    }

    private func makePanoramaSourceID(relativePath: String) -> String {
        let slug = relativePath.lowercased().map { character -> Character in
            if character.isLetter || character.isNumber {
                return character
            }
            return "-"
        }
        return "panorama-" + String(slug).replacingOccurrences(of: "--", with: "-")
    }

    private func sanitizedImportFolderName(_ value: String, fallback: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }

    private static func mediaMimeType(for fileURL: URL) -> String {
        switch fileURL.pathExtension.lowercased() {
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

    private func loadContentSources() {
        do {
            let directory = sourceStoreURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            guard FileManager.default.fileExists(atPath: sourceStoreURL.path) else {
                contentSources = AppModel.defaultContentSources
                normalizeContentSourceOrder()
                saveContentSources()
                selectedContentSourceID = contentSources.first?.id
                return
            }
            let data = try Data(contentsOf: sourceStoreURL)
            let file = try JSONDecoder().decode(ContentSourceStoreFile.self, from: data)
            contentSources = file.sources
            if contentSources.isEmpty {
                contentSources = AppModel.defaultContentSources
            }
            sortContentSources()
            selectedContentSourceID = contentSources.first?.id
        } catch {
            log("内容源读取失败，回退默认配置: \(error.localizedDescription)")
            contentSources = AppModel.defaultContentSources
            normalizeContentSourceOrder()
            selectedContentSourceID = contentSources.first?.id
        }
    }

    private func saveContentSources() {
        do {
            let directory = sourceStoreURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let file = ContentSourceStoreFile(version: 1, lastUpdated: ContentSourceItem.nowISO(), sources: contentSources)
            let data = try JSONEncoder().encode(file)
            try data.write(to: sourceStoreURL, options: .atomic)
        } catch {
            log("内容源保存失败: \(error.localizedDescription)")
        }
    }

    private func sortContentSources() {
        contentSources.sort {
            if $0.sortOrder == $1.sortOrder {
                return $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
            return $0.sortOrder < $1.sortOrder
        }
        normalizeContentSourceOrder()
    }

    private func normalizeContentSourceOrder() {
        for index in contentSources.indices {
            contentSources[index].sortOrder = index + 1
        }
    }

    private func startContentSourceHealthCheck() {
        contentSourceHealthTimer?.invalidate()
        contentSourceHealthTimer = Timer.scheduledTimer(withTimeInterval: 12, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshContentSourceStatus()
            }
        }
    }

    private func syncContentSourcesToClients(reason: String) {
        Task {
            await refreshSnapshot(reason: reason)
            broadcastSnapshot(type: "status", message: reason)
        }
    }

    private func updateRawFrameMetadata(using image: CGImage?) {
        guard let image else {
            rawFrameWidth = 0
            rawFrameHeight = 0
            rawFrameAspectRatio = 0
            rawFrameType = "未知"
            projectionMode = "Raw"
            isSpherePreviewEnabled = false
            return
        }

        rawFrameWidth = image.width
        rawFrameHeight = image.height
        rawFrameAspectRatio = rawFrameHeight > 0 ? Double(rawFrameWidth) / Double(rawFrameHeight) : 0

        if abs(rawFrameAspectRatio - 2.0) < 0.05 {
            rawFrameType = "2:1 全景候选"
            projectionMode = "Equirectangular"
            isSpherePreviewEnabled = true
        } else if abs(rawFrameAspectRatio - (16.0 / 9.0)) < 0.05 {
            rawFrameType = "普通 16:9 / 非360"
            projectionMode = "Raw"
            isSpherePreviewEnabled = false
        } else {
            rawFrameType = "未识别输入"
            projectionMode = "Raw"
            isSpherePreviewEnabled = false
        }
    }

    private func handleControlMessage(_ text: String, from peer: ControlPeer) async {
        guard let message = text.data(using: .utf8) else { return }
        do {
            let envelope = try JSONDecoder.tsjy.decode(ControlClientMessage.self, from: message)
            switch envelope.type {
            case "hello":
                let response = safetyManager.register(clientID: envelope.clientID ?? peer.id.uuidString)
                let snapshot = await currentSnapshot()
                try controlServer.send(
                    ControlServerMessage(type: "helloAck", accepted: true, message: "控制会话已建立", sessionID: response.sessionID, snapshot: snapshot, commandID: nil),
                    to: peer
                )
            case "heartbeat":
                let snapshot = await heartbeat(for: envelope.sessionID)
                try controlServer.send(
                    ControlServerMessage(type: "status", accepted: true, message: "heartbeat", sessionID: envelope.sessionID, snapshot: snapshot, commandID: nil),
                    to: peer
                )
            case "arm":
                let result = safetyManager.arm(sessionID: envelope.sessionID)
                let snapshot = await currentSnapshot()
                try controlServer.send(
                    ControlServerMessage(type: "status", accepted: result.accepted, message: result.message, sessionID: envelope.sessionID, snapshot: snapshot, commandID: envelope.commandID),
                    to: peer
                )
            case "releaseEmergencyStop":
                let result = safetyManager.releaseEmergencyStop(sessionID: envelope.sessionID)
                if result.accepted {
                    _ = await siteBridge.releaseEmergencyStop(reason: envelope.reason ?? "远程解除急停")
                }
                let snapshot = await currentSnapshot()
                try controlServer.send(
                    ControlServerMessage(type: "status", accepted: result.accepted, message: result.message, sessionID: envelope.sessionID, snapshot: snapshot, commandID: envelope.commandID),
                    to: peer
                )
                broadcastSnapshot(type: "status", message: result.message)
            case "videoMetricBatch":
                if let batch = envelope.videoMetricBatch {
                    recordVisionMetricBatch(batch)
                    await refreshSnapshot(reason: "收到 Vision Pro 视频指标批次")
                    try controlServer.send(
                        ControlServerMessage(
                            type: "status",
                            accepted: true,
                            message: "已接收 Vision Pro 视频指标批次 \(batch.frames.count) 条",
                            sessionID: envelope.sessionID,
                            snapshot: await currentSnapshot(),
                            commandID: envelope.commandID,
                            resultSendTimestamp: Date().timeIntervalSince1970
                        ),
                        to: peer
                    )
                }
            case "vpFeedbackRendered":
                if let commandID = envelope.commandID {
                    recordVPFeedbackRendered(
                        commandID: commandID,
                        at: envelope.clientSendTimestamp ?? Date().timeIntervalSince1970
                    )
                }
            case "command":
                let commandResult = try await executeCommand(envelope)
                try controlServer.send(commandResult, to: peer)
                broadcastSnapshot(type: "status", message: commandResult.message)
            case "emergencyStop":
                safetyManager.forceEmergencyStop(reason: envelope.reason ?? "远程触发")
                _ = await siteBridge.emergencyStop(reason: envelope.reason ?? "远程触发")
                let snapshot = await currentSnapshot()
                try controlServer.send(
                    ControlServerMessage(type: "alarm", accepted: true, message: "已执行急停", sessionID: envelope.sessionID, snapshot: snapshot, commandID: envelope.commandID),
                    to: peer
                )
                broadcastSnapshot(type: "alarm", message: "远程急停已触发")
            default:
                try controlServer.send(
                    ControlServerMessage(type: "error", accepted: false, message: "未知消息类型: \(envelope.type)", sessionID: envelope.sessionID, snapshot: await currentSnapshot(), commandID: envelope.commandID),
                    to: peer
                )
            }
        } catch {
            log("控制消息解析失败: \(error.localizedDescription)")
            try? controlServer.send(
                ControlServerMessage(type: "error", accepted: false, message: "控制消息解析失败", sessionID: nil, snapshot: await currentSnapshot(), commandID: nil),
                to: peer
            )
        }
    }

    private func handleRelayControlMessage(_ text: String) async {
        guard let message = text.data(using: .utf8) else { return }
        do {
            let envelope = try JSONDecoder.tsjy.decode(ControlClientMessage.self, from: message)
            switch envelope.type {
            case "hello":
                let response = safetyManager.register(clientID: envelope.clientID ?? "relay-\(UUID().uuidString)")
                let snapshot = await currentSnapshot()
                try controlRelay.send(
                    ControlServerMessage(type: "helloAck", accepted: true, message: "控制会话已建立 (中继)", sessionID: response.sessionID, snapshot: snapshot, commandID: nil)
                )
            case "heartbeat":
                let snapshot = await heartbeat(for: envelope.sessionID)
                try controlRelay.send(
                    ControlServerMessage(type: "status", accepted: true, message: "heartbeat", sessionID: envelope.sessionID, snapshot: snapshot, commandID: nil)
                )
            case "arm":
                let result = safetyManager.arm(sessionID: envelope.sessionID)
                let snapshot = await currentSnapshot()
                try controlRelay.send(
                    ControlServerMessage(type: "status", accepted: result.accepted, message: result.message, sessionID: envelope.sessionID, snapshot: snapshot, commandID: envelope.commandID)
                )
            case "releaseEmergencyStop":
                let result = safetyManager.releaseEmergencyStop(sessionID: envelope.sessionID)
                if result.accepted {
                    _ = await siteBridge.releaseEmergencyStop(reason: envelope.reason ?? "远程解除急停(中继)")
                }
                let snapshot = await currentSnapshot()
                try controlRelay.send(
                    ControlServerMessage(type: "status", accepted: result.accepted, message: result.message, sessionID: envelope.sessionID, snapshot: snapshot, commandID: envelope.commandID)
                )
                broadcastSnapshot(type: "status", message: result.message)
            case "videoMetricBatch":
                if let batch = envelope.videoMetricBatch {
                    recordVisionMetricBatch(batch)
                    await refreshSnapshot(reason: "收到 Vision Pro 视频指标批次")
                    try controlRelay.send(
                        ControlServerMessage(
                            type: "status",
                            accepted: true,
                            message: "已接收 Vision Pro 视频指标批次 \(batch.frames.count) 条",
                            sessionID: envelope.sessionID,
                            snapshot: await currentSnapshot(),
                            commandID: envelope.commandID,
                            resultSendTimestamp: Date().timeIntervalSince1970
                        )
                    )
                }
            case "vpFeedbackRendered":
                if let commandID = envelope.commandID {
                    recordVPFeedbackRendered(
                        commandID: commandID,
                        at: envelope.clientSendTimestamp ?? Date().timeIntervalSince1970
                    )
                }
            case "command":
                let commandResult = try await executeCommand(envelope)
                try controlRelay.send(commandResult)
                broadcastSnapshot(type: "status", message: commandResult.message)
            case "emergencyStop":
                safetyManager.forceEmergencyStop(reason: envelope.reason ?? "远程触发(中继)")
                _ = await siteBridge.emergencyStop(reason: envelope.reason ?? "远程触发(中继)")
                let snapshot = await currentSnapshot()
                try controlRelay.send(
                    ControlServerMessage(type: "alarm", accepted: true, message: "已执行急停", sessionID: envelope.sessionID, snapshot: snapshot, commandID: envelope.commandID)
                )
                broadcastSnapshot(type: "alarm", message: "远程急停已触发(中继)")
            default:
                try controlRelay.send(
                    ControlServerMessage(type: "error", accepted: false, message: "未知消息类型: \(envelope.type)", sessionID: envelope.sessionID, snapshot: await currentSnapshot(), commandID: envelope.commandID)
                )
            }
        } catch {
            log("控制中继消息解析失败: \(error.localizedDescription)")
            try? controlRelay.send(
                ControlServerMessage(type: "error", accepted: false, message: "控制消息解析失败", sessionID: nil, snapshot: await currentSnapshot(), commandID: nil)
            )
        }
    }
    
    private func heartbeat(for sessionID: String?) async -> GatewaySnapshot {
        if let sessionID {
            safetyManager.heartbeat(sessionID: sessionID)
        }
        return await currentSnapshot()
    }

    private func executeCommand(_ envelope: ControlClientMessage) async throws -> ControlServerMessage {
        let commandID = envelope.commandID ?? UUID().uuidString
        let gatewayReceiveTime = Date().timeIntervalSince1970
        beginCommandLifecycle(for: envelope, commandID: commandID, gatewayReceiveTime: gatewayReceiveTime)
        let validation = safetyManager.validateCommand(sessionID: envelope.sessionID, message: envelope)
        let validationFinishTime = Date().timeIntervalSince1970
        updateCommandLifecycle(commandID: commandID) { record in
            record.validationFinishTimestamp = validationFinishTime
            record.accepted = validation.accepted
            if !validation.accepted {
                record.rejectionReason = validation.message
                record.failureStage = "GATEWAY_VALIDATION"
                record.finalResult = "REJECTED"
                record.blockLayer = inferSafetyBlockLayer(from: validation.message)
                record.blockReason = validation.message
                record.invalidReason = validation.message
                record.validSample = false
                record.resultSendTimestamp = validationFinishTime
            }
        }
        guard validation.accepted else {
            appendMonitoringProcessEvent(
                eventType: "Vision Pro 操作",
                actionName: commandDisplayName(for: envelope.action ?? ""),
                phase: "安全校验拒绝",
                detail: validation.message,
                commandID: commandID,
                commandRoundTripMs: nil,
                at: Date(timeIntervalSince1970: validationFinishTime)
            )
            return ControlServerMessage(
                type: "commandResult",
                accepted: false,
                message: validation.message,
                sessionID: envelope.sessionID,
                snapshot: await currentSnapshot(),
                commandID: commandID,
                gatewayReceiveTimestamp: gatewayReceiveTime,
                validationFinishTimestamp: validationFinishTime,
                resultSendTimestamp: validationFinishTime
            )
        }

        if envelope.action == "connectPLC" {
            let url = SiteConnectionConfig.resolveConnectPLCURL(
                explicitURL: envelope.reason,
                siteEndpointText: siteEndpointText
            )
            do {
                try await siteBridge.connect(to: url)
                appendMonitoringProcessEvent(
                    eventType: "Vision Pro 操作",
                    actionName: "连接 PLC",
                    phase: "网关已执行",
                    detail: "已成功启动本地 PLC 服务端: \(url)",
                    commandID: commandID,
                    commandRoundTripMs: nil,
                    at: .now
                )
                return ControlServerMessage(
                    type: "commandResult",
                    accepted: true,
                    message: "已成功启动本地 PLC 服务端: \(url)",
                    sessionID: envelope.sessionID,
                    snapshot: await currentSnapshot(),
                    commandID: commandID,
                    gatewayReceiveTimestamp: gatewayReceiveTime,
                    validationFinishTimestamp: validationFinishTime,
                    resultSendTimestamp: Date().timeIntervalSince1970
                )
            } catch {
                appendMonitoringProcessEvent(
                    eventType: "Vision Pro 操作",
                    actionName: "连接 PLC",
                    phase: "执行失败",
                    detail: "PLC 连接失败: \(error.localizedDescription)",
                    commandID: commandID,
                    commandRoundTripMs: nil,
                    at: .now
                )
                return ControlServerMessage(
                    type: "commandResult",
                    accepted: false,
                    message: "PLC 连接失败: \(error.localizedDescription)",
                    sessionID: envelope.sessionID,
                    snapshot: await currentSnapshot(),
                    commandID: commandID,
                    gatewayReceiveTimestamp: gatewayReceiveTime,
                    validationFinishTimestamp: validationFinishTime,
                    resultSendTimestamp: Date().timeIntervalSince1970
                )
            }
        }

        let result = await siteBridge.execute(
            deviceID: envelope.deviceID ?? "",
            action: envelope.action ?? "",
            parameters: envelope.parameters ?? [:],
            commandID: commandID
        )
        let registerWriteTime = result.registerWrites.isEmpty ? nil : Date().timeIntervalSince1970
        let resultSendTime = Date().timeIntervalSince1970
        if result.accepted {
            safetyManager.touch(sessionID: envelope.sessionID)
        }
        updateCommandLifecycle(commandID: commandID) { record in
            let expectedFeedback = expectedFeedbackText(for: envelope.action ?? "", parameters: envelope.parameters)
            let feedbackInfo = feedbackComponents(for: expectedFeedback)
            record.accepted = result.accepted
            record.registerWriteTimestamp = registerWriteTime
            record.commandSemantic = commandSemantic(for: envelope.action ?? "", parameters: envelope.parameters)
            record.expectedFeedback = expectedFeedback
            record.targetFeedbackName = feedbackInfo.name
            record.targetFeedbackExpectedValue = feedbackInfo.value
            record.feedbackWaitStartTimestamp = registerWriteTime ?? record.clientSendTimestamp
            record.simulatorAccepted = result.simulatorAccepted
            record.simulatorResultCode = result.simulatorResultCode
            record.simulatorRejectReason = result.simulatorRejectReason
            record.simulatorExecutedAction = result.simulatorExecutedAction
            let isSimulatorRejected = (result.accepted == false && !result.blockLayer.isEmpty)
            record.finalResult = result.accepted ? "WAITING_FEEDBACK" : (isSimulatorRejected ? "REJECTED" : "COMMUNICATION_FAILED")
            record.failureStage = result.accepted ? "" : (isSimulatorRejected ? "SIMULATOR_REJECTED" : "REGISTER_WRITE")
            record.resultSendTimestamp = resultSendTime
            if !result.accepted {
                record.blockLayer = result.blockLayer.isEmpty ? record.blockLayer : result.blockLayer
                record.blockReason = result.simulatorRejectReason.isEmpty ? result.message : result.simulatorRejectReason
                record.invalidReason = result.simulatorRejectReason.isEmpty ? result.message : result.simulatorRejectReason
                record.validSample = false
                record.feedbackTimeoutTimestamp = nil
                record.feedbackMatchedTimestamp = nil
            }
        }
        if result.accepted {
            monitoringActionName = commandDisplayName(for: envelope.action ?? "")
            monitoringCommandCount += 1
            pendingPLCFeedbackCommandIDs.append(commandID)
        }
        appendMonitoringProcessEvent(
            eventType: "Vision Pro 操作",
            actionName: commandDisplayName(for: envelope.action ?? ""),
            phase: result.accepted ? "网关已执行" : "执行失败",
            detail: result.message,
            commandID: commandID,
            commandRoundTripMs: nil,
            at: .now
        )
        await refreshSnapshot(reason: result.message)
        let latestRecord = commandLifecycleRecords[commandID]
        return ControlServerMessage(
            type: "commandResult",
            accepted: result.accepted,
            message: result.message,
            sessionID: envelope.sessionID,
            snapshot: await currentSnapshot(),
            commandID: commandID,
            gatewayReceiveTimestamp: gatewayReceiveTime,
            validationFinishTimestamp: validationFinishTime,
            registerWriteTimestamp: latestRecord?.registerWriteTimestamp,
            plcFeedbackTimestamp: latestRecord?.plcFeedbackTimestamp,
            deviceFeedbackTimestamp: latestRecord?.deviceFeedbackTimestamp,
            resultSendTimestamp: latestRecord?.resultSendTimestamp,
            simulatorAccepted: latestRecord?.simulatorAccepted,
            simulatorResultCode: latestRecord?.simulatorResultCode,
            simulatorRejectReason: latestRecord?.simulatorRejectReason,
            simulatorExecutedAction: latestRecord?.simulatorExecutedAction
        )
    }

    private func currentSnapshot() async -> GatewaySnapshot {
        var snapshot = await siteBridge.snapshot()
        snapshot.gatewayName = gatewayName
        snapshot.videoPort = Int(TSJYNetwork.videoPort)
        snapshot.controlPort = Int(TSJYNetwork.controlPort)
        snapshot.videoClientCount = connectedVideoClients
        snapshot.controlClientCount = connectedControlClients
        snapshot.videoStatus = lastFrameInfo
        snapshot.gatewayStatus = gatewayStatus
        snapshot.siteStatus = siteStatus
        snapshot.lockState = safetyManager.lockStateDescription
        snapshot.contentSources = contentSources.map(resolvedContentSourceForDistribution)
        snapshot.defaultSourceIDs = snapshot.contentSources.filter { $0.defaultVisible == true }.map(\.id)
        snapshot.monitoring = monitoringSummary
        return snapshot
    }

    private func refreshSnapshot(reason: String) async {
        latestSnapshot = await currentSnapshot()
        log(reason)
    }

    private func broadcastSnapshot(type: String, message: String) {
        Task {
            let snapshot = await currentSnapshot()
            let serverMessage = ControlServerMessage(type: type, accepted: true, message: message, sessionID: safetyManager.activeSessionID, snapshot: snapshot, commandID: nil)
            controlServer.broadcast(serverMessage)
            try? controlRelay.send(serverMessage)
        }
    }

    private func log(_ message: String) {
        let entry = LogEntry(timestamp: DateFormatter.logTimestamp.string(from: .now), message: message)
        logEntries.insert(entry, at: 0)
        if logEntries.count > 200 {
            logEntries.removeLast(logEntries.count - 200)
        }
    }

    private func ensureStateExportFile(in directoryURL: URL, at date: Date) throws -> URL {
        if let activeStateExportFileURL {
            return activeStateExportFileURL
        }

        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let filename = "试验记录_\(Self.stateExportFileFormatter.string(from: date)).csv"
        let fileURL = directoryURL.appendingPathComponent(filename)
        let header = [
            "会话编号", "记录编号", "记录开始时间", "记录结束时间", "事件时间", "事件类型", "动作类型", "阶段", "命令ID",
            "试验工况", "操作者", "试验模式", "重复序号", "场景编号", "点动周期ID", "网络工况", "模拟PLC扫描周期(ms)", "人工延迟(ms)",
            "VisionPro发送时间", "Mac接收时间", "寄存器写入时间", "模拟器读取时间", "反馈写入时间", "Mac收到反馈时间", "VisionPro显示反馈时间",
            "命令语义", "预期反馈", "目标反馈名称", "目标反馈期望值", "目标反馈前值", "目标反馈当前值", "反馈等待开始时间", "反馈匹配时间", "反馈超时时间", "反馈等待耗时(ms)",
            "反馈前状态", "实际反馈", "反馈后状态", "反馈是否变化", "反馈变化时间", "反馈是否匹配", "最终结果", "失败阶段", "拦截层级", "拦截原因", "模拟器是否接受", "模拟器结果码", "模拟器拒绝原因", "模拟器执行动作", "有效样本", "无效原因",
            "启动响应时间(ms)", "控制闭环时间(ms)", "停止响应时间(ms)", "停止成功", "启动命令ID", "停止命令ID", "保持时长(ms)", "非预期动作", "命令往返时延(ms)", "视频端到端时延(ms)", "视频时延有效", "视频时延无效原因",
            "时钟偏移(ms)", "时钟往返(ms)", "时钟同步有效", "卡顿次数", "最大帧间隔(ms)",
            "起始接收帧数", "起始解码帧数", "起始显示帧数", "结束接收帧数", "结束解码帧数", "结束显示帧数",
            "接收帧数", "解码帧数", "显示帧数", "网络缺帧数", "解码丢帧数", "显示丢帧数",
            "网关状态", "现场状态", "控制锁状态", "PLC心跳", "拼装机运行", "真空到位", "真空故障", "泵站故障",
            "详情", "备注"
        ].joined(separator: ",") + "\n"
        try header.write(to: fileURL, atomically: true, encoding: .utf8)
        activeStateExportFileURL = fileURL
        return fileURL
    }

    private func commandDisplayName(for action: String) -> String {
        switch action {
        case "startPump": return "启动拼装机泵"
        case "stopPump": return "停止拼装机泵"
        case "moveForward": return "前进"
        case "moveBackward": return "后退"
        case "stopTravel": return "停止行走"
        case "rotateClockwise": return "顺时针旋转"
        case "rotateCounterclockwise": return "逆时针旋转"
        case "stopRotation": return "停止旋转"
        case "setParameter": return "参数下发"
        default: return action
        }
    }

    private func actionCode(forDisplayName name: String) -> String {
        switch name {
        case "启动拼装机泵": return "startPump"
        case "停止拼装机泵": return "stopPump"
        case "前进": return "moveForward"
        case "后退": return "moveBackward"
        case "停止行走": return "stopTravel"
        case "顺时针旋转": return "rotateClockwise"
        case "逆时针旋转": return "rotateCounterclockwise"
        case "停止旋转": return "stopRotation"
        default: return name
        }
    }

    private func commandSemantic(for action: String, parameters: [String: Double]? = nil) -> String {
        guard action == "setParameter" else { return action }
        if let value = parameters?["travelEnable"] {
            return "travelEnable=\(Int(value.rounded()))"
        }
        if let value = parameters?["cylinderEnable"] {
            return "cylinderEnable=\(Int(value.rounded()))"
        }
        return action
    }

    private func expectedFeedbackText(for action: String, parameters: [String: Double]? = nil) -> String {
        switch action {
        case "startPump": return "pumpRunningFeedback=1"
        case "stopPump": return "pumpRunningFeedback=0"
        case "moveForward": return "travelActualDirection=1"
        case "moveBackward": return "travelActualDirection=2"
        case "stopTravel": return "travelActualDirection=0"
        case "rotateClockwise": return "rotationActualDirection=1"
        case "rotateCounterclockwise": return "rotationActualDirection=2"
        case "stopRotation": return "rotationActualDirection=0"
        case "setParameter":
            if let value = parameters?["travelEnable"] {
                return "travelEnableFeedback=\(Int(value.rounded()))"
            }
            if let value = parameters?["cylinderEnable"] {
                return "cylinderEnableFeedback=\(Int(value.rounded()))"
            }
            return "setParameter"
        default: return action
        }
    }

    private func feedbackComponents(for text: String) -> (name: String, value: String) {
        guard let expectation = feedbackExpectation(from: text) else {
            return ("", "")
        }
        return (expectation.name, expectation.expectedValue)
    }

    private func isTravelStartAction(_ action: String) -> Bool {
        action == "moveForward" || action == "moveBackward"
    }

    private func isRotationStartAction(_ action: String) -> Bool {
        action == "rotateClockwise" || action == "rotateCounterclockwise"
    }

    private func isStopAction(_ action: String) -> Bool {
        action == "stopPump" || action == "stopTravel" || action == "stopRotation"
    }

    private func invalidStopReason(for record: CommandLifecycleRecord, currentValue: String) -> String? {
        guard isStopAction(record.action), currentValue == "0" else { return nil }
        let hadSuccessfulStart =
            !record.startCommandID.isEmpty &&
            commandLifecycleRecords[record.startCommandID]?.feedbackMatched == true
        let wasMovingBeforeStop =
            !record.targetFeedbackBeforeValue.isEmpty &&
            record.targetFeedbackBeforeValue != "0"
        if hadSuccessfulStart && wasMovingBeforeStop {
            return nil
        }
        return "停止前设备未处于运动状态"
    }

    private func resolveJogCycleID(for action: String, commandID: String, clientSendTimestamp: TimeInterval?) -> String {
        if isTravelStartAction(action) {
            let cycleID = "jog-travel-\(commandID)"
            activeTravelJogCycle = ActiveJogCycle(
                jogCycleID: cycleID,
                direction: action,
                startCommandID: commandID,
                startClientSendTimestamp: clientSendTimestamp
            )
            return cycleID
        }
        if isRotationStartAction(action) {
            let cycleID = "jog-rotate-\(commandID)"
            activeRotationJogCycle = ActiveJogCycle(
                jogCycleID: cycleID,
                direction: action,
                startCommandID: commandID,
                startClientSendTimestamp: clientSendTimestamp
            )
            return cycleID
        }
        if action == "stopTravel" {
            return activeTravelJogCycle?.jogCycleID ?? monitoringJogCycleID
        }
        if action == "stopRotation" {
            return activeRotationJogCycle?.jogCycleID ?? monitoringJogCycleID
        }
        return monitoringJogCycleID
    }

    private func activeStartCommandID(for action: String) -> String {
        if action == "stopTravel" {
            return activeTravelJogCycle?.startCommandID ?? ""
        }
        if action == "stopRotation" {
            return activeRotationJogCycle?.startCommandID ?? ""
        }
        return ""
    }

    private func holdDurationMs(for action: String, stopClientSendTimestamp: TimeInterval?) -> Int? {
        guard let stopClientSendTimestamp else { return nil }
        if action == "stopTravel", let start = activeTravelJogCycle?.startClientSendTimestamp {
            return max(0, Int((stopClientSendTimestamp - start) * 1000))
        }
        if action == "stopRotation", let start = activeRotationJogCycle?.startClientSendTimestamp {
            return max(0, Int((stopClientSendTimestamp - start) * 1000))
        }
        return nil
    }

    private func clearJogCycleIfNeeded(for record: CommandLifecycleRecord) {
        guard record.feedbackMatched == true else { return }
        if record.action == "stopTravel" {
            activeTravelJogCycle = nil
        } else if record.action == "stopRotation" {
            activeRotationJogCycle = nil
        }
    }

    private func inferSafetyBlockLayer(from message: String) -> String {
        if message.contains("未授权") || message.contains("会话") {
            return "GATEWAY_SESSION"
        }
        if message.contains("急停") {
            return "SOFTWARE_ESTOP"
        }
        if message.contains("联锁") || message.contains("安全") {
            return "SOFTWARE_PLC_INTERLOCK"
        }
        return "NOT_BLOCKED"
    }

    private func feedbackExpectation(from text: String) -> FeedbackExpectation? {
        let parts = text.split(separator: "=", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return nil }
        return FeedbackExpectation(
            name: parts[0].trimmingCharacters(in: .whitespacesAndNewlines),
            expectedValue: parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    private func feedbackValueMap(from summary: String) -> [String: String] {
        Dictionary(
            uniqueKeysWithValues: summary
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .compactMap { item -> (String, String)? in
                    let parts = item.split(separator: "=", maxSplits: 1).map(String.init)
                    guard parts.count == 2 else { return nil }
                    return (
                        feedbackSemanticKey(for: parts[0].trimmingCharacters(in: .whitespacesAndNewlines)),
                        parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
                    )
                }
        )
    }

    private func matchesExpectedFeedback(expected: String, actual: String) -> Bool {
        guard let expectation = feedbackExpectation(from: expected) else {
            guard !expected.isEmpty, !actual.isEmpty else { return false }
            return actual.contains(expected)
        }
        let actualMap = feedbackValueMap(from: actual)
        return actualMap[expectation.name] == expectation.expectedValue
    }

    private func isIllegalFeedbackValue(name: String, value: String) -> Bool {
        switch name {
        case "travelActualDirection", "rotationActualDirection":
            return !["0", "1", "2"].contains(value)
        case "travelEnableFeedback", "cylinderEnableFeedback", "pumpRunningFeedback":
            return !["0", "1"].contains(value)
        default:
            return false
        }
    }

    private func isExplicitMismatch(for record: CommandLifecycleRecord, expectation: FeedbackExpectation, currentValue: String) -> Bool {
        guard !currentValue.isEmpty else { return false }
        if isIllegalFeedbackValue(name: expectation.name, value: currentValue) {
            return true
        }
        switch (record.action, expectation.name, expectation.expectedValue, currentValue) {
        case ("moveForward", "travelActualDirection", "1", "2"),
             ("moveBackward", "travelActualDirection", "2", "1"),
             ("rotateClockwise", "rotationActualDirection", "1", "2"),
             ("rotateCounterclockwise", "rotationActualDirection", "2", "1"):
            return true
        default:
            return false
        }
    }

    private func evaluateFeedback(for record: CommandLifecycleRecord, actualSummary: String, at now: TimeInterval) -> (currentValue: String, matched: Bool, finalResult: String, failureStage: String) {
        let waitStart = record.registerWriteTimestamp ?? record.clientSendTimestamp
        let elapsedMs = responseDurationMs(from: waitStart, to: now) ?? 0
        guard let expectation = feedbackExpectation(from: record.expectedFeedback) else {
            if matchesExpectedFeedback(expected: record.expectedFeedback, actual: actualSummary) {
                return ("", true, "SUCCESS", "")
            }
            if elapsedMs >= record.responseTimeoutMs {
                return ("", false, "TIMEOUT", "FEEDBACK_TIMEOUT")
            }
            return ("", false, "WAITING_FEEDBACK", "")
        }

        let actualMap = feedbackValueMap(from: actualSummary)
        let currentValue = actualMap[expectation.name] ?? ""
        if currentValue == expectation.expectedValue {
            return (currentValue, true, "SUCCESS", "")
        }
        if isExplicitMismatch(for: record, expectation: expectation, currentValue: currentValue) {
            return (currentValue, false, "FEEDBACK_MISMATCH", "FEEDBACK")
        }
        if elapsedMs >= record.responseTimeoutMs {
            return (currentValue, false, "TIMEOUT", "FEEDBACK_TIMEOUT")
        }
        return (currentValue, false, "WAITING_FEEDBACK", "")
    }

    private func feedbackSemanticKey(for key: String) -> String {
        switch key {
        case "travelDirectionAN1": return "travelActualDirection"
        case "rotationDirectionAN2": return "rotationActualDirection"
        case "travelEnable": return "travelEnableFeedback"
        case "cylinderEnable": return "cylinderEnableFeedback"
        case "assemblerRunning": return "pumpRunningFeedback"
        default: return key
        }
    }

    private func currentFeedbackSnapshotSummary() -> String {
        guard let assembler = latestSnapshot.devices.first(where: { $0.id == "assembler" }),
              let properties = assembler.properties else {
            return ""
        }
        return makeFeedbackSummary(from: properties)
    }

    private func normalizePLCFeedbackSummary(_ summary: String) -> String {
        let normalizedItems = summary
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .compactMap { item -> String? in
                let parts = item.split(separator: "=", maxSplits: 1).map(String.init)
                guard parts.count == 2 else { return item.isEmpty ? nil : item }
                let key = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
                let value = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
                if let address = Int(key), let fieldName = modbusFeedbackAddressNames[address] {
                    return "\(feedbackSemanticKey(for: fieldName))=\(value)"
                }
                return "\(feedbackSemanticKey(for: key))=\(value)"
            }
        return normalizedItems.joined(separator: ", ")
    }

    private func makeFeedbackSummary(from feedbackValues: [String: Double]) -> String {
        let orderedKeys = [
            "pumpRunningFeedback",
            "travelEnableFeedback",
            "cylinderEnableFeedback",
            "travelActualDirection",
            "rotationActualDirection",
            "heartbeatPLC",
            "vacuumBoxReady",
            "vacuumFault",
            "pumpFault"
        ]
        let normalized = Dictionary(uniqueKeysWithValues: feedbackValues.map { key, value in
            (feedbackSemanticKey(for: key), value)
        })
        let orderedItems = orderedKeys.compactMap { key -> String? in
            guard let value = normalized[key] else { return nil }
            return "\(key)=\(Int(value.rounded()))"
        }
        let remainingItems = normalized.keys
            .filter { !orderedKeys.contains($0) }
            .sorted()
            .compactMap { key -> String? in
                guard let value = normalized[key] else { return nil }
                return "\(key)=\(Int(value.rounded()))"
            }
        return (orderedItems + remainingItems).joined(separator: ", ")
    }

    private func deltaCount(current: Int, start: Int) -> Int {
        max(0, current - start)
    }

    private func selectPendingCommandID(for normalizedSummary: String) -> String? {
        for commandID in pendingPLCFeedbackCommandIDs {
            if let record = commandLifecycleRecords[commandID],
               matchesExpectedFeedback(expected: record.expectedFeedback, actual: normalizedSummary) {
                return commandID
            }
        }
        return pendingPLCFeedbackCommandIDs.first
    }

    private func responseDurationMs(from start: TimeInterval?, to end: TimeInterval?) -> Int? {
        guard let start, let end else { return nil }
        return max(0, Int((end - start) * 1000))
    }

    private func boolText(_ value: Bool?) -> String {
        guard let value else { return "" }
        return value ? "是" : "否"
    }

    private func formatIntText(_ value: Int?) -> String {
        value.map(String.init) ?? ""
    }

    private func beginCommandLifecycle(for envelope: ControlClientMessage, commandID: String, gatewayReceiveTime: TimeInterval) {
        let action = envelope.action ?? ""
        let jogCycleID = resolveJogCycleID(for: action, commandID: commandID, clientSendTimestamp: envelope.clientSendTimestamp)
        let expectedFeedback = expectedFeedbackText(for: envelope.action ?? "", parameters: envelope.parameters)
        let feedbackInfo = feedbackComponents(for: expectedFeedback)
        commandLifecycleRecords[commandID] = CommandLifecycleRecord(
            sessionID: monitoringSessionID,
            trialID: monitoringTrialID,
            commandID: commandID,
            action: action,
            commandSemantic: commandSemantic(for: action, parameters: envelope.parameters),
            repeatIndex: monitoringRepeatIndex,
            scenarioID: monitoringScenarioID,
            jogCycleID: jogCycleID,
            clientSendTimestamp: envelope.clientSendTimestamp,
            gatewayReceiveTimestamp: gatewayReceiveTime,
            validationFinishTimestamp: nil,
            registerWriteTimestamp: nil,
            simulatorReadTimestamp: nil,
            logicFinishTimestamp: nil,
            feedbackWriteTimestamp: nil,
            plcFeedbackTimestamp: nil,
            deviceFeedbackTimestamp: nil,
            resultSendTimestamp: nil,
            vpFeedbackRenderTimestamp: nil,
            accepted: false,
            rejectionReason: "",
            expectedFeedback: expectedFeedback,
            targetFeedbackName: feedbackInfo.name,
            targetFeedbackExpectedValue: feedbackInfo.value,
            targetFeedbackBeforeValue: "",
            targetFeedbackCurrentValue: "",
            feedbackBefore: currentFeedbackSnapshotSummary(),
            actualFeedback: "",
            feedbackAfter: "",
            feedbackChanged: nil,
            feedbackChangeTimestamp: nil,
            feedbackMatched: nil,
            feedbackWaitStartTimestamp: nil,
            feedbackMatchedTimestamp: nil,
            feedbackTimeoutTimestamp: nil,
            feedbackWaitDurationMs: nil,
            finalResult: "RECEIVED",
            failureStage: "",
            responseTimeoutMs: monitoringResponseTimeoutMs,
            validSample: true,
            invalidReason: "",
            blockLayer: "NOT_BLOCKED",
            blockReason: "",
            simulatorAccepted: nil,
            simulatorResultCode: nil,
            simulatorRejectReason: "",
            simulatorExecutedAction: action,
            unexpectedMotion: false,
            startCommandID: action == "stopTravel" || action == "stopRotation" ? activeStartCommandID(for: action) : commandID,
            stopCommandID: action == "stopTravel" || action == "stopRotation" ? commandID : "",
            holdDurationMs: holdDurationMs(for: action, stopClientSendTimestamp: envelope.clientSendTimestamp),
            startResponseMs: nil,
            stopResponseMs: nil,
            stopSuccessful: nil
        )
    }

    private func updateCommandLifecycle(commandID: String, mutate: (inout CommandLifecycleRecord) -> Void) {
        guard var record = commandLifecycleRecords[commandID] else { return }
        mutate(&record)
        commandLifecycleRecords[commandID] = record
    }

    private func recordPLCFeedback(summary: String) {
        recordPLCFeedback(summary: summary, receivedAt: Date().timeIntervalSince1970)
    }

    private func applySimulatorLifecycleReport(_ report: SimulatorLifecycleReport, receivedAt now: TimeInterval) {
        guard commandLifecycleRecords[report.commandID] != nil else { return }
        updateCommandLifecycle(commandID: report.commandID) { record in
            record.simulatorReadTimestamp = report.simulatorReadTimestamp ?? record.simulatorReadTimestamp
            record.logicFinishTimestamp = report.logicFinishTimestamp ?? record.logicFinishTimestamp
            record.feedbackWriteTimestamp = report.feedbackWriteTimestamp ?? record.feedbackWriteTimestamp
            record.plcFeedbackTimestamp = now
            record.deviceFeedbackTimestamp = now
            record.simulatorAccepted = report.accepted ?? record.simulatorAccepted
            record.simulatorResultCode = report.resultCode ?? record.simulatorResultCode
            if !report.rejectReason.isEmpty {
                record.simulatorRejectReason = report.rejectReason
            }
            if !report.executedAction.isEmpty {
                record.simulatorExecutedAction = report.executedAction
            }
            if record.feedbackWaitStartTimestamp == nil {
                record.feedbackWaitStartTimestamp = record.registerWriteTimestamp ?? record.clientSendTimestamp
            }
            if record.targetFeedbackBeforeValue.isEmpty,
               let beforeValue = feedbackValueMap(from: record.feedbackBefore)[record.targetFeedbackName] {
                record.targetFeedbackBeforeValue = beforeValue
            }
            if report.accepted == false {
                record.feedbackMatched = false
                record.finalResult = "REJECTED"
                record.failureStage = "SIMULATOR_REJECTED"
                record.blockLayer = "SOFTWARE_PLC_INTERLOCK"
                record.blockReason = report.rejectReason.isEmpty ? report.detail : report.rejectReason
                record.invalidReason = report.rejectReason.isEmpty ? report.detail : report.rejectReason
                record.validSample = false
                if isStopAction(record.action) {
                    record.stopResponseMs = responseDurationMs(from: record.clientSendTimestamp, to: now)
                    record.stopSuccessful = false
                } else {
                    record.stopResponseMs = nil
                    record.stopSuccessful = nil
                }
                record.feedbackWaitDurationMs = responseDurationMs(from: record.feedbackWaitStartTimestamp, to: now)
                return
            }
            if !report.feedbackSummary.isEmpty {
                let evaluation = evaluateFeedback(for: record, actualSummary: report.feedbackSummary, at: now)
                record.feedbackBefore = record.feedbackBefore.isEmpty ? currentFeedbackSnapshotSummary() : record.feedbackBefore
                record.actualFeedback = report.feedbackSummary
                record.feedbackAfter = report.feedbackSummary
                record.feedbackChanged = record.feedbackBefore != report.feedbackSummary
                record.feedbackChangeTimestamp = now
                record.targetFeedbackCurrentValue = evaluation.currentValue
                if record.targetFeedbackBeforeValue.isEmpty {
                    record.targetFeedbackBeforeValue = feedbackValueMap(from: record.feedbackBefore)[record.targetFeedbackName] ?? ""
                }
                record.feedbackMatched = evaluation.matched
                record.finalResult = evaluation.finalResult
                record.failureStage = evaluation.failureStage
                record.feedbackWaitDurationMs = responseDurationMs(from: record.feedbackWaitStartTimestamp, to: now)
                record.feedbackMatchedTimestamp = evaluation.finalResult == "SUCCESS" ? now : record.feedbackMatchedTimestamp
                record.feedbackTimeoutTimestamp = evaluation.finalResult == "TIMEOUT" ? now : record.feedbackTimeoutTimestamp
                if let invalidStopReason = invalidStopReason(for: record, currentValue: evaluation.currentValue),
                   evaluation.finalResult == "SUCCESS" {
                    record.feedbackMatched = false
                    record.finalResult = "NO_ACTION_REQUIRED"
                    record.failureStage = ""
                    record.validSample = false
                    record.invalidReason = invalidStopReason
                }
                if isStopAction(record.action) {
                    record.stopResponseMs = responseDurationMs(from: record.clientSendTimestamp, to: now)
                    record.stopSuccessful = record.finalResult == "SUCCESS"
                } else {
                    record.stopResponseMs = nil
                    record.stopSuccessful = nil
                }
            }
            record.startResponseMs = responseDurationMs(from: record.clientSendTimestamp, to: record.feedbackWriteTimestamp)
        }
        guard let record = commandLifecycleRecords[report.commandID] else { return }
        if let clientSendTimestamp = record.clientSendTimestamp {
            let responseReference = report.feedbackWriteTimestamp ?? now
            monitoringLastCommandRoundTripMs = max(0, Int((responseReference - clientSendTimestamp) * 1000))
        }
        appendMonitoringProcessEvent(
            eventType: "模拟PLC阶段回报",
            actionName: commandDisplayName(for: record.action),
            phase: "远程回报",
            detail: report.detail.isEmpty ? report.feedbackSummary : report.detail,
            commandID: report.commandID,
            commandRoundTripMs: monitoringLastCommandRoundTripMs > 0 ? monitoringLastCommandRoundTripMs : nil,
            at: Date(timeIntervalSince1970: now)
        )
        if record.finalResult != "WAITING_FEEDBACK" {
            pendingPLCFeedbackCommandIDs.removeAll { $0 == report.commandID }
        }
        if record.feedbackMatched == true {
            monitoringCommandSuccessCount += 1
        }
        clearJogCycleIfNeeded(for: record)
    }

    private func recordPLCFeedback(summary: String, receivedAt now: TimeInterval) {
        let normalizedSummary = normalizePLCFeedbackSummary(summary)
        guard let commandID = selectPendingCommandID(for: normalizedSummary) else { return }
        updateCommandLifecycle(commandID: commandID) { record in
            record.simulatorReadTimestamp = record.simulatorReadTimestamp ?? record.registerWriteTimestamp
            record.logicFinishTimestamp = record.logicFinishTimestamp ?? now
            record.feedbackWriteTimestamp = record.feedbackWriteTimestamp ?? now
            record.plcFeedbackTimestamp = now
            record.deviceFeedbackTimestamp = now
            record.feedbackBefore = record.feedbackBefore.isEmpty ? currentFeedbackSnapshotSummary() : record.feedbackBefore
            record.actualFeedback = normalizedSummary
            record.feedbackAfter = normalizedSummary
            record.feedbackChanged = record.feedbackBefore != normalizedSummary
            record.feedbackChangeTimestamp = now
            if record.feedbackWaitStartTimestamp == nil {
                record.feedbackWaitStartTimestamp = record.registerWriteTimestamp ?? record.clientSendTimestamp
            }
            if record.targetFeedbackBeforeValue.isEmpty {
                record.targetFeedbackBeforeValue = feedbackValueMap(from: record.feedbackBefore)[record.targetFeedbackName] ?? ""
            }
            let evaluation = evaluateFeedback(for: record, actualSummary: normalizedSummary, at: now)
            record.targetFeedbackCurrentValue = evaluation.currentValue
            record.feedbackMatched = evaluation.matched
            record.finalResult = evaluation.finalResult
            record.failureStage = evaluation.failureStage
            record.feedbackWaitDurationMs = responseDurationMs(from: record.feedbackWaitStartTimestamp, to: now)
            record.feedbackMatchedTimestamp = evaluation.finalResult == "SUCCESS" ? now : record.feedbackMatchedTimestamp
            record.feedbackTimeoutTimestamp = evaluation.finalResult == "TIMEOUT" ? now : record.feedbackTimeoutTimestamp
            if let invalidStopReason = invalidStopReason(for: record, currentValue: evaluation.currentValue),
               evaluation.finalResult == "SUCCESS" {
                record.feedbackMatched = false
                record.finalResult = "NO_ACTION_REQUIRED"
                record.failureStage = ""
                record.validSample = false
                record.invalidReason = invalidStopReason
            }
            record.startResponseMs = responseDurationMs(from: record.clientSendTimestamp, to: record.plcFeedbackTimestamp)
            if isStopAction(record.action) {
                record.stopResponseMs = responseDurationMs(from: record.clientSendTimestamp, to: now)
                record.stopSuccessful = record.finalResult == "SUCCESS"
            } else {
                record.stopResponseMs = nil
                record.stopSuccessful = nil
            }
        }
        if let record = commandLifecycleRecords[commandID],
           let clientSendTimestamp = record.clientSendTimestamp {
            if record.finalResult != "WAITING_FEEDBACK" {
                pendingPLCFeedbackCommandIDs.removeAll { $0 == commandID }
            }
            monitoringLastCommandRoundTripMs = max(0, Int((now - clientSendTimestamp) * 1000))
            appendMonitoringProcessEvent(
                eventType: "PLC 反馈",
                actionName: commandDisplayName(for: record.action),
                phase: "PLC 已反馈",
                detail: normalizedSummary,
                commandID: commandID,
                commandRoundTripMs: monitoringLastCommandRoundTripMs,
                at: Date(timeIntervalSince1970: now)
            )
        }
        if let updatedRecord = commandLifecycleRecords[commandID], updatedRecord.feedbackMatched == true {
            monitoringCommandSuccessCount += 1
            clearJogCycleIfNeeded(for: updatedRecord)
        }
    }

    private func recordVPFeedbackRendered(commandID: String, at renderTime: TimeInterval) {
        updateCommandLifecycle(commandID: commandID) { record in
            record.vpFeedbackRenderTimestamp = renderTime
            record.resultSendTimestamp = renderTime
            if isStopAction(record.action) {
                record.stopResponseMs = responseDurationMs(from: record.clientSendTimestamp, to: renderTime)
            } else {
                record.stopResponseMs = nil
                record.stopSuccessful = nil
            }
        }
        guard let record = commandLifecycleRecords[commandID] else { return }
        if let clientSendTimestamp = record.clientSendTimestamp {
            monitoringLastCommandRoundTripMs = max(0, Int((renderTime - clientSendTimestamp) * 1000))
        }
        appendMonitoringProcessEvent(
            eventType: "Vision Pro 反馈显示",
            actionName: commandDisplayName(for: record.action),
            phase: "反馈已显示",
            detail: record.finalResult.isEmpty ? "Vision Pro 已显示反馈" : "Vision Pro 已显示反馈: \(record.finalResult)",
            commandID: commandID,
            commandRoundTripMs: monitoringLastCommandRoundTripMs > 0 ? monitoringLastCommandRoundTripMs : nil,
            at: Date(timeIntervalSince1970: renderTime)
        )
    }

    private func recordVideoSenderMetric(_ frame: EncodedVideoFrame) {
        guard isMonitoringRecording else { return }
        monitoringLastBatchSummary = "最近视频发送帧 #\(frame.sequence)，在线视频端 \(connectedVideoClients)"
    }

    private func recordVisionMetricBatch(_ batch: VideoMetricBatchPayload, receivedAt date: Date = .now) {
        monitoringReceivedFrameCount = batch.receivedFrameCount
        monitoringDecodedFrameCount = batch.decodedFrameCount
        monitoringDisplayedFrameCount = batch.displayedFrameCount
        monitoringNetworkMissingFrameCount = batch.networkMissingFrameCount
        monitoringDecodeDroppedFrameCount = batch.decodeDroppedFrameCount
        monitoringDisplayDroppedFrameCount = batch.displayDroppedFrameCount
        monitoringLatestEndToEndLatencyMs = batch.latestEndToEndLatencyMs
        monitoringClockOffsetMs = batch.clockOffsetMs ?? monitoringClockOffsetMs
        monitoringClockRoundTripMs = batch.clockRoundTripMs ?? monitoringClockRoundTripMs
        monitoringClockSyncValid = batch.clockSyncValid ?? monitoringClockSyncValid
        monitoringStallCount = batch.stallCount ?? monitoringStallCount
        monitoringMaxFrameIntervalMs = batch.maxFrameIntervalMs ?? monitoringMaxFrameIntervalMs
        monitoringLastBatchSummary = "Vision Pro 已回传 \(batch.frames.count) 条视频指标，显示帧 \(batch.displayedFrameCount)"
        appendMonitoringProcessEvent(
            eventType: "视频指标",
            actionName: monitoringActionName,
            phase: "Vision Pro 回传",
            detail: monitoringLastBatchSummary,
            commandID: "",
            commandRoundTripMs: monitoringLastCommandRoundTripMs > 0 ? monitoringLastCommandRoundTripMs : nil,
            at: date
        )
    }

    private func appendMonitoringProcessEvent(
        eventType: String,
        actionName: String,
        phase: String,
        detail: String,
        commandID: String,
        commandRoundTripMs: Int?,
        at date: Date
    ) {
        guard isMonitoringRecording, let startedAt = monitoringCurrentTrialStartedAt else { return }
        let assembler = latestSnapshot.devices.first(where: { $0.id == "assembler" })
        let props = assembler?.properties ?? [:]
        let record = commandID.isEmpty ? nil : commandLifecycleRecords[commandID]
        let controlLoopMs = responseDurationMs(
            from: record?.registerWriteTimestamp,
            to: record?.plcFeedbackTimestamp
        )
        let videoLatencyText = monitoringClockSyncValid ? String(monitoringLatestEndToEndLatencyMs) : ""
        let videoLatencyValidText = boolText(monitoringClockSyncValid)
        let videoLatencyInvalidReason = monitoringClockSyncValid ? "" : "clock_not_synchronized"
        monitoringProcessEvents.append(
            MonitoringProcessEvent(
                sessionID: monitoringSessionID,
                recordID: monitoringTrialID,
                repeatIndex: record?.repeatIndex ?? monitoringRepeatIndex,
                conditionName: monitoringConditionName,
                operatorID: monitoringOperatorID,
                mode: monitoringMode,
                scenarioID: record?.scenarioID ?? monitoringScenarioID,
                jogCycleID: record?.jogCycleID ?? monitoringJogCycleID,
                networkCondition: monitoringNetworkCondition,
                simulatorScanCycleMs: monitoringSimulatorScanCycleMs,
                artificialDelayMs: monitoringArtificialDelayMs,
                recordingStartedAt: startedAt,
                eventAt: date,
                eventType: eventType,
                actionName: actionName,
                phase: phase,
                commandID: commandID,
                clientSendTimeText: isoTimestamp(record?.clientSendTimestamp),
                gatewayReceiveTimeText: isoTimestamp(record?.gatewayReceiveTimestamp),
                registerWriteTimeText: isoTimestamp(record?.registerWriteTimestamp),
                simulatorReadTimeText: isoTimestamp(record?.simulatorReadTimestamp),
                feedbackWriteTimeText: isoTimestamp(record?.feedbackWriteTimestamp),
                gatewayFeedbackTimeText: isoTimestamp(record?.plcFeedbackTimestamp),
                vpFeedbackRenderTimeText: isoTimestamp(record?.vpFeedbackRenderTimestamp),
                commandSemantic: record?.commandSemantic ?? "",
                expectedFeedback: record?.expectedFeedback ?? "",
                targetFeedbackName: record?.targetFeedbackName ?? "",
                targetFeedbackExpectedValue: record?.targetFeedbackExpectedValue ?? "",
                targetFeedbackBeforeValue: record?.targetFeedbackBeforeValue ?? "",
                targetFeedbackCurrentValue: record?.targetFeedbackCurrentValue ?? "",
                feedbackBefore: record?.feedbackBefore ?? "",
                actualFeedback: record?.actualFeedback ?? "",
                feedbackAfter: record?.feedbackAfter ?? "",
                feedbackChangedText: boolText(record?.feedbackChanged),
                feedbackChangeTimeText: isoTimestamp(record?.feedbackChangeTimestamp),
                feedbackMatchedText: boolText(record?.feedbackMatched),
                feedbackWaitStartTimeText: isoTimestamp(record?.feedbackWaitStartTimestamp),
                feedbackMatchedTimeText: isoTimestamp(record?.feedbackMatchedTimestamp),
                feedbackTimeoutTimeText: isoTimestamp(record?.feedbackTimeoutTimestamp),
                feedbackWaitDurationMsText: formatIntText(record?.feedbackWaitDurationMs),
                finalResult: record?.finalResult ?? "",
                failureStage: record?.failureStage ?? "",
                blockLayer: record?.blockLayer ?? "NOT_BLOCKED",
                blockReason: record?.blockReason ?? "",
                simulatorAcceptedText: boolText(record?.simulatorAccepted),
                simulatorResultCodeText: formatIntText(record?.simulatorResultCode),
                simulatorRejectReason: record?.simulatorRejectReason ?? "",
                simulatorExecutedAction: record?.simulatorExecutedAction ?? "",
                validSampleText: boolText(record?.validSample),
                invalidReason: record?.invalidReason ?? "",
                unexpectedMotionText: boolText(record?.unexpectedMotion),
                startResponseMsText: record?.startResponseMs.map(String.init) ?? "",
                controlLoopMsText: controlLoopMs.map(String.init) ?? "",
                stopResponseMsText: isStopAction(record?.action ?? "") ? (record?.stopResponseMs.map(String.init) ?? "") : "",
                stopSuccessfulText: isStopAction(record?.action ?? "") ? boolText(record?.stopSuccessful) : "",
                startCommandID: record?.startCommandID ?? "",
                stopCommandID: record?.stopCommandID ?? "",
                holdDurationMsText: formatIntText(record?.holdDurationMs),
                clockOffsetMsText: String(monitoringClockOffsetMs),
                clockRoundTripMsText: String(monitoringClockRoundTripMs),
                clockSyncValidText: boolText(monitoringClockSyncValid),
                stallCountText: String(monitoringStallCount),
                maxFrameIntervalMsText: String(monitoringMaxFrameIntervalMs),
                videoLatencyText: videoLatencyText,
                videoLatencyValidText: videoLatencyValidText,
                videoLatencyInvalidReason: videoLatencyInvalidReason,
                detail: detail,
                commandRoundTripMs: commandRoundTripMs,
                endToEndLatencyMs: monitoringLatestEndToEndLatencyMs,
                startReceivedFrameCount: monitoringStartReceivedFrameCount,
                startDecodedFrameCount: monitoringStartDecodedFrameCount,
                startDisplayedFrameCount: monitoringStartDisplayedFrameCount,
                endReceivedFrameCount: monitoringReceivedFrameCount,
                endDecodedFrameCount: monitoringDecodedFrameCount,
                endDisplayedFrameCount: monitoringDisplayedFrameCount,
                receivedFrameCount: deltaCount(current: monitoringReceivedFrameCount, start: monitoringStartReceivedFrameCount),
                decodedFrameCount: deltaCount(current: monitoringDecodedFrameCount, start: monitoringStartDecodedFrameCount),
                displayedFrameCount: deltaCount(current: monitoringDisplayedFrameCount, start: monitoringStartDisplayedFrameCount),
                networkMissingFrameCount: deltaCount(current: monitoringNetworkMissingFrameCount, start: monitoringStartNetworkMissingFrameCount),
                decodeDroppedFrameCount: deltaCount(current: monitoringDecodeDroppedFrameCount, start: monitoringStartDecodeDroppedFrameCount),
                displayDroppedFrameCount: deltaCount(current: monitoringDisplayDroppedFrameCount, start: monitoringStartDisplayDroppedFrameCount),
                gatewayStatus: latestSnapshot.gatewayStatus,
                siteStatus: latestSnapshot.siteStatus,
                lockState: latestSnapshot.lockState,
                heartbeatPLC: Int(props["heartbeatPLC"] ?? 0),
                assemblerRunning: props["assemblerRunning"] == 1.0,
                vacuumBoxReady: props["vacuumBoxReady"] == 1.0,
                vacuumFault: props["vacuumFault"] == 1.0,
                pumpFault: props["pumpFault"] == 1.0,
                notes: monitoringNotes
            )
        )
    }

    private func exportMonitoringArtifactsIfNeeded(at date: Date) throws {
        guard stateExportDirectoryURL != nil else { return }
        try rewriteUnifiedMonitoringCSV(at: date)
    }

    private func rewriteUnifiedMonitoringCSV(at date: Date) throws {
        guard let directoryURL = stateExportDirectoryURL else { return }
        let fileURL = try ensureStateExportFile(in: directoryURL, at: date)
        let header = [
            "会话编号", "记录编号", "记录开始时间", "记录结束时间", "事件时间", "事件类型", "动作类型", "阶段", "命令ID",
            "试验工况", "操作者", "试验模式", "重复序号", "场景编号", "点动周期ID", "网络工况", "模拟PLC扫描周期(ms)", "人工延迟(ms)",
            "VisionPro发送时间", "Mac接收时间", "寄存器写入时间", "模拟器读取时间", "反馈写入时间", "Mac收到反馈时间", "VisionPro显示反馈时间",
            "命令语义", "预期反馈", "目标反馈名称", "目标反馈期望值", "目标反馈前值", "目标反馈当前值", "反馈等待开始时间", "反馈匹配时间", "反馈超时时间", "反馈等待耗时(ms)",
            "反馈前状态", "实际反馈", "反馈后状态", "反馈是否变化", "反馈变化时间", "反馈是否匹配", "最终结果", "失败阶段", "拦截层级", "拦截原因", "模拟器是否接受", "模拟器结果码", "模拟器拒绝原因", "模拟器执行动作", "有效样本", "无效原因",
            "启动响应时间(ms)", "控制闭环时间(ms)", "停止响应时间(ms)", "停止成功", "启动命令ID", "停止命令ID", "保持时长(ms)", "非预期动作", "命令往返时延(ms)", "视频端到端时延(ms)", "视频时延有效", "视频时延无效原因",
            "时钟偏移(ms)", "时钟往返(ms)", "时钟同步有效", "卡顿次数", "最大帧间隔(ms)",
            "起始接收帧数", "起始解码帧数", "起始显示帧数", "结束接收帧数", "结束解码帧数", "结束显示帧数",
            "接收帧数", "解码帧数", "显示帧数", "网络缺帧数", "解码丢帧数", "显示丢帧数",
            "网关状态", "现场状态", "控制锁状态", "PLC心跳", "拼装机运行", "真空到位", "真空故障", "泵站故障",
            "详情", "备注"
        ].joined(separator: ",") + "\n"
        let lines = monitoringProcessEvents
            .map { makeUnifiedMonitoringCSVRow(for: $0, endedAt: date) }
            .joined(separator: "\n")
        try (header + (lines.isEmpty ? "" : lines + "\n")).write(to: fileURL, atomically: true, encoding: .utf8)
    }

    private func makeUnifiedMonitoringCSVRow(for event: MonitoringProcessEvent, endedAt: Date) -> String {
        let columns: [String] = [
            event.sessionID,
            event.recordID,
            Self.stateExportTimestampFormatter.string(from: event.recordingStartedAt),
            Self.stateExportTimestampFormatter.string(from: endedAt),
            Self.stateExportTimestampFormatter.string(from: event.eventAt),
            event.eventType,
            event.actionName,
            event.phase,
            event.commandID,
            event.conditionName,
            event.operatorID,
            event.mode,
            String(event.repeatIndex),
            event.scenarioID,
            event.jogCycleID,
            event.networkCondition,
            String(event.simulatorScanCycleMs),
            String(event.artificialDelayMs),
            event.clientSendTimeText,
            event.gatewayReceiveTimeText,
            event.registerWriteTimeText,
            event.simulatorReadTimeText,
            event.feedbackWriteTimeText,
            event.gatewayFeedbackTimeText,
            event.vpFeedbackRenderTimeText,
            event.commandSemantic,
            event.expectedFeedback,
            event.targetFeedbackName,
            event.targetFeedbackExpectedValue,
            event.targetFeedbackBeforeValue,
            event.targetFeedbackCurrentValue,
            event.feedbackWaitStartTimeText,
            event.feedbackMatchedTimeText,
            event.feedbackTimeoutTimeText,
            event.feedbackWaitDurationMsText,
            event.feedbackBefore,
            event.actualFeedback,
            event.feedbackAfter,
            event.feedbackChangedText,
            event.feedbackChangeTimeText,
            event.feedbackMatchedText,
            event.finalResult,
            event.failureStage,
            event.blockLayer,
            event.blockReason,
            event.simulatorAcceptedText,
            event.simulatorResultCodeText,
            event.simulatorRejectReason,
            event.simulatorExecutedAction,
            event.validSampleText,
            event.invalidReason,
            event.startResponseMsText,
            event.controlLoopMsText,
            event.stopResponseMsText,
            event.stopSuccessfulText,
            event.startCommandID,
            event.stopCommandID,
            event.holdDurationMsText,
            event.unexpectedMotionText,
            event.commandRoundTripMs.map(String.init) ?? "",
            event.videoLatencyText,
            event.videoLatencyValidText,
            event.videoLatencyInvalidReason,
            event.clockOffsetMsText,
            event.clockRoundTripMsText,
            event.clockSyncValidText,
            event.stallCountText,
            event.maxFrameIntervalMsText,
            String(event.startReceivedFrameCount),
            String(event.startDecodedFrameCount),
            String(event.startDisplayedFrameCount),
            String(event.endReceivedFrameCount),
            String(event.endDecodedFrameCount),
            String(event.endDisplayedFrameCount),
            String(event.receivedFrameCount),
            String(event.decodedFrameCount),
            String(event.displayedFrameCount),
            String(event.networkMissingFrameCount),
            String(event.decodeDroppedFrameCount),
            String(event.displayDroppedFrameCount),
            event.gatewayStatus,
            event.siteStatus,
            event.lockState,
            String(event.heartbeatPLC),
            event.assemblerRunning ? "是" : "否",
            event.vacuumBoxReady ? "是" : "否",
            event.vacuumFault ? "是" : "否",
            event.pumpFault ? "是" : "否",
            event.detail,
            event.notes
        ]
        return columns.map(csvEscaped).joined(separator: ",")
    }

    private func isoTimestamp(_ value: TimeInterval?) -> String {
        guard let value else { return "" }
        return Self.stateExportTimestampFormatter.string(from: Date(timeIntervalSince1970: value))
    }

    private func csvEscaped(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return value
    }
}

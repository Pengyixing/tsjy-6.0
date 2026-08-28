import Foundation
import Observation
import SwiftUI

@MainActor
@Observable
final class AppModel {
    enum ControlAction {
        case startPump
        case stopPump
        case moveForward
        case moveBackward
        case stopTravel
        case rotateClockwise
        case rotateCounterclockwise
        case stopRotation
        case setTravelEnable(Bool)
        case setCylinderEnable(Bool)

        var title: String {
            switch self {
            case .startPump: return "启动辅助泵"
            case .stopPump: return "停止辅助泵"
            case .moveForward: return "前进"
            case .moveBackward: return "后退"
            case .stopTravel: return "停止行走"
            case .rotateClockwise: return "顺时针"
            case .rotateCounterclockwise: return "逆时针"
            case .stopRotation: return "停止旋转"
            case .setTravelEnable(let enabled): return enabled ? "打开旋转/行走允许" : "关闭旋转/行走允许"
            case .setCylinderEnable(let enabled): return enabled ? "打开伸缩油缸允许" : "关闭伸缩油缸允许"
            }
        }

        var requiresUnlock: Bool {
            switch self {
            case .stopPump, .stopTravel, .stopRotation:
                return false
            default:
                return true
            }
        }
    }

    enum ImmersiveSpaceState {
        case closed
        case inTransition
        case open
    }

    enum ConnectionMode: String, CaseIterable, Identifiable {
        case automatic
        case manual

        var id: String { rawValue }

        var title: String {
            switch self {
            case .automatic:
                "自动发现"
            case .manual:
                "手动输入"
            }
        }
    }

    let immersiveSpaceID = "ImmersiveSpace"
    var immersiveSpaceState = ImmersiveSpaceState.closed

    var discoveredGateways: [DiscoveredGateway] = []
    var selectedGateway: DiscoveredGateway?
    var connectionStatus = "未连接"
    var controlStatus = "未连接"
    var videoStatus = "未连接"
    var latestSnapshot: GatewaySnapshot?
    var videoConfiguration: VideoConfiguration?
    var latestFrameImage: CGImage?
    var latestFrameSequence: UInt64 = 0
    var latestFrameLabel = "暂无视频画面"
    var latestFrameLatencyMs: Int = 0
    var latestFrameAspectRatio: Double = 0
    var latestFrameType = "未知"
    var isPanoramaEligible = false
    var isSessionArmed = false
    var shouldShowUnlockPrompt = false
    var pendingUnlockActionTitle: String?
    
    // 管片拼装机状态 (Phase 1)
    var assemblerRunning: Bool = false
    var vacuumBoxReady: Bool = false
    var vacuumFault: Bool = false
    var pumpFault: Bool = false
    var heartbeatPLC: Int = 0
    var travelDirectionAN1: Int = 0
    var rotationDirectionAN2: Int = 0
    
    // 管片拼装机控制 (Phase 2)
    var travelEnable: Bool = false
    var cylinderEnable: Bool = false

    var lastServerMessage = "等待连接"
    var latestCommandID: String?
    var latestCommandActionText = "无"
    var latestCommandPhaseText = "等待命令"
    var latestCommandDetail = "尚未发送"
    var latestCommandRoundTripMs = 0
    var isUIFixed = false
    var sources: [ContentSourceItem] = []
    var sourceDetails: [String: ContentSourceItem] = [:]
    var defaultSourceIDs: [String] = []
    var selectedSource: ContentSourceItem?
    var immersivePanoramaSourceID: String?
    var sourceWindowPrefs: [String: WindowPreference] = [:]
    var connectionMode: ConnectionMode = .automatic
    var manualGatewayHost = ""
    var useRelayServer = false
    var manualVideoURLText = ""
    var manualControlURLText = ""
    var lastConnectionAttempt = ""
    var panoramaCacheStatusBySourceID: [String: String] = [:]
    var monitoringSessionID = ""
    var monitoringTrialID = ""
    var receivedFrameCount = 0
    var decodedFrameCount = 0
    var displayedFrameCount = 0
    var networkMissingFrameCount = 0
    var decodeDroppedFrameCount = 0
    var displayDroppedFrameCount = 0
    var latestNetworkLatencyMs = 0
    var latestDecodeLatencyMs = 0
    var latestDisplayLatencyMs = 0
    var latestEndToEndLatencyMs = 0

    enum PendingOpen {
        case web
        case video
        case immersivePanorama
    }

    struct WindowPreference: Codable, Hashable {
        var pinned: Bool
        var scale: Double
    }

    private struct PendingCommandMetric {
        var action: String
        var sendTime: TimeInterval
    }

    var pendingOpen: PendingOpen?

    private let discoveryClient = DiscoveryClient()
    private let videoClient = VideoStreamClient()
    private let controlClient = ControlClient()
    private let frameDecoder = FrameDecodeService()
    private var panoramaDownloadTasks: [String: Task<URL?, Never>] = [:]
    private var pendingUnlockAction: ControlAction?
    private var pendingCommandMetrics: [String: PendingCommandMetric] = [:]
    private var pendingVideoMetricsBySequence: [UInt64: VideoReceiverFrameMetric] = [:]
    private var queuedVideoMetrics: [VideoReceiverFrameMetric] = []
    private var lastReceivedFrameSequence: UInt64?
    private var videoMetricFlushTask: Task<Void, Never>?
    private let panoramaCacheDirectoryURL: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("tsjy-V/panorama-cache", isDirectory: true)
    }()

    init() {
        ensurePanoramaCacheDirectory()
        let frameDecoder = frameDecoder
        discoveryClient.onGatewaysChanged = { [weak self] gateways in
            self?.discoveredGateways = gateways
            if self?.selectedGateway == nil {
                self?.selectedGateway = gateways.first
            }
        }
        videoClient.onStatus = { [weak self] status in
            Task { @MainActor in
                self?.videoStatus = status
                self?.refreshConnectionStatus()
            }
        }
        videoClient.onConfiguration = { [weak self] configuration in
            Task { @MainActor in
                self?.videoConfiguration = configuration
            }
            frameDecoder.update(configuration: configuration)
        }
        videoClient.onFrame = { frame in
            self.recordReceivedFrame(frame)
            frameDecoder.enqueue(frame: frame)
        }
        controlClient.onStatus = { [weak self] status in
            self?.controlStatus = status
            self?.refreshConnectionStatus()
        }
        controlClient.onServerMessage = { [weak self] message in
            self?.handle(serverMessage: message)
        }
        controlClient.onCommandSent = { [weak self] commandID, action in
            self?.recordCommandSent(commandID: commandID, action: action)
        }
        frameDecoder.onDecodedFrame = { [weak self] decoded in
            let displayTime = Date().timeIntervalSince1970
            self?.latestFrameImage = decoded.image
            self?.latestFrameLabel = "帧 #\(decoded.sequence)  \(Int(decoded.size.width))x\(Int(decoded.size.height))"
            self?.latestFrameLatencyMs = max(0, Int(decoded.latency * 1000))
            let ratio = decoded.size.height > 0 ? Double(decoded.size.width / decoded.size.height) : 0
            self?.latestFrameAspectRatio = ratio
            if abs(ratio - 2.0) < 0.05 {
                self?.latestFrameType = "2:1 全景候选"
                self?.isPanoramaEligible = true
            } else if abs(ratio - (16.0 / 9.0)) < 0.05 {
                self?.latestFrameType = "普通 16:9 / 非360"
                self?.isPanoramaEligible = false
            } else {
                self?.latestFrameType = "未识别输入"
                self?.isPanoramaEligible = false
            }
            self?.latestFrameSequence = decoded.sequence
            self?.recordDisplayedFrame(decoded, displayTime: displayTime)
        }
        frameDecoder.onFrameDropped = { [weak self] _ in
            Task { @MainActor in
                self?.decodeDroppedFrameCount += 1
            }
        }
    }

    func startDiscovery() {
        discoveryClient.start()
    }

    func stopDiscovery() {
        discoveryClient.stop()
    }

    func connectSelectedGateway() {
        guard let gateway = selectedGateway,
              let videoURL = gateway.videoURL,
              let controlURL = gateway.controlURL else {
            connectionStatus = "请选择可用网关"
            return
        }

        connect(videoURL: videoURL, controlURL: controlURL, description: "\(gateway.name) \(gateway.host)")
    }

    func connectManualGateway() {
        guard let resolved = resolveManualConnection() else {
            connectionStatus = "请输入主机/IP，或完整的视频/控制 WebSocket 地址"
            return
        }

        connect(
            videoURL: resolved.videoURL,
            controlURL: resolved.controlURL,
            description: resolved.description
        )
    }

    private func connect(videoURL: URL, controlURL: URL, description: String) {
        disconnect()
        latestFrameImage = nil
        latestFrameSequence = 0
        latestFrameLabel = "正在等待视频画面"
        latestFrameLatencyMs = 0
        latestFrameAspectRatio = 0
        latestFrameType = "未知"
        isPanoramaEligible = false
        videoClient.connect(url: videoURL)
        controlClient.connect(url: controlURL)
        lastConnectionAttempt = "视频 \(videoURL.absoluteString) | 控制 \(controlURL.absoluteString)"
        connectionStatus = "正在连接 \(description)"
    }

    func disconnect() {
        videoClient.disconnect()
        controlClient.disconnect()
        latestSnapshot = nil
        isSessionArmed = false
        sources = []
        sourceDetails = [:]
        defaultSourceIDs = []
        selectedSource = nil
        immersivePanoramaSourceID = nil
        pendingOpen = nil
        panoramaCacheStatusBySourceID = [:]
        lastConnectionAttempt = ""
        latestCommandID = nil
        latestCommandActionText = "无"
        latestCommandPhaseText = "等待命令"
        latestCommandDetail = "尚未发送"
        latestCommandRoundTripMs = 0
        pendingCommandMetrics = [:]
        pendingVideoMetricsBySequence = [:]
        queuedVideoMetrics = []
        lastReceivedFrameSequence = nil
        receivedFrameCount = 0
        decodedFrameCount = 0
        displayedFrameCount = 0
        networkMissingFrameCount = 0
        decodeDroppedFrameCount = 0
        displayDroppedFrameCount = 0
        latestNetworkLatencyMs = 0
        latestDecodeLatencyMs = 0
        latestDisplayLatencyMs = 0
        latestEndToEndLatencyMs = 0
        monitoringSessionID = ""
        monitoringTrialID = ""
        videoMetricFlushTask?.cancel()
        videoMetricFlushTask = nil
        refreshConnectionStatus()
    }

    func armControl() {
        controlClient.arm()
    }

    func releaseEmergencyStop() {
        controlClient.releaseEmergencyStop()
        latestCommandPhaseText = "请求解除急停"
        latestCommandDetail = "已向 Mac 发送解除急停请求"
    }

    func startPump() {
        requestControlAction(.startPump)
    }

    func stopPump() {
        requestControlAction(.stopPump)
    }

    func moveForward() {
        requestControlAction(.moveForward)
    }

    func moveBackward() {
        requestControlAction(.moveBackward)
    }

    func stopTravel() {
        requestControlAction(.stopTravel)
    }

    func rotateClockwise() {
        requestControlAction(.rotateClockwise)
    }

    func rotateCounterclockwise() {
        requestControlAction(.rotateCounterclockwise)
    }

    func stopRotation() {
        requestControlAction(.stopRotation)
    }

    func setTravelEnable(_ enable: Bool) {
        requestControlAction(.setTravelEnable(enable))
    }

    func setCylinderEnable(_ enable: Bool) {
        requestControlAction(.setCylinderEnable(enable))
    }

    func connectToGateway(url: String) {
        controlClient.connect(to: url)
    }

    func emergencyStop() {
        controlClient.emergencyStop(reason: "Vision Pro 操作员触发")
        isSessionArmed = false
    }

    func requestControlAction(_ action: ControlAction) {
        guard action.requiresUnlock, !isSessionArmed else {
            performControlAction(action)
            return
        }

        pendingUnlockAction = action
        pendingUnlockActionTitle = action.title
        shouldShowUnlockPrompt = true
    }

    func confirmUnlockPrompt() {
        shouldShowUnlockPrompt = false
        pendingUnlockAction = nil
        pendingUnlockActionTitle = nil
        latestCommandPhaseText = "等待重新解锁"
        latestCommandDetail = "控制已锁定，已请求重新解锁"
        armControl()
    }

    func cancelUnlockPrompt() {
        shouldShowUnlockPrompt = false
        pendingUnlockAction = nil
        pendingUnlockActionTitle = nil
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

    func recordCommandSentForTesting(commandID: String, action: String) {
        recordCommandSent(commandID: commandID, action: action)
    }

    func applyServerMessageForTesting(_ message: ControlServerMessage) {
        handle(serverMessage: message)
    }

    func openSource(id: String) {
        guard let source = sources.first(where: { $0.id == id }) else { return }
        sourceDetails[id] = source
        selectedSource = source
        if source.type.isPanoramaScene {
            immersivePanoramaSourceID = source.id
            pendingOpen = .immersivePanorama
        } else {
            pendingOpen = source.type == .url ? .web : .video
        }
    }

    func useLivePanoramaFeed() {
        immersivePanoramaSourceID = nil
        pendingOpen = nil
    }

    func sourceURLWithAuth(_ source: ContentSourceItem) -> URL? {
        if source.type == .url, let raw = source.url, var components = URLComponents(string: raw) {
            if source.requiresAuth == true, let user = source.username, !user.isEmpty {
                components.user = user
                if let password = source.password, !password.isEmpty {
                    components.password = password
                }
            }
            return components.url
        }
        if source.type == .video || source.type.isPanoramaScene, let raw = source.streamUrl {
            return URL(string: raw)
        }
        return nil
    }

    func localPlaybackURL(for source: ContentSourceItem) async -> URL? {
        guard source.type.isPanoramaScene else {
            return sourceURLWithAuth(source)
        }

        ensurePanoramaCacheDirectory()

        if let localURL = existingCachedURL(for: source) {
            panoramaCacheStatusBySourceID[source.id] = "本地已缓存"
            return localURL
        }

        if let existingTask = panoramaDownloadTasks[source.id] {
            panoramaCacheStatusBySourceID[source.id] = "缓存中"
            return await existingTask.value
        }

        guard let remoteURL = sourceURLWithAuth(source) else {
            panoramaCacheStatusBySourceID[source.id] = "缓存失败"
            return nil
        }

        panoramaCacheStatusBySourceID[source.id] = "缓存中"
        let task = Task<URL?, Never> { [weak self] in
            guard let self else { return nil }
            do {
                let (temporaryURL, response) = try await URLSession.shared.download(from: remoteURL)
                if let http = response as? HTTPURLResponse, !(200...399).contains(http.statusCode) {
                    await MainActor.run {
                        self.panoramaCacheStatusBySourceID[source.id] = "缓存失败"
                        self.panoramaDownloadTasks[source.id] = nil
                    }
                    return nil
                }

                let destinationURL = self.cacheFileURL(for: source)
                try self.replaceCachedFile(at: destinationURL, with: temporaryURL, sourceID: source.id)
                await MainActor.run {
                    self.panoramaCacheStatusBySourceID[source.id] = "本地已缓存"
                    self.panoramaDownloadTasks[source.id] = nil
                }
                return destinationURL
            } catch {
                await MainActor.run {
                    self.panoramaCacheStatusBySourceID[source.id] = "缓存失败"
                    self.panoramaDownloadTasks[source.id] = nil
                }
                return nil
            }
        }
        panoramaDownloadTasks[source.id] = task
        return await task.value
    }

    func prefetchPanoramaSourcesIfNeeded() {
        for source in sources where source.type.isPanoramaScene {
            if existingCachedURL(for: source) != nil {
                panoramaCacheStatusBySourceID[source.id] = "本地已缓存"
                continue
            }
            if panoramaDownloadTasks[source.id] != nil {
                continue
            }
            Task {
                _ = await localPlaybackURL(for: source)
            }
        }
    }

    func cacheStatusText(for sourceID: String) -> String? {
        panoramaCacheStatusBySourceID[sourceID]
    }

    var immersivePanoramaSource: ContentSourceItem? {
        guard let immersivePanoramaSourceID else { return nil }
        return sourceDetails[immersivePanoramaSourceID] ?? sources.first(where: { $0.id == immersivePanoramaSourceID })
    }

    func setWindowPreference(sourceID: String, pinned: Bool, scale: Double) {
        sourceWindowPrefs[sourceID] = WindowPreference(pinned: pinned, scale: scale)
    }

    func windowPreference(sourceID: String) -> WindowPreference {
        sourceWindowPrefs[sourceID] ?? WindowPreference(pinned: false, scale: 1.0)
    }

    private func handle(serverMessage: ControlServerMessage) {
        lastServerMessage = serverMessage.message
        updateCommandReceipt(using: serverMessage)
        if let snapshot = serverMessage.snapshot {
            latestSnapshot = snapshot
            sources = snapshot.contentSources
                .filter { $0.enabled && $0.showOnVisionPro }
                .sorted { $0.sortOrder < $1.sortOrder }
            for source in sources {
                sourceDetails[source.id] = source
            }
            defaultSourceIDs = snapshot.defaultSourceIDs
            if let monitoring = snapshot.monitoring {
                monitoringSessionID = monitoring.sessionID
                monitoringTrialID = monitoring.trialID
            }
            if let assembler = snapshot.devices.first(where: { $0.id == "assembler" }),
               let props = assembler.properties {
                heartbeatPLC = Int(props["heartbeatPLC"] ?? 0)
                assemblerRunning = props["assemblerRunning"] == 1.0
                vacuumBoxReady = props["vacuumBoxReady"] == 1.0
                vacuumFault = props["vacuumFault"] == 1.0
                pumpFault = props["pumpFault"] == 1.0
                travelEnable = props["travelEnable"] == 1.0
                cylinderEnable = props["cylinderEnable"] == 1.0
                travelDirectionAN1 = Int(props["travelDirectionAN1"] ?? 0)
                rotationDirectionAN2 = Int(props["rotationDirectionAN2"] ?? 0)
            }
            if let immersivePanoramaSourceID,
               !sources.contains(where: { $0.id == immersivePanoramaSourceID }) {
                self.immersivePanoramaSourceID = nil
            }
            prefetchPanoramaSourcesIfNeeded()
        }
        isSessionArmed = serverMessage.snapshot?.lockState.contains("已授权") ?? false
        refreshConnectionStatus()
    }

    private func performControlAction(_ action: ControlAction) {
        switch action {
        case .startPump:
            controlClient.startPump()
        case .stopPump:
            controlClient.stopPump()
        case .moveForward:
            controlClient.moveForward()
        case .moveBackward:
            controlClient.moveBackward()
        case .stopTravel:
            controlClient.stopTravel()
        case .rotateClockwise:
            controlClient.rotateClockwise()
        case .rotateCounterclockwise:
            controlClient.rotateCounterclockwise()
        case .stopRotation:
            controlClient.stopRotation()
        case .setTravelEnable(let enable):
            controlClient.setTravelEnable(enable)
        case .setCylinderEnable(let enable):
            controlClient.setCylinderEnable(enable)
        }
    }

    private func recordCommandSent(commandID: String, action: String) {
        pendingCommandMetrics[commandID] = PendingCommandMetric(
            action: action,
            sendTime: Date().timeIntervalSince1970
        )
        latestCommandID = commandID
        latestCommandActionText = commandDisplayName(for: action)
        latestCommandPhaseText = "命令已发送"
        latestCommandDetail = "等待 Mac 回执"
    }

    private func updateCommandReceipt(using serverMessage: ControlServerMessage) {
        if serverMessage.message.contains("PLC 已反馈") {
            latestCommandPhaseText = "PLC 已反馈"
            latestCommandDetail = serverMessage.message
            return
        }

        guard let commandID = serverMessage.commandID,
              commandID == latestCommandID else { return }

        if serverMessage.type == "commandResult" {
            latestCommandPhaseText = serverMessage.accepted ? "Mac 已执行" : "执行失败"
            if let metric = pendingCommandMetrics[commandID] {
                let receiveTime = Date().timeIntervalSince1970
                let ackReference = serverMessage.resultSendTimestamp ?? receiveTime
                let roundTripMs = max(0, Int((ackReference - metric.sendTime) * 1000))
                latestCommandRoundTripMs = roundTripMs
                latestCommandDetail = "\(serverMessage.message) | 往返 \(roundTripMs) ms"
                pendingCommandMetrics.removeValue(forKey: commandID)
            } else {
                latestCommandDetail = serverMessage.message
            }
            controlClient.sendFeedbackRendered(for: commandID)
        } else if serverMessage.type == "alarm" {
            latestCommandPhaseText = "急停已执行"
            latestCommandDetail = serverMessage.message
        } else if serverMessage.type == "error" {
            latestCommandPhaseText = "执行失败"
            latestCommandDetail = serverMessage.message
        }
    }

    private func recordReceivedFrame(_ frame: FrameSnapshot) {
        Task { @MainActor in
            if let lastReceivedFrameSequence, frame.sequence > lastReceivedFrameSequence + 1 {
                networkMissingFrameCount += Int(frame.sequence - lastReceivedFrameSequence - 1)
            }
            self.lastReceivedFrameSequence = frame.sequence
            receivedFrameCount += 1
            pendingVideoMetricsBySequence[frame.sequence] = VideoReceiverFrameMetric(
                sequence: frame.sequence,
                receiveTimestamp: frame.receiveTimestamp,
                decodeFinishTimestamp: nil,
                displayTimestamp: nil
            )
            latestNetworkLatencyMs = max(0, Int((frame.receiveTimestamp - frame.timestamp) * 1000))
        }
    }

    private func recordDisplayedFrame(_ decoded: FrameDecodeService.DecodedFrame, displayTime: TimeInterval) {
        decodedFrameCount += 1
        displayedFrameCount += 1
        latestNetworkLatencyMs = max(0, Int((decoded.receiveTimestamp - decoded.frameTimestamp) * 1000))
        latestDecodeLatencyMs = max(0, Int((decoded.decodeFinishTimestamp - decoded.receiveTimestamp) * 1000))
        latestDisplayLatencyMs = max(0, Int((displayTime - decoded.decodeFinishTimestamp) * 1000))
        latestEndToEndLatencyMs = max(0, Int((displayTime - decoded.frameTimestamp) * 1000))

        var metric = pendingVideoMetricsBySequence.removeValue(forKey: decoded.sequence) ?? VideoReceiverFrameMetric(
            sequence: decoded.sequence,
            receiveTimestamp: decoded.receiveTimestamp,
            decodeFinishTimestamp: nil,
            displayTimestamp: nil
        )
        metric.decodeFinishTimestamp = decoded.decodeFinishTimestamp
        metric.displayTimestamp = displayTime
        queuedVideoMetrics.append(metric)
        flushVideoMetricsIfNeeded()
    }

    private func flushVideoMetricsIfNeeded() {
        if queuedVideoMetrics.count >= 8 {
            flushVideoMetrics()
            return
        }
        guard videoMetricFlushTask == nil else { return }
        videoMetricFlushTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            await MainActor.run {
                self?.flushVideoMetrics()
            }
        }
    }

    private func flushVideoMetrics() {
        videoMetricFlushTask?.cancel()
        videoMetricFlushTask = nil
        guard !queuedVideoMetrics.isEmpty else { return }
        let sessionID = monitoringSessionID.isEmpty ? "vision-session-\(UUID().uuidString.prefix(8))" : monitoringSessionID
        let batch = VideoMetricBatchPayload(
            sessionID: sessionID,
            frames: queuedVideoMetrics,
            receivedFrameCount: receivedFrameCount,
            decodedFrameCount: decodedFrameCount,
            displayedFrameCount: displayedFrameCount,
            networkMissingFrameCount: networkMissingFrameCount,
            decodeDroppedFrameCount: decodeDroppedFrameCount,
            displayDroppedFrameCount: displayDroppedFrameCount,
            latestEndToEndLatencyMs: latestEndToEndLatencyMs
        )
        controlClient.sendVideoMetricBatch(batch)
        queuedVideoMetrics.removeAll(keepingCapacity: true)
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

    private func refreshConnectionStatus() {
        if controlStatus.contains("断开") || controlStatus.contains("失败")
            || videoStatus.contains("断开") || videoStatus.contains("失败") {
            if lastConnectionAttempt.isEmpty {
                connectionStatus = "连接失败 | 视频: \(videoStatus) | 控制: \(controlStatus)"
            } else {
                connectionStatus = "连接失败 | \(lastConnectionAttempt)"
            }
        } else if controlStatus.contains("连接中") || videoStatus.contains("连接中") {
            if lastConnectionAttempt.isEmpty {
                connectionStatus = "连接中 | 视频: \(videoStatus) | 控制: \(controlStatus)"
            } else {
                connectionStatus = "连接中 | \(lastConnectionAttempt)"
            }
        } else if controlStatus.contains("已连接") || videoStatus.contains("已连接") {
            connectionStatus = "视频: \(videoStatus) | 控制: \(controlStatus)"
        } else {
            connectionStatus = "未连接"
        }
    }

    var manualConnectionPreviewText: String {
        guard let resolved = resolveManualConnection() else {
            return "待生成 WebSocket 地址"
        }
        return "视频: \(resolved.videoURL.absoluteString)\n控制: \(resolved.controlURL.absoluteString)"
    }

    private func resolveManualConnection() -> (videoURL: URL, controlURL: URL, description: String)? {
        let host = manualGatewayHost.trimmingCharacters(in: .whitespacesAndNewlines)
        let videoText = manualVideoURLText.trimmingCharacters(in: .whitespacesAndNewlines)
        let controlText = manualControlURLText.trimmingCharacters(in: .whitespacesAndNewlines)

        let videoURL = !videoText.isEmpty
            ? normalizeSocketURL(videoText, defaultPort: TSJYNetwork.videoPort)
            : (!host.isEmpty ? makeSocketURL(host: host, port: TSJYNetwork.videoPort) : nil)
        let controlURL = !controlText.isEmpty
            ? normalizeSocketURL(controlText, defaultPort: TSJYNetwork.controlPort)
            : (!host.isEmpty ? makeSocketURL(host: host, port: TSJYNetwork.controlPort) : nil)

        guard let videoURL, let controlURL else { return nil }
        let description = host.isEmpty ? (videoURL.host ?? videoURL.absoluteString) : host
        return (videoURL, controlURL, description)
    }

    private func normalizeSocketURL(_ text: String, defaultPort: Int) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.contains("://") {
            let normalizedText = normalizedSocketURLString(trimmed)
            guard var components = URLComponents(string: normalizedText) else { return nil }
            if components.scheme == nil {
                components.scheme = "ws"
            }
            if components.port == nil {
                components.port = defaultPort
            }
            if useRelayServer, components.path.isEmpty || components.path == "/" {
                components.path = "/consumer"
            }
            return components.url
        }
        return makeSocketURL(host: trimmed, port: defaultPort)
    }

    private func makeSocketURL(host: String, port: Int) -> URL? {
        let trimmed = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let hostOnly = normalizedURLHost(trimmed)
        if let components = URLComponents(string: trimmed), components.host != nil {
            var normalized = components
            normalized.scheme = normalized.scheme ?? "ws"
            normalized.port = normalized.port ?? port
            if useRelayServer {
                normalized.path = "/consumer"
            }
            return normalized.url
        }

        var components = URLComponents()
        components.scheme = "ws"
        applyNormalizedHost(hostOnly, to: &components)
        components.port = port
        if useRelayServer {
            components.path = "/consumer"
        }
        return components.url
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

    private func normalizedSocketURLString(_ value: String) -> String {
        guard let schemeRange = value.range(of: "://") else {
            return value
        }
        let prefix = value[..<schemeRange.upperBound]
        let suffix = value[schemeRange.upperBound...]
        guard !suffix.hasPrefix("["),
              let slashIndex = suffix.firstIndex(where: { $0 == "/" || $0 == "?" || $0 == "#" }) else {
            let authority = String(suffix)
            if authority.filter({ $0 == ":" }).count >= 2 {
                return "\(prefix)[\(authority)]"
            }
            return value
        }

        let authority = String(suffix[..<slashIndex])
        let remainder = String(suffix[slashIndex...])
        if authority.filter({ $0 == ":" }).count >= 2 {
            return "\(prefix)[\(authority)]\(remainder)"
        }
        return value
    }

    private func ensurePanoramaCacheDirectory() {
        do {
            try FileManager.default.createDirectory(at: panoramaCacheDirectoryURL, withIntermediateDirectories: true)
        } catch {
            lastServerMessage = "创建本地缓存目录失败: \(error.localizedDescription)"
        }
    }

    private func existingCachedURL(for source: ContentSourceItem) -> URL? {
        let candidate = cacheFileURL(for: source)
        if FileManager.default.fileExists(atPath: candidate.path) {
            return candidate
        }
        return nil
    }

    private func cacheFileURL(for source: ContentSourceItem) -> URL {
        let ext = cacheFileExtension(for: source)
        let updatedSlug = source.updatedAt
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: ".", with: "-")
        return panoramaCacheDirectoryURL
            .appendingPathComponent("\(source.id)-\(updatedSlug)", isDirectory: false)
            .appendingPathExtension(ext)
    }

    private func cacheFileExtension(for source: ContentSourceItem) -> String {
        if let relativePath = source.mediaRelativePath,
           !relativePath.isEmpty,
           let ext = relativePath.split(separator: "/").last?.split(separator: ".").last,
           !ext.isEmpty {
            return String(ext)
        }
        if let streamURL = source.streamUrl,
           let url = URL(string: streamURL) {
            let ext = url.pathExtension
            if !ext.isEmpty {
                return ext
            }
        }
        switch source.type {
        case .panoramaPhoto:
            return "jpg"
        case .panoramaVideo:
            return "mp4"
        default:
            return "bin"
        }
    }

    private func replaceCachedFile(at destinationURL: URL, with temporaryURL: URL, sourceID: String) throws {
        let fileManager = FileManager.default
        let prefix = "\(sourceID)-"
        if let existingFiles = try? fileManager.contentsOfDirectory(at: panoramaCacheDirectoryURL, includingPropertiesForKeys: nil) {
            for fileURL in existingFiles where fileURL.lastPathComponent.hasPrefix(prefix) {
                try? fileManager.removeItem(at: fileURL)
            }
        }
        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }
        try fileManager.moveItem(at: temporaryURL, to: destinationURL)
    }
}

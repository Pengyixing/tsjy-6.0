import AppKit
import SceneKit
import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var appModel
    @State private var selectedTab: DashboardTab = .streaming
    @State private var sourceDraft = ContentSourceDraft()
    private let dashboardColumns = [
        GridItem(.flexible(minimum: 180), spacing: 16),
        GridItem(.flexible(minimum: 180), spacing: 16),
        GridItem(.flexible(minimum: 180), spacing: 16),
        GridItem(.flexible(minimum: 180), spacing: 16)
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    heroSection
                    tabPicker
                    if selectedTab == .streaming {
                        overviewSection
                        contentSection
                    } else {
                        sourceManagementSection
                    }
                }
                .frame(maxWidth: 1200, alignment: .leading)
                .padding(24)
                .frame(maxWidth: .infinity)
            }
            .background(Color(nsColor: .windowBackgroundColor))
            .navigationTitle("tsjy 边缘网关")
        }
        .task {
            await appModel.refreshCameras()
            syncDraftFromSelection()
        }
        .onChange(of: appModel.selectedContentSourceID) { _, _ in
            syncDraftFromSelection()
        }
        .onChange(of: appModel.contentSources) { _, _ in
            if appModel.selectedContentSourceID == nil {
                appModel.selectContentSource(id: appModel.contentSources.first?.id)
            }
        }
    }

    private var tabPicker: some View {
        HStack {
            Spacer()
            Picker("工作区", selection: $selectedTab) {
                ForEach(DashboardTab.allCases) { tab in
                    Text(tab.title).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 240)
            Spacer()
        }
    }

    private var heroSection: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.blue.opacity(0.9),
                            Color.indigo.opacity(0.85),
                            Color.cyan.opacity(0.8)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("tsjy 远程施工网关")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(.white)
                        Text(appModel.gatewayName)
                            .font(.headline)
                            .foregroundStyle(.white.opacity(0.9))
                        Label(appModel.gatewayStatus, systemImage: appModel.isGatewayRunning ? "dot.radiowaves.left.and.right" : "pause.circle")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                    }
                    Spacer()
                    HStack(spacing: 12) {
                        Button("刷新摄像头") {
                            Task { await appModel.refreshCameras() }
                        }
                        .buttonStyle(.bordered)
                        .tint(.white)

                        if appModel.isGatewayRunning {
                            Button("停止网关", role: .destructive) {
                                appModel.stopGateway()
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.black.opacity(0.75))
                        } else {
                            Button("启动网关") {
                                appModel.startGateway()
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.white)
                            .foregroundStyle(.blue)
                        }
                    }
                }
                HStack(spacing: 16) {
                    Label("视频 \(appModel.connectedVideoClients)", systemImage: "video")
                    Label("控制 \(appModel.connectedControlClients)", systemImage: "switch.2")
                    Label(appModel.latestSnapshot.lockState, systemImage: "lock.shield")
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white.opacity(0.95))
            }
            .padding(24)
        }
        .frame(minHeight: 180)
    }

    private var overviewSection: some View {
        LazyVGrid(columns: dashboardColumns, spacing: 16) {
            StatusTile(
                title: "当前摄像头",
                value: appModel.selectedCameraName,
                detail: "视频源设备",
                color: .blue,
                systemImage: "camera"
            )
            StatusTile(
                title: "视频状态",
                value: appModel.lastFrameInfo,
                detail: "原始帧编码后推流",
                color: .purple,
                systemImage: "waveform.badge.magnifyingglass"
            )
            StatusTile(
                title: "现场接口",
                value: appModel.siteStatus,
                detail: "Mac 本地 Modbus TCP Server，等待 PLC 主动连接",
                color: .orange,
                systemImage: "network"
            )
            StatusTile(
                title: "控制锁",
                value: appModel.latestSnapshot.lockState,
                detail: "远程权限状态",
                color: .green,
                systemImage: "lock.shield"
            )
        }
    }

    private var contentSection: some View {
        HStack(alignment: .top, spacing: 20) {
            VStack(spacing: 20) {
                gatewaySection
                siteSection
                assemblerFeedbackSection
                assemblerControlSection
            }
            .frame(maxWidth: 420, alignment: .topLeading)

            VStack(spacing: 20) {
                previewSection
                videoRecordingSection
                inspectionSection
                deviceSection
                logSection
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private var sourceManagementSection: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Menu("新增源") {
                    Button("URL") {
                        appModel.addContentSource(type: .url)
                    }
                    Button("VIDEO") {
                        appModel.addContentSource(type: .video)
                    }
                }
                Button("导入 360 文件") {
                    importPanoramaFiles()
                }
                Button("导入 360 目录") {
                    importPanoramaDirectory()
                }
                if appModel.suggestedPanoramaImportPath != nil {
                    Button("导入默认 360素材") {
                        appModel.importSuggestedPanoramaDirectory()
                    }
                }
                Button("删除源") {
                    appModel.removeSelectedContentSource()
                }
                .disabled(appModel.selectedContentSourceID == nil)
                Button("刷新状态") {
                    appModel.refreshContentSourceStatus()
                }
                Button("同步到 Vision Pro") {
                    appModel.syncContentSourcesToVision()
                }
                Spacer()
            }

            HStack(alignment: .top, spacing: 20) {
                sourceListPane
                sourceEditorPane
            }
        }
    }

    private var gatewaySection: some View {
        DashboardPanel(title: "网关配置", systemImage: "slider.horizontal.3") {
            VStack(alignment: .leading, spacing: 14) {
                Picker("摄像头", selection: Binding(
                    get: { appModel.selectedCameraID ?? "" },
                    set: { appModel.selectCamera(id: $0) }
                )) {
                    ForEach(appModel.availableCameras) { camera in
                        Text(camera.name).tag(camera.id)
                    }
                }
                .pickerStyle(.menu)

                Picker("传输画质", selection: Binding(
                    get: { appModel.selectedVideoQualityMode },
                    set: { appModel.updateVideoQualityMode($0) }
                )) {
                    ForEach(VideoQualityMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                Divider()

                LabeledContent("当前摄像头", value: appModel.selectedCameraName)
                LabeledContent("传输画质", value: appModel.selectedVideoQualityMode.displayName)
                LabeledContent("视频连接", value: "\(appModel.connectedVideoClients)")
                LabeledContent("控制连接", value: "\(appModel.connectedControlClients)")
                LabeledContent("视频编码", value: appModel.lastFrameInfo)

                Divider()

                Text("Vision Pro 局域网直连地址")
                    .font(.subheadline.weight(.semibold))
                Text("如果在同一个 Wi-Fi 下，可以直接在 Vision Pro 输入下面的私网地址。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                if !appModel.gatewayReachableHosts.isEmpty {
                    ForEach(appModel.gatewayReachableHosts, id: \.self) { host in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(host)
                                .font(.caption.monospaced())
                            HStack(spacing: 8) {
                                copyButton(title: "复制视频", value: appModel.publishedVideoSocketURL(host: host))
                                copyButton(title: "复制控制", value: appModel.publishedControlSocketURL(host: host))
                            }
                        }
                        .padding(.top, 4)
                    }
                }
                
                Divider()

                Text("跨网络公网中继配置 (可选)")
                    .font(.subheadline.weight(.semibold))
                Text("如果要在非局域网环境下演示，请输入公网中继服务器域名、IPv4 或 IPv6。IPv6 建议优先使用域名，或手动写成 `[2001:db8::10]` 这种形式。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                TextField("例如: relay.example.com / 123.45.67.89 / [2001:db8::10]", text: Binding(
                    get: { appModel.relayServerHost },
                    set: {
                        appModel.relayServerHost = $0
                        appModel.refreshRelayStatusForConfiguration()
                    }
                ))
                .textFieldStyle(.roundedBorder)

                LabeledContent("中继目标", value: appModel.relayTargetDescription)
                LabeledContent("中继视频", value: appModel.relayVideoStatus)
                LabeledContent("中继控制", value: appModel.relayControlStatus)

                if appModel.relayLastError != "无" {
                    Text("最近中继错误: \(appModel.relayLastError)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var deviceSection: some View {
        DashboardPanel(title: "施工设备", systemImage: "gearshape.2") {
            VStack(alignment: .leading, spacing: 12) {
                Text("控制锁状态: \(appModel.latestSnapshot.lockState)")
                    .font(.headline)

                ForEach(appModel.latestSnapshot.devices) { device in
                    DeviceCard(device: device)
                }

                HStack {
                    Spacer()
                    Button("本地急停", role: .destructive) {
                        appModel.sendMockEmergencyStop()
                    }
                    .buttonStyle(.borderedProminent)

                    Button("解除急停") {
                        appModel.releaseEmergencyStop()
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    private var siteSection: some View {
        DashboardPanel(title: "现场接口 (Modbus TCP Server)", systemImage: "point.3.connected.trianglepath.dotted") {
            VStack(alignment: .leading, spacing: 14) {
                Text("本机监听地址和端口。PLC 作为 Client，应主动读取这台 Mac 的局域网 IP:5020。")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)

                TextField(SiteConnectionConfig.defaultModbusEndpoint, text: Binding(
                    get: { appModel.siteEndpointText },
                    set: { appModel.siteEndpointText = $0 }
                ))
                .textFieldStyle(.roundedBorder)

                HStack(spacing: 12) {
                    Button("启动现场接口") {
                        appModel.connectSite()
                    }
                    .buttonStyle(.borderedProminent)

                    Button("断开现场接口") {
                        appModel.disconnectSite()
                    }
                    .buttonStyle(.bordered)
                }

                Divider()
                Text(appModel.siteStatus)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var assemblerFeedbackSection: some View {
        DashboardPanel(title: "现场设备反馈状态 (PLC → Mac)", systemImage: "sensor.tag.radiowaves.forward") {
            if let assembler = appModel.latestSnapshot.devices.first(where: { $0.id == "assembler" }) {
                let props = assembler.properties ?? [:]
                let heartbeat = Int(props["heartbeatPLC"] ?? 0)
                let assemblerRunning = props["assemblerRunning"] == 1.0
                let vacuumBoxReady = props["vacuumBoxReady"] == 1.0
                let vacuumFault = props["vacuumFault"] == 1.0
                let pumpFault = props["pumpFault"] == 1.0
                let travelDirectionAN1 = Int(props["travelDirectionAN1"] ?? 0)
                let rotationDirectionAN2 = Int(props["rotationDirectionAN2"] ?? 0)
                
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text("PLC 心跳 (100):")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text("\(heartbeat)")
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.primary)
                    }
                    
                    HStack(spacing: 24) {
                        feedbackIndicator(title: "拼装机运行 (101)", isOn: assemblerRunning, activeColor: .green)
                        feedbackIndicator(title: "真空箱就绪 (102)", isOn: vacuumBoxReady, activeColor: .green)
                    }
                    
                    HStack(spacing: 24) {
                        feedbackIndicator(title: "真空故障 (103)", isOn: vacuumFault, activeColor: .red)
                        feedbackIndicator(title: "泵站故障 (104)", isOn: pumpFault, activeColor: .red)
                    }

                    Divider()

                    LabeledContent("AN1 / 40015") {
                        Text("\(travelDirectionAN1) (\(appModel.travelDirectionText(value: travelDirectionAN1)))")
                            .font(.subheadline.monospacedDigit())
                    }

                    LabeledContent("AN2 / 40016") {
                        Text("\(rotationDirectionAN2) (\(appModel.rotationDirectionText(value: rotationDirectionAN2)))")
                            .font(.subheadline.monospacedDigit())
                    }
                }
            } else {
                Text("等待设备数据...")
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func feedbackIndicator(title: String, isOn: Bool, activeColor: Color) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(isOn ? activeColor : Color.gray.opacity(0.3))
                .frame(width: 12, height: 12)
            Text(title)
                .font(.subheadline)
                .foregroundStyle(isOn ? .primary : .secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var assemblerControlSection: some View {
        DashboardPanel(title: "管片拼装机调试控制", systemImage: "gamecontroller") {
            if let assembler = appModel.latestSnapshot.devices.first(where: { $0.id == "assembler" }) {
                let props = assembler.properties ?? [:]
                let travelEnable = props["travelEnable"] == 1.0
                let cylinderEnable = props["cylinderEnable"] == 1.0
                
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 12) {
                        Button("启动泵") {
                            appModel.executeLocalSiteCommand(deviceID: "assembler", action: "startPump")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.blue)

                        Button("停止泵") {
                            appModel.executeLocalSiteCommand(deviceID: "assembler", action: "stopPump")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                    }

                    HStack(spacing: 12) {
                        Button("前进") {
                            appModel.executeLocalSiteCommand(deviceID: "assembler", action: "moveForward")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.indigo)

                        Button("后退") {
                            appModel.executeLocalSiteCommand(deviceID: "assembler", action: "moveBackward")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                    }

                    HStack(spacing: 12) {
                        Button("停止行走") {
                            appModel.executeLocalSiteCommand(deviceID: "assembler", action: "stopTravel")
                        }
                        .buttonStyle(.bordered)

                        Button("顺时针") {
                            appModel.executeLocalSiteCommand(deviceID: "assembler", action: "rotateClockwise")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.purple)

                        Button("逆时针") {
                            appModel.executeLocalSiteCommand(deviceID: "assembler", action: "rotateCounterclockwise")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.teal)

                        Button("停止旋转") {
                            appModel.executeLocalSiteCommand(deviceID: "assembler", action: "stopRotation")
                        }
                        .buttonStyle(.bordered)
                    }

                    Divider()

                    Toggle("旋转/行走允许", isOn: Binding(
                        get: { travelEnable },
                        set: { newValue in
                            appModel.executeLocalSiteCommand(deviceID: "assembler", action: "setParameter", parameters: ["travelEnable": newValue ? 1 : 0])
                        }
                    ))
                    
                    Toggle("伸缩油缸允许", isOn: Binding(
                        get: { cylinderEnable },
                        set: { newValue in
                            appModel.executeLocalSiteCommand(deviceID: "assembler", action: "setParameter", parameters: ["cylinderEnable": newValue ? 1 : 0])
                        }
                    ))
                }
            } else {
                Text("等待设备数据...")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var previewSection: some View {
        DashboardPanel(title: "原始帧预览", systemImage: "photo.on.rectangle") {
            VStack(alignment: .leading, spacing: 14) {
                Text("这里显示的是刚从 Mac 摄像头采集出来的原始帧，不做任何球面投影、不做拉伸判断。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                RawFramePane(image: appModel.rawPreviewImage)
            }
        }
    }

    private var videoRecordingSection: some View {
        DashboardPanel(title: "视频录制", systemImage: "record.circle") {
            VStack(alignment: .leading, spacing: 14) {
                LabeledContent("录像状态", value: appModel.videoRecordingStatus)
                LabeledContent("录像目录", value: appModel.videoRecordingDirectoryPath)
                LabeledContent("当前文件", value: appModel.activeVideoRecordingFilePath)

                HStack(spacing: 10) {
                    Button("开始录制") {
                        appModel.startVideoRecording()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(appModel.isVideoRecording)

                    Button("结束录制") {
                        Task {
                            await appModel.stopVideoRecording()
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(!appModel.isVideoRecording)

                    Button("打开录像目录") {
                        openVideoRecordingDirectory()
                    }
                    .buttonStyle(.bordered)
                }

                Text("录像文件统一写入 Mac 本地专用视频记录文件夹，便于后续查找和归档。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var inspectionSection: some View {
        DashboardPanel(title: "输入判定与球面检查", systemImage: "scope") {
            VStack(alignment: .leading, spacing: 14) {
                LabeledContent("原始帧尺寸", value: "\(appModel.rawFrameWidth)x\(appModel.rawFrameHeight)")
                LabeledContent("原始帧比例", value: String(format: "%.3f", appModel.rawFrameAspectRatio))
                LabeledContent("判定类型", value: appModel.rawFrameType)
                LabeledContent("投影模式", value: appModel.projectionMode)
                LabeledContent("球面贴图", value: appModel.isSpherePreviewEnabled ? "已启用" : "已禁用")
                LabeledContent("原始帧保存", value: appModel.rawFramesDirectory)

                if !appModel.supportedFormats.isEmpty {
                    Divider()
                    Text("当前摄像头支持格式")
                        .font(.subheadline.weight(.semibold))
                    ForEach(appModel.supportedFormats.prefix(8)) { format in
                        Text(format.displayText)
                            .font(.caption.monospaced())
                            .foregroundStyle(format.isPanoramaCandidate ? .green : .secondary)
                    }
                }

                Divider()

                if appModel.isSpherePreviewEnabled {
                    PanoramaInspectorPanel(image: appModel.rawPreviewImage)
                } else {
                    DisabledSpherePanel(
                        message: "当前输入不是 2:1 全景候选，已禁止进入球面贴图，避免把普通 16:9 画面错误当成全景。"
                    )
                }
            }
        }
    }

    private var logSection: some View {
        DashboardPanel(title: "运行日志", systemImage: "terminal") {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("试验监测")
                        .font(.subheadline.weight(.semibold))
                    LabeledContent("会话编号", value: appModel.monitoringSessionID)
                    LabeledContent("当前记录", value: appModel.monitoringTrialID)
                    LabeledContent("监测模式", value: appModel.monitoringMode)
                    LabeledContent("记录状态", value: appModel.monitoringCurrentTrialState)
                    LabeledContent("视频统计", value: "收 \(appModel.monitoringReceivedFrameCount) / 解 \(appModel.monitoringDecodedFrameCount) / 显 \(appModel.monitoringDisplayedFrameCount)")
                    LabeledContent("最新命令往返", value: "\(appModel.monitoringLastCommandRoundTripMs) ms")
                    LabeledContent("最新端到端视频时延", value: "\(appModel.monitoringLatestEndToEndLatencyMs) ms")
                    Text(appModel.monitoringSummaryText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(appModel.monitoringLastBatchSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 10) {
                        TextField(
                            "记录编号",
                            text: Binding(
                                get: { appModel.monitoringTrialID },
                                set: { appModel.monitoringTrialID = $0 }
                            )
                        )
                        TextField(
                            "试验工况",
                            text: Binding(
                                get: { appModel.monitoringConditionName },
                                set: { appModel.monitoringConditionName = $0 }
                            )
                        )
                        TextField(
                            "操作者",
                            text: Binding(
                                get: { appModel.monitoringOperatorID },
                                set: { appModel.monitoringOperatorID = $0 }
                            )
                        )
                    }
                    TextField(
                        "试验备注",
                        text: Binding(
                            get: { appModel.monitoringNotes },
                            set: { appModel.monitoringNotes = $0 }
                        )
                    )
                    Toggle(
                        "启用试验记录",
                        isOn: Binding(
                            get: { appModel.isMonitoringRecording },
                            set: { appModel.isMonitoringRecording = $0 }
                        )
                    )
                    .toggleStyle(.switch)
                    HStack(spacing: 10) {
                        Button("新建监测会话") {
                            appModel.startNewMonitoringSession()
                        }
                        .buttonStyle(.bordered)

                        Button("开始记录") {
                            appModel.startMonitoringRecording()
                        }
                        .buttonStyle(.borderedProminent)

                        Button("结束记录并导出") {
                            appModel.stopMonitoringRecording(notes: appModel.monitoringNotes)
                        }
                        .buttonStyle(.bordered)
                    }

                    if !appModel.monitoringTrialHistory.isEmpty {
                        Divider()
                        Text("最近记录")
                            .font(.caption.weight(.semibold))
                        ForEach(appModel.monitoringTrialHistory.suffix(5).reversed()) { record in
                            HStack {
                                Text(record.trialID)
                                    .font(.caption.monospaced())
                                Text(record.conditionName)
                                    .font(.caption)
                                Spacer()
                                Text("已导出")
                                    .font(.caption)
                                    .foregroundStyle(.green)
                                Text("\(record.commandRoundTripMs) ms")
                                    .font(.caption.monospaced())
                            }
                        }
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    LabeledContent("导出目录", value: appModel.stateExportDirectoryPath.isEmpty ? "未设置" : appModel.stateExportDirectoryPath)
                    LabeledContent("当前记录表", value: appModel.activeStateExportFilePath)
                    HStack(spacing: 10) {
                        Button("选择导出目录") {
                            chooseStateExportDirectory()
                        }
                        .buttonStyle(.bordered)

                        Button("打开导出目录") {
                            openStateExportDirectory()
                        }
                        .buttonStyle(.bordered)
                        .disabled(appModel.stateExportDirectoryPath.isEmpty)

                        Button("关闭导出") {
                            appModel.clearStateExportDirectory()
                        }
                        .buttonStyle(.bordered)
                        .disabled(appModel.stateExportDirectoryPath.isEmpty)
                    }
                }

                Divider()

                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(appModel.logEntries.prefix(50)) { entry in
                            HStack(alignment: .top, spacing: 10) {
                                Text(entry.timestamp)
                                    .foregroundStyle(.secondary)
                                Text(entry.message)
                                    .textSelection(.enabled)
                                Spacer(minLength: 0)
                            }
                            .font(.system(.caption, design: .monospaced))
                            .padding(.vertical, 3)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minHeight: 220, maxHeight: 280)
            }
        }
    }

    private var sourceListPane: some View {
        DashboardPanel(title: "源列表", systemImage: "list.bullet.rectangle") {
            VStack(alignment: .leading, spacing: 10) {
                List(selection: Binding(
                    get: { appModel.selectedContentSourceID },
                    set: { appModel.selectContentSource(id: $0) }
                )) {
                    ForEach(appModel.contentSources) { source in
                        HStack(spacing: 10) {
                            Image(systemName: source.type.symbolName)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(source.name)
                                Text("\(source.type.displayName) • \(source.group)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(source.lastStatus ?? "unknown")
                                .font(.caption2.monospaced())
                                .foregroundStyle((source.lastStatus ?? "") == "ok" ? .green : .secondary)
                        }
                        .tag(Optional(source.id))
                    }
                }
                .frame(minHeight: 520)

                HStack {
                    Button("上移") {
                        appModel.moveSelectedContentSourceUp()
                    }
                    .disabled(appModel.selectedContentSourceID == nil)
                    Button("下移") {
                        appModel.moveSelectedContentSourceDown()
                    }
                    .disabled(appModel.selectedContentSourceID == nil)
                }
            }
        }
        .frame(minWidth: 340, maxWidth: 360)
    }

    private var sourceEditorPane: some View {
        DashboardPanel(title: "源详情 / 编辑", systemImage: "square.and.pencil") {
            if appModel.selectedContentSourceID == nil {
                Text("请选择一个内容源")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 520)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        TextField("名称", text: $sourceDraft.name)
                        Picker("类型", selection: $sourceDraft.type) {
                            Text(ContentSourceType.url.displayName).tag(ContentSourceType.url)
                            Text(ContentSourceType.video.displayName).tag(ContentSourceType.video)
                            Text(ContentSourceType.panoramaPhoto.displayName).tag(ContentSourceType.panoramaPhoto)
                            Text(ContentSourceType.panoramaVideo.displayName).tag(ContentSourceType.panoramaVideo)
                        }
                        .pickerStyle(.menu)

                        TextField("分组", text: $sourceDraft.group)
                        TextField("图标", text: $sourceDraft.icon)
                        TextField("描述", text: $sourceDraft.description)

                        Toggle("启用", isOn: $sourceDraft.enabled)
                        Toggle("Vision Pro 显示", isOn: $sourceDraft.showOnVisionPro)
                        Toggle("默认显示", isOn: $sourceDraft.defaultVisible)

                        if sourceDraft.type == .url {
                            TextField("URL 地址", text: $sourceDraft.url)
                            Toggle("允许刷新", isOn: $sourceDraft.allowRefresh)
                            Toggle("需要认证", isOn: $sourceDraft.requiresAuth)
                            Toggle("通过 Mac 代理", isOn: $sourceDraft.proxyThroughMac)
                            if sourceDraft.requiresAuth {
                                TextField("用户名", text: $sourceDraft.username)
                                SecureField("密码", text: $sourceDraft.password)
                            }
                        } else if sourceDraft.type == .video {
                            TextField("视频流地址", text: $sourceDraft.streamUrl)
                            TextField("协议", text: $sourceDraft.streamProtocol)
                            Toggle("默认静音", isOn: $sourceDraft.muted)
                        } else {
                            LabeledContent("本地文件", value: sourceDraft.localFilePath.isEmpty ? "未绑定" : sourceDraft.localFilePath)
                            LabeledContent("发布 URL", value: sourceDraft.streamUrl.isEmpty ? "待生成" : sourceDraft.streamUrl)
                            LabeledContent("相对路径", value: sourceDraft.mediaRelativePath.isEmpty ? "未设置" : sourceDraft.mediaRelativePath)
                            if sourceDraft.type == .panoramaVideo {
                                Toggle("默认静音", isOn: $sourceDraft.muted)
                            }
                        }

                        TextField("宽度", value: $sourceDraft.width, format: .number)
                        TextField("高度", value: $sourceDraft.height, format: .number)

                        HStack(spacing: 10) {
                            Button("保存") {
                                saveCurrentDraft()
                            }
                            .buttonStyle(.borderedProminent)

                            Button("测试打开") {
                                appModel.refreshContentSourceStatus()
                            }
                            .buttonStyle(.bordered)

                            Button("复制 ID") {
                                if let id = appModel.selectedContentSourceID {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(id, forType: .string)
                                }
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .padding(.top, 6)
                }
                .frame(minHeight: 520)
            }
        }
    }

    private func syncDraftFromSelection() {
        guard let id = appModel.selectedContentSourceID,
              let source = appModel.contentSources.first(where: { $0.id == id }) else {
            sourceDraft = ContentSourceDraft()
            return
        }
        sourceDraft = ContentSourceDraft(source: source)
    }

    @ViewBuilder
    private func labeledSocketRow(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Text(value)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                copyButton(title: "复制", value: value)
            }
        }
    }

    @ViewBuilder
    private func copyButton(title: String, value: String) -> some View {
        Button(title) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(value, forType: .string)
        }
        .buttonStyle(.bordered)
    }

    private func saveCurrentDraft() {
        guard let id = appModel.selectedContentSourceID else { return }
        let order = appModel.contentSources.firstIndex(where: { $0.id == id }).map { $0 + 1 } ?? 1
        appModel.upsertContentSource(sourceDraft.toSource(id: id, sortOrder: order))
    }

    private func importPanoramaFiles() {
        let panel = NSOpenPanel()
        panel.title = "选择全景照片或全景视频"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedFileTypes = ["jpg", "jpeg", "png", "heic", "webp", "mp4", "mov", "m4v"]
        guard panel.runModal() == .OK else { return }
        appModel.importPanoramaFiles(urls: panel.urls)
    }

    private func importPanoramaDirectory() {
        let panel = NSOpenPanel()
        panel.title = "选择包含 360 素材的目录"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        appModel.importPanoramaDirectory(url: url)
    }

    private func chooseStateExportDirectory() {
        let panel = NSOpenPanel()
        panel.title = "选择状态数据导出目录"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        appModel.configureStateExportDirectory(url: url)
    }

    private func openStateExportDirectory() {
        guard !appModel.stateExportDirectoryPath.isEmpty else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: appModel.stateExportDirectoryPath, isDirectory: true))
    }

    private func openVideoRecordingDirectory() {
        guard !appModel.videoRecordingDirectoryPath.isEmpty else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: appModel.videoRecordingDirectoryPath, isDirectory: true))
    }
}

extension ContentView {
    @ViewBuilder
    private func calibrationRow(
        title: String,
        value: Double,
        range: ClosedRange<Double>,
        format: String,
        action: @escaping (Double) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text(String(format: format, value))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(
                value: Binding(
                    get: { value },
                    set: { action($0) }
                ),
                in: range
            )
        }
    }
}

private enum DashboardTab: String, CaseIterable, Identifiable {
    case streaming
    case sources

    var id: String { rawValue }

    var title: String {
        switch self {
        case .streaming: "全景推流"
        case .sources: "内容源管理"
        }
    }
}

private struct ContentSourceDraft {
    var name = ""
    var type: ContentSourceType = .url
    var enabled = true
    var showOnVisionPro = true
    var group = "默认"
    var icon = "globe"
    var description = ""
    var defaultVisible = false
    var url = "https://"
    var allowRefresh = true
    var requiresAuth = false
    var proxyThroughMac = false
    var username = ""
    var password = ""
    var streamUrl = "https://"
    var streamProtocol = "hls"
    var muted = true
    var width = 1280
    var height = 800
    var localFilePath = ""
    var mediaRelativePath = ""
    var mediaMimeType = ""

    init() {}

    init(source: ContentSourceItem) {
        name = source.name
        type = source.type
        enabled = source.enabled
        showOnVisionPro = source.showOnVisionPro
        group = source.group
        icon = source.icon
        description = source.description
        defaultVisible = source.defaultVisible == true
        url = source.url ?? "https://"
        allowRefresh = source.allowRefresh ?? true
        requiresAuth = source.requiresAuth ?? false
        proxyThroughMac = source.proxyThroughMac ?? false
        username = source.username ?? ""
        password = source.password ?? ""
        streamUrl = source.streamUrl ?? "https://"
        streamProtocol = source.streamProtocol ?? "hls"
        muted = source.muted ?? true
        width = source.width ?? (source.type == .video ? 960 : 1280)
        height = source.height ?? (source.type == .video ? 540 : 800)
        localFilePath = source.localFilePath ?? ""
        mediaRelativePath = source.mediaRelativePath ?? ""
        mediaMimeType = source.mediaMimeType ?? ""
    }

    func toSource(id: String, sortOrder: Int) -> ContentSourceItem {
        let timestamp = ContentSourceItem.nowISO()
        let isPanorama = type.isPanoramaScene
        return ContentSourceItem(
            id: id,
            name: name,
            type: type,
            enabled: enabled,
            showOnVisionPro: showOnVisionPro,
            sortOrder: sortOrder,
            group: group,
            icon: icon,
            description: description,
            displayMode: isPanorama ? "immersive" : "window",
            createdAt: timestamp,
            updatedAt: timestamp,
            url: type == .url ? url : nil,
            openMode: type == .url ? "embedded-webview" : nil,
            streamUrl: type == .url ? nil : streamUrl,
            streamProtocol: type == .video ? streamProtocol : (isPanorama ? "http-file" : nil),
            width: width,
            height: height,
            allowRefresh: type == .url ? allowRefresh : nil,
            requiresAuth: type == .url ? requiresAuth : nil,
            proxyThroughMac: type == .url ? proxyThroughMac : (isPanorama ? true : nil),
            defaultVisible: defaultVisible,
            username: type == .url ? (username.isEmpty ? nil : username) : nil,
            password: type == .url ? (password.isEmpty ? nil : password) : nil,
            muted: (type == .video || type == .panoramaVideo) ? muted : nil,
            lastStatus: "unknown",
            lastCheckedAt: nil,
            localFilePath: isPanorama ? (localFilePath.isEmpty ? nil : localFilePath) : nil,
            mediaRelativePath: isPanorama ? (mediaRelativePath.isEmpty ? nil : mediaRelativePath) : nil,
            mediaMimeType: isPanorama ? (mediaMimeType.isEmpty ? nil : mediaMimeType) : nil
        )
    }
}

private struct DashboardPanel<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(title, systemImage: systemImage)
                .font(.headline)
            content
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }
}

private struct StatusTile: View {
    let title: String
    let value: String
    let detail: String
    let color: Color
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(color)
            Text(value)
                .font(.headline)
                .lineLimit(3)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 132, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(color.opacity(0.08))
        )
    }
}

private struct DeviceCard: View {
    let device: SiteDeviceState

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: device.id == "auxPump" ? "drop.circle" : "gear.circle")
                .font(.system(size: 26))
                .foregroundStyle(device.isRunning ? .green : .secondary)

            VStack(alignment: .leading, spacing: 4) {
                Text(device.name)
                    .font(.headline)
                Text(device.summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(device.isRunning ? "运行中" : "待机")
                    .font(.subheadline.weight(.semibold))
                if let rpm = device.rpm {
                    Text("\(rpm, specifier: "%.2f") rpm")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
    }
}

private struct PanoramaInspectorPanel: View {
    let image: CGImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("360° 拖拽检查")
                .font(.subheadline.weight(.semibold))
            Text("按住鼠标拖动可提前检查前后接缝、比例和地平线，效果接近旧版 VRsteam3.0 的本地预览。")
                .font(.caption)
                .foregroundStyle(.secondary)
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.black.opacity(0.9))
                if let image {
                    PanoramaInspectorView(image: image)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                } else {
                    Text("等待全景画面")
                        .foregroundStyle(.white.opacity(0.75))
                }
            }
            .frame(minHeight: 320)
        }
    }
}

private struct RawFramePane: View {
    let image: CGImage?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.black.opacity(0.9))
            if let image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding(10)
            } else {
                Text("等待原始帧")
                    .foregroundStyle(.white.opacity(0.75))
            }
        }
        .frame(minHeight: 280)
    }
}

private struct DisabledSpherePanel: View {
    let message: String

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.black.opacity(0.9))
            VStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 28))
                    .foregroundStyle(.orange)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            }
            .padding(24)
        }
        .frame(minHeight: 320)
    }
}

private struct PanoramaInspectorView: NSViewRepresentable {
    let image: CGImage

    func makeNSView(context: Context) -> DraggablePanoramaSCNView {
        let view = DraggablePanoramaSCNView(frame: .zero)
        view.configure(with: image)
        return view
    }

    func updateNSView(_ nsView: DraggablePanoramaSCNView, context: Context) {
        nsView.configure(with: image)
    }
}

private final class DraggablePanoramaSCNView: SCNView {
    private let sphereNode = SCNNode()
    private let cameraNode = SCNNode()
    private let material = SCNMaterial()
    private var lastPoint: CGPoint = .zero
    private var currentImageID: UInt = 0

    override init(frame frameRect: NSRect, options: [String : Any]? = nil) {
        super.init(frame: frameRect, options: options)

        scene = SCNScene()
        backgroundColor = .black
        isPlaying = false
        rendersContinuously = false

        let sphere = SCNSphere(radius: 30)
        sphere.segmentCount = 96
        material.isDoubleSided = true
        sphere.materials = [material]

        sphereNode.geometry = sphere
        sphereNode.scale = SCNVector3(1, 1, -1)
        scene?.rootNode.addChildNode(sphereNode)

        let camera = SCNCamera()
        camera.fieldOfView = 75
        cameraNode.camera = camera
        cameraNode.position = SCNVector3(0, 0, 0)
        scene?.rootNode.addChildNode(cameraNode)
        pointOfView = cameraNode
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(with image: CGImage) {
        let imageID = UInt(bitPattern: Unmanaged.passUnretained(image).toOpaque())
        guard imageID != currentImageID else { return }
        currentImageID = imageID
        material.diffuse.contents = image
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        lastPoint = convert(event.locationInWindow, from: nil)
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let dx = point.x - lastPoint.x
        let dy = point.y - lastPoint.y
        let sensitivity: CGFloat = 0.005
        let halfPi: CGFloat = .pi / 2

        cameraNode.eulerAngles.y -= dx * sensitivity
        cameraNode.eulerAngles.x = max(-halfPi, min(halfPi, cameraNode.eulerAngles.x - dy * sensitivity))
        lastPoint = point
    }
}

#Preview {
    ContentView()
        .environment(AppModel())
}

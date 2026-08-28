import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    discoverySection
                    previewSection
                    sourceSection
                    controlSection
                    statusSection
                }
                .padding()
            }
            .navigationTitle("tsjy Vision")
        }
        .task {
            appModel.startDiscovery()
        }
        .onDisappear {
            appModel.stopDiscovery()
        }
    }

    private var discoverySection: some View {
        GroupBox("网关发现与连接") {
            VStack(alignment: .leading, spacing: 12) {
                Picker("连接模式", selection: Binding(
                    get: { appModel.connectionMode },
                    set: { appModel.connectionMode = $0 }
                )) {
                    ForEach(AppModel.ConnectionMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                if appModel.connectionMode == .automatic {
                    Picker("可用网关", selection: Binding(
                        get: { appModel.selectedGateway },
                        set: { appModel.selectedGateway = $0 }
                    )) {
                        Text("请选择").tag(Optional<DiscoveredGateway>.none)
                        ForEach(appModel.discoveredGateways) { gateway in
                            Text("\(gateway.name) (\(gateway.host))").tag(Optional(gateway))
                        }
                    }
                    .pickerStyle(.menu)
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        TextField("主机 / IP（如 192.168.1.20、relay.example.com 或 [2001:db8::10]）", text: Binding(
                            get: { appModel.manualGatewayHost },
                            set: { appModel.manualGatewayHost = $0 }
                        ))
                        .textFieldStyle(.roundedBorder)

                        TextField("视频 WebSocket 地址（可选）", text: Binding(
                            get: { appModel.manualVideoURLText },
                            set: { appModel.manualVideoURLText = $0 }
                        ))
                        .textFieldStyle(.roundedBorder)

                        TextField("控制 WebSocket 地址（可选）", text: Binding(
                            get: { appModel.manualControlURLText },
                            set: { appModel.manualControlURLText = $0 }
                        ))
                        .textFieldStyle(.roundedBorder)

                        Toggle("使用公网中继连接", isOn: Binding(
                            get: { appModel.useRelayServer },
                            set: { appModel.useRelayServer = $0 }
                        ))

                        Text("只填主机/IP 时，默认按 `ws://主机:8800` 和 `ws://主机:8801` 连接；IPv6 建议优先填域名，或输入带方括号的地址。")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Text(appModel.manualConnectionPreviewText)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)

                        Text("`172.16.x` / `192.168.x` / `10.x` 这类地址只适合同一局域网直连；跨网络时建议优先输入公网域名，若走 IPv6 请确认两端网络都已开通 IPv6。")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }

                HStack {
                    Button(appModel.connectionMode == .automatic ? "连接网关" : "手动连接") {
                        if appModel.connectionMode == .automatic {
                            appModel.connectSelectedGateway()
                        } else {
                            appModel.connectManualGateway()
                        }
                    }
                    .buttonStyle(.borderedProminent)

                    Button("断开连接") {
                        appModel.disconnect()
                    }
                }

                Text(appModel.connectionStatus)
                    .foregroundStyle(.secondary)
                Text("视频: \(appModel.videoStatus) | 控制: \(appModel.controlStatus)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var previewSection: some View {
        GroupBox("实时预览") {
            VStack(alignment: .leading, spacing: 12) {
                if let image = appModel.latestFrameImage {
                    Image(decorative: image, scale: 1.0)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity)
                        .frame(height: 220)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                } else {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(.regularMaterial)
                        .frame(height: 220)
                        .overlay(Text("等待视频帧"))
                }
                Text(appModel.latestFrameLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("比例: \(appModel.latestFrameAspectRatio, specifier: "%.3f")  |  类型: \(appModel.latestFrameType)")
                    .font(.caption)
                    .foregroundStyle(appModel.isPanoramaEligible ? .green : .orange)
                Text("当前帧龄: \(appModel.latestFrameLatencyMs) ms")
                    .font(.caption)
                    .foregroundStyle(appModel.latestFrameLatencyMs < 1000 ? .green : .orange)
                if !appModel.isPanoramaEligible {
                    Text("当前输入不是 2:1 全景候选，沉浸式球面贴图已自动禁用。")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                ToggleImmersiveSpaceButton()
            }
        }
    }

    private var controlSection: some View {
        GroupBox("远程控制") {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Button(appModel.isSessionArmed ? "已授权" : "解锁控制") {
                        appModel.armControl()
                    }
                    .buttonStyle(.borderedProminent)

                    Button("急停", role: .destructive) {
                        appModel.emergencyStop()
                    }

                    Button("恢复") {
                        appModel.releaseEmergencyStop()
                    }
                    .buttonStyle(.bordered)
                }

                HStack {
                    Button("启动辅助泵") {
                        appModel.startPump()
                    }
                    Button("停止辅助泵") {
                        appModel.stopPump()
                    }
                }

                HStack {
                    Button("前进") {
                        appModel.moveForward()
                    }
                    Button("后退") {
                        appModel.moveBackward()
                    }
                    Button("停止行走") {
                        appModel.stopTravel()
                    }
                }

                HStack {
                    Button("顺时针") {
                        appModel.rotateClockwise()
                    }
                    Button("逆时针") {
                        appModel.rotateCounterclockwise()
                    }
                    Button("停止旋转") {
                        appModel.stopRotation()
                    }
                }
            }
        }
    }

    private var sourceSection: some View {
        GroupBox("内容流") {
            VStack(alignment: .leading, spacing: 12) {
                if appModel.sources.isEmpty {
                    Text("等待网关下发可在 Vision Pro 中打开的内容源。")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(appModel.sources) { source in
                        Button {
                            openSource(source)
                        } label: {
                            HStack {
                                Image(systemName: source.type.symbolName)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(source.name)
                                    Text(source.group)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    if let cacheStatus = appModel.cacheStatusText(for: source.id), source.type.isPanoramaScene {
                                        Text(cacheStatus)
                                            .font(.caption2)
                                            .foregroundStyle(cacheStatus == "本地已缓存" ? .green : .secondary)
                                    }
                                }
                                Spacer()
                                if source.defaultVisible == true {
                                    Text("默认")
                                        .font(.caption)
                                        .foregroundStyle(.yellow)
                                }
                            }
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
        }
    }

    private var statusSection: some View {
        GroupBox("系统状态") {
            VStack(alignment: .leading, spacing: 12) {
                Text(appModel.lastServerMessage)
                    .foregroundStyle(.secondary)
                if let snapshot = appModel.latestSnapshot {
                    Text("网关: \(snapshot.gatewayName)")
                    Text("视频状态: \(snapshot.videoStatus)")
                    Text("现场状态: \(snapshot.siteStatus)")
                    Text("控制锁: \(snapshot.lockState)")
                    if let monitoring = snapshot.monitoring, !monitoring.sessionID.isEmpty {
                        Text("监测会话: \(monitoring.sessionID)")
                        Text("试次编号: \(monitoring.trialID)")
                        Text("监测汇总: 命令 \(monitoring.commandCount) / 成功 \(monitoring.commandSuccessCount)")
                    }
                    Text("最近动作: \(appModel.latestCommandActionText)")
                    Text("命令阶段: \(appModel.latestCommandPhaseText)")
                    Text("回执详情: \(appModel.latestCommandDetail)")
                    Text("命令往返: \(appModel.latestCommandRoundTripMs) ms")
                    Text("PLC 心跳: \(appModel.heartbeatPLC)")
                    Text("行走方向: \(appModel.travelDirectionText(value: appModel.travelDirectionAN1))")
                    Text("旋转方向: \(appModel.rotationDirectionText(value: appModel.rotationDirectionAN2))")
                    Text("视频监测: 收 \(appModel.receivedFrameCount) / 解 \(appModel.decodedFrameCount) / 显 \(appModel.displayedFrameCount)")
                    Text("网络缺帧: \(appModel.networkMissingFrameCount)  解码丢帧: \(appModel.decodeDroppedFrameCount)")
                    Text("延迟: 网 \(appModel.latestNetworkLatencyMs) / 解 \(appModel.latestDecodeLatencyMs) / 显 \(appModel.latestDisplayLatencyMs) / 端到端 \(appModel.latestEndToEndLatencyMs) ms")
                    ForEach(snapshot.devices) { device in
                        HStack {
                            Text(device.name)
                            Spacer()
                            Text(device.summary)
                        }
                    }
                } else {
                    Text("等待网关状态")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func openSource(_ source: ContentSourceItem) {
        Task { @MainActor in
            appModel.openSource(id: source.id)
            if appModel.pendingOpen == .web {
                openWindow(id: "webViewWindow", value: source.id)
            } else if appModel.pendingOpen == .video {
                openWindow(id: "videoWindow", value: source.id)
            } else if appModel.pendingOpen == .immersivePanorama {
                await openImmersivePanoramaIfNeeded()
            }
        }
    }

    private func openImmersivePanoramaIfNeeded() async {
        guard appModel.immersiveSpaceState == .closed else { return }
        appModel.immersiveSpaceState = .inTransition
        switch await openImmersiveSpace(id: appModel.immersiveSpaceID) {
        case .opened:
            break
        case .userCancelled, .error:
            fallthrough
        @unknown default:
            appModel.immersiveSpaceState = .closed
        }
    }
}

#Preview(windowStyle: .automatic) {
    ContentView()
        .environment(AppModel())
}

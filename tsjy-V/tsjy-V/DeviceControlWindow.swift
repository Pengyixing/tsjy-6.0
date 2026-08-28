import SwiftUI

struct DeviceControlWindow: View {
    enum LayoutMode: Equatable {
        case compact
        case expanded
    }

    static let defaultSelectedTab = "assembler"
    static let assemblerControlFlowOrder = ["summary", "locks", "pump", "motion"]
    static let expandedConsoleColumns = ["status", "controls"]

    static func layoutMode(for width: CGFloat) -> LayoutMode {
        width >= 1100 ? .expanded : .compact
    }

    @Environment(AppModel.self) private var appModel
    @State private var selectedTab = DeviceControlWindow.defaultSelectedTab

    var body: some View {
        GeometryReader { proxy in
            let layoutMode = Self.layoutMode(for: proxy.size.width)

            TabView(selection: $selectedTab) {
                assemblerTab(layoutMode: layoutMode)
                    .tabItem { Label("管片拼装", systemImage: "circle.grid.cross") }
                    .tag("assembler")

                safetyTab(layoutMode: layoutMode)
                    .tabItem { Label("安全控制", systemImage: "lock.shield") }
                    .tag("safety")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .alert(
                "控制已锁定",
                isPresented: Binding(
                    get: { appModel.shouldShowUnlockPrompt },
                    set: { newValue in
                        if !newValue {
                            appModel.cancelUnlockPrompt()
                        }
                    }
                )
            ) {
                Button("去解锁") {
                    selectedTab = "safety"
                    appModel.confirmUnlockPrompt()
                }
                Button("取消", role: .cancel) {
                    appModel.cancelUnlockPrompt()
                }
            } message: {
                Text("\(appModel.pendingUnlockActionTitle ?? "该操作")需要重新解锁控制权限，是否先前往解锁？")
            }
        }
    }

    // MARK: - Assembler Tab
    private func assemblerTab(layoutMode: LayoutMode) -> some View {
        NavigationStack {
            VStack(spacing: 18) {
                VStack(spacing: 10) {
                    Image(systemName: "cone")
                        .font(.system(size: 38))
                        .foregroundStyle(.orange)
                        .padding(.top, 24)
                    Text("管片拼装控制")
                        .font(.title.bold())
                    Text("顶部固定显示控制状态，便于一边下发动作一边查看反馈。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }

                assemblerSummaryStrip(layoutMode: layoutMode)
                    .padding(.horizontal, layoutMode == .expanded ? 24 : 32)

                Group {
                    if layoutMode == .expanded {
                        HStack(alignment: .top, spacing: 20) {
                            VStack(spacing: 20) {
                                assemblerStatusCard
                                assemblerReceiptCard
                            }
                            .frame(maxWidth: 420, alignment: .topLeading)

                            ScrollView {
                                VStack(spacing: 22) {
                                    HStack(alignment: .top, spacing: 20) {
                                        assemblerSafetyLocksCard
                                        assemblerPumpCard
                                    }

                                    assemblerMotionCard(layoutMode: layoutMode)
                                }
                                .frame(maxWidth: .infinity, alignment: .topLeading)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        }
                        .padding(.horizontal, 24)
                    } else {
                        ScrollView {
                            VStack(spacing: 22) {
                                assemblerSafetyLocksCard
                                    .padding(.horizontal, 40)
                                assemblerPumpCard
                                    .padding(.horizontal, 40)
                                assemblerMotionCard(layoutMode: layoutMode)
                                    .padding(.horizontal, 40)

                                Spacer(minLength: 20)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .navigationTitle("管片拼装")
                .navigationBarHidden(true)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    private func assemblerSummaryStrip(layoutMode: LayoutMode) -> some View {
        Group {
            if layoutMode == .expanded {
                EmptyView()
            } else {
                VStack(spacing: 16) {
                    assemblerStatusCard
                    assemblerReceiptCard
                }
            }
        }
    }

    // MARK: - Safety Tab
    private func safetyTab(layoutMode: LayoutMode) -> some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 30) {
                    Image(systemName: "shield.lefthalf.filled")
                        .font(.system(size: 60))
                        .foregroundStyle(.red)
                        .padding(.top, 40)
                    
                    Text("安全仲裁与急停")
                        .font(.largeTitle.bold())
                    
                    GroupBox {
                        VStack(alignment: .leading, spacing: 20) {
                            Label("控制权限", systemImage: "lock.shield")
                                .font(.title2.bold())
                            Text("远程下发控制指令前，必须先获取安全网关的授权令牌。")
                                .foregroundStyle(.secondary)
                            
                            Button(action: {
                                appModel.armControl()
                            }) {
                                HStack {
                                    Image(systemName: appModel.isSessionArmed ? "lock.open.fill" : "lock.fill")
                                    Text(appModel.isSessionArmed ? "已获授权 (ARMED)" : "请求解锁控制")
                                        .fontWeight(.bold)
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                            .tint(appModel.isSessionArmed ? .green : .blue)
                            .disabled(appModel.isSessionArmed)
                        }
                        .padding(20)
                    }
                    .padding(.horizontal, layoutMode == .expanded ? 24 : 40)
                    
                    GroupBox {
                        VStack(alignment: .leading, spacing: 20) {
                            Label("全局紧急停止", systemImage: "exclamationmark.octagon.fill")
                                .font(.title2.bold())
                                .foregroundStyle(.red)
                            Text("按下后将立即切断所有远程动作，并将急停信号下发至现场 PLC。")
                                .foregroundStyle(.secondary)
                            
                            Button(action: {
                                appModel.emergencyStop()
                            }) {
                                HStack {
                                    Image(systemName: "hand.raised.fill")
                                    Text("立刻急停 (E-STOP)")
                                        .font(.title2.bold())
                                }
                                .padding()
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.extraLarge)
                            .tint(.red)

                            Button(action: {
                                appModel.releaseEmergencyStop()
                            }) {
                                HStack {
                                    Image(systemName: "arrow.clockwise.circle.fill")
                                    Text("解除急停并恢复")
                                        .font(.headline.bold())
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.large)
                        }
                        .padding(20)
                    }
                    .padding(.horizontal, layoutMode == .expanded ? 24 : 40)
                }
            }
            .navigationTitle("安全控制")
            .navigationBarHidden(true)
        }
    }

    private var assemblerStatusCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Label("状态总览", systemImage: "eye.fill")
                    .font(.headline)

                HStack(spacing: 18) {
                    StatusIndicator(title: "PLC 心跳", isOn: appModel.heartbeatPLC > 0, onColor: .green)
                    StatusIndicator(title: "拼装机运行", isOn: appModel.assemblerRunning)
                    StatusIndicator(title: "真空到位", isOn: appModel.vacuumBoxReady, onColor: .green)
                    StatusIndicator(title: "真空故障", isOn: appModel.vacuumFault, onColor: .red, isFault: true)
                    StatusIndicator(title: "泵站故障", isOn: appModel.pumpFault, onColor: .red, isFault: true)
                }

                LabeledContent("行走方向", value: appModel.travelDirectionText(value: appModel.travelDirectionAN1))
                LabeledContent("旋转方向", value: appModel.rotationDirectionText(value: appModel.rotationDirectionAN2))
                LabeledContent("控制授权", value: appModel.isSessionArmed ? "已授权" : "未授权")
                LabeledContent("视频计数", value: "收 \(appModel.receivedFrameCount) / 解 \(appModel.decodedFrameCount) / 显 \(appModel.displayedFrameCount)")
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var assemblerReceiptCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Label("命令回执", systemImage: "checklist")
                    .font(.headline)
                LabeledContent("最近动作", value: appModel.latestCommandActionText)
                LabeledContent("当前阶段", value: appModel.latestCommandPhaseText)
                LabeledContent("往返时延", value: "\(appModel.latestCommandRoundTripMs) ms")
                LabeledContent("视频时延", value: "\(appModel.latestEndToEndLatencyMs) ms")
                Text(appModel.latestCommandDetail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var assemblerSafetyLocksCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 16) {
                Label("动作安全锁", systemImage: "lock.shield")
                    .font(.headline)

                Text("已授权后，先打开安全锁，再进行启动泵和动作控制。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle(isOn: Binding(
                    get: { appModel.travelEnable },
                    set: { newValue in
                        appModel.setTravelEnable(newValue)
                    }
                )) {
                    Text("旋转 / 行走允许 (TX5)")
                        .font(.title3)
                }
                .tint(.blue)

                Toggle(isOn: Binding(
                    get: { appModel.cylinderEnable },
                    set: { newValue in
                        appModel.setCylinderEnable(newValue)
                    }
                )) {
                    Text("伸缩油缸允许 (TX6)")
                        .font(.title3)
                }
                .tint(.blue)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var assemblerPumpCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 20) {
                Label("拼装机辅助泵", systemImage: "engine.combustion")
                    .font(.headline)

                HStack(spacing: 16) {
                    Button(action: {
                        appModel.startPump()
                    }) {
                        HStack {
                            Image(systemName: "play.fill")
                            Text("启动辅助泵")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)

                    Button(action: {
                        appModel.stopPump()
                    }) {
                        HStack {
                            Image(systemName: "stop.fill")
                            Text("停止辅助泵")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.gray)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func assemblerMotionCard(layoutMode: LayoutMode) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 20) {
                Label("行走与旋转控制", systemImage: "arrow.left.and.right.righttriangle.left.righttriangle.right")
                    .font(.headline)

                HStack(spacing: 16) {
                    Button(action: {
                        appModel.moveForward()
                    }) {
                        HStack {
                            Image(systemName: "arrow.up")
                            Text("前进")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)

                    Button(action: {
                        appModel.moveBackward()
                    }) {
                        HStack {
                            Image(systemName: "arrow.down")
                            Text("后退")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                }

                if layoutMode == .expanded {
                    HStack(spacing: 16) {
                        motionButton(title: "停止行走", tint: nil) { appModel.stopTravel() }
                        motionButton(title: "顺时针", tint: .purple) { appModel.rotateClockwise() }
                        motionButton(title: "逆时针", tint: .teal) { appModel.rotateCounterclockwise() }
                        motionButton(title: "停止旋转", tint: nil) { appModel.stopRotation() }
                    }
                } else {
                    HStack(spacing: 16) {
                        motionButton(title: "停止行走", tint: nil) { appModel.stopTravel() }
                        motionButton(title: "顺时针", tint: .purple) { appModel.rotateClockwise() }
                    }
                    HStack(spacing: 16) {
                        motionButton(title: "逆时针", tint: .teal) { appModel.rotateCounterclockwise() }
                        motionButton(title: "停止旋转", tint: nil) { appModel.stopRotation() }
                    }
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func motionButton(title: String, tint: Color?, action: @escaping () -> Void) -> some View {
        Group {
            if let tint {
                Button(title, action: action)
                    .frame(maxWidth: .infinity)
                    .buttonStyle(.borderedProminent)
                    .tint(tint)
            } else {
                Button(title, action: action)
                    .frame(maxWidth: .infinity)
                    .buttonStyle(.bordered)
            }
        }
    }
}

struct StatusIndicator: View {
    let title: String
    let isOn: Bool
    var onColor: Color = .blue
    var isFault: Bool = false
    
    var body: some View {
        VStack(spacing: 8) {
            Circle()
                .fill(isOn ? onColor : Color.gray.opacity(0.3))
                .frame(width: 24, height: 24)
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.2), lineWidth: 2)
                )
                .shadow(color: isOn ? onColor.opacity(0.6) : .clear, radius: 8)
            
            Text(title)
                .font(.caption)
                .foregroundStyle(isOn && isFault ? .red : .primary)
        }
    }
}

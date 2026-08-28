//
//  tsjy_VTests.swift
//  tsjy-VTests
//
//  Created by Peng Yixing on 2026/5/12.
//

import CoreFoundation
import Foundation
import Testing
@testable import tsjy_V

struct tsjy_VTests {
    @Test func deviceControlWindow_defaultsToAssemblerTab() async throws {
        #expect(DeviceControlWindow.defaultSelectedTab == "assembler")
    }

    @Test func assemblerControlFlow_placesSafetyBeforePumpAndMotion() async throws {
        #expect(DeviceControlWindow.assemblerControlFlowOrder == ["summary", "locks", "pump", "motion"])
    }

    @Test func deviceControlWindow_switchesToExpandedLayoutForWideWindow() async throws {
        #expect(DeviceControlWindow.layoutMode(for: 760) == .compact)
        #expect(DeviceControlWindow.layoutMode(for: 1180) == .expanded)
    }

    @Test func deviceControlWindow_expandedLayout_usesConsoleColumns() async throws {
        #expect(DeviceControlWindow.expandedConsoleColumns == ["status", "controls"])
    }

    @MainActor
    @Test func manualConnectionPreviewText_wrapsBareIPv6HostForRelayConsumer() async throws {
        let appModel = AppModel()
        appModel.manualGatewayHost = "2001:da8:8002:1bd1:c00a:6b69:f681:ea80"
        appModel.useRelayServer = true

        #expect(appModel.manualConnectionPreviewText.contains("ws://[2001:da8:8002:1bd1:c00a:6b69:f681:ea80]:8800/consumer"))
        #expect(appModel.manualConnectionPreviewText.contains("ws://[2001:da8:8002:1bd1:c00a:6b69:f681:ea80]:8801/consumer"))
    }

    @Test func directWebSocketSessionConfiguration_disablesSystemProxy() async throws {
        let configuration = makeDirectWebSocketSessionConfiguration()
        let proxy = configuration.connectionProxyDictionary as? [AnyHashable: Any]

        #expect(proxy?.isEmpty == true)
    }

    @MainActor
    @Test func assemblerDirectionStateText_uses新的AN枚举语义() async throws {
        let appModel = AppModel()

        #expect(appModel.travelDirectionText(value: 0) == "停止")
        #expect(appModel.travelDirectionText(value: 1) == "前进")
        #expect(appModel.travelDirectionText(value: 2) == "后退")
        #expect(appModel.rotationDirectionText(value: 0) == "停止")
        #expect(appModel.rotationDirectionText(value: 1) == "顺时针")
        #expect(appModel.rotationDirectionText(value: 2) == "逆时针")
    }

    @MainActor
    @Test func commandReceipt_advancesFromSentToExecutedToPLCFeedback() async throws {
        let appModel = AppModel()

        appModel.recordCommandSentForTesting(commandID: "cmd-1", action: "moveForward")
        #expect(appModel.latestCommandPhaseText == "命令已发送")

        appModel.applyServerMessageForTesting(
            ControlServerMessage(
                type: "commandResult",
                accepted: true,
                message: "拼装机指令已写入本地 Modbus Server",
                sessionID: "session-1",
                snapshot: nil,
                commandID: "cmd-1"
            )
        )
        #expect(appModel.latestCommandPhaseText == "Mac 已执行")

        appModel.applyServerMessageForTesting(
            ControlServerMessage(
                type: "status",
                accepted: true,
                message: "PLC 已反馈: PLC 写入本地 Modbus 寄存器: 100=9, 101=1",
                sessionID: "session-1",
                snapshot: nil,
                commandID: nil
            )
        )
        #expect(appModel.latestCommandPhaseText == "PLC 已反馈")
    }

    @MainActor
    @Test func commandReceipt_includesRoundTripLatencyAfterGatewayAck() async throws {
        let appModel = AppModel()

        appModel.recordCommandSentForTesting(commandID: "cmd-latency", action: "moveForward")
        try await Task.sleep(for: .milliseconds(20))

        appModel.applyServerMessageForTesting(
            ControlServerMessage(
                type: "commandResult",
                accepted: true,
                message: "拼装机指令已写入本地 Modbus Server",
                sessionID: "session-1",
                snapshot: nil,
                commandID: "cmd-latency"
            )
        )

        #expect(appModel.latestCommandPhaseText == "Mac 已执行")
        #expect(appModel.latestCommandDetail.contains("往返"))
        #expect(appModel.latestCommandDetail.contains("ms"))
    }

    @MainActor
    @Test func lockedControlAction_promptsUnlockConfirmation_afterEmergencyStop() async throws {
        let appModel = AppModel()

        appModel.applyServerMessageForTesting(
            ControlServerMessage(
                type: "alarm",
                accepted: true,
                message: "已触发急停",
                sessionID: "session-1",
                snapshot: GatewaySnapshot(
                    gatewayName: "tsjy",
                    gatewayStatus: "运行中",
                    videoStatus: "",
                    siteStatus: "",
                    videoPort: 8800,
                    controlPort: 8801,
                    videoClientCount: 0,
                    controlClientCount: 0,
                    lockState: "未授权",
                    devices: [],
                    contentSources: [],
                    defaultSourceIDs: []
                ),
                commandID: "stop-1"
            )
        )

        appModel.requestControlAction(.moveForward)

        #expect(appModel.shouldShowUnlockPrompt == true)
        #expect(appModel.pendingUnlockActionTitle == "前进")
    }

    @MainActor
    @Test func confirmUnlockRequest_clearsPromptAndRequestsArm() async throws {
        let appModel = AppModel()

        appModel.requestControlAction(.rotateClockwise)
        #expect(appModel.shouldShowUnlockPrompt == true)

        appModel.confirmUnlockPrompt()

        #expect(appModel.shouldShowUnlockPrompt == false)
        #expect(appModel.pendingUnlockActionTitle == nil)
        #expect(appModel.latestCommandDetail == "控制已锁定，已请求重新解锁")
    }

    @MainActor
    @Test func releaseEmergencyStop_updatesRecoveryStatusText() async throws {
        let appModel = AppModel()

        appModel.releaseEmergencyStop()

        #expect(appModel.latestCommandPhaseText == "请求解除急停")
        #expect(appModel.latestCommandDetail == "已向 Mac 发送解除急停请求")
    }

    @Test func immersiveWristMenu_staysVisibleDuringReentryGracePeriod() async throws {
        #expect(ImmersiveView.wristMenuVisibility(isUIFixed: false, isWristVisible: false, forceVisible: true) == 1.0)
        #expect(ImmersiveView.wristMenuVisibility(isUIFixed: false, isWristVisible: true, forceVisible: false) == 1.0)
        #expect(ImmersiveView.wristMenuVisibility(isUIFixed: false, isWristVisible: false, forceVisible: false) == 0.0)
        #expect(ImmersiveView.wristMenuVisibility(isUIFixed: true, isWristVisible: false, forceVisible: false) == 1.0)
    }

    @Test func wristMenuActionRail_containsEmergencyStopShortcut() async throws {
        #expect(WristMenuView.actionRailItemIDs.contains("emergencyStop"))
    }

    @Test func wristMenuActionRail_containsReleaseEmergencyShortcut() async throws {
        #expect(WristMenuView.actionRailItemIDs.contains("releaseEmergencyStop"))
    }

    @Test func wristMenuActionRail_prioritizesSafetyActions() async throws {
        #expect(WristMenuView.actionRailItemIDs == ["armControl", "emergencyStop", "releaseEmergencyStop", "controlWindow", "livePanorama"])
    }

}

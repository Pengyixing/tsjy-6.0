//
//  tsjyTests.swift
//  tsjyTests
//
//  Created by Peng Yixing on 2026/5/12.
//

import CoreMedia
import CoreVideo
import Foundation
import Network
import Testing
@testable import tsjy

private enum ModbusTestClientError: Error {
    case emptyResponse
}

private final class ResumeGate {
    private let lock = NSLock()
    private var hasResumed = false

    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !hasResumed else { return false }
        hasResumed = true
        return true
    }
}

struct tsjyTests {

    @Test func safetyManager_canReleaseEmergencyStopAndRestoreControl() async throws {
        let manager = ControlSafetyManager()
        let session = manager.register(clientID: "vision-client")
        let command = ControlClientMessage(
            type: "command",
            clientID: "vision-client",
            sessionID: session.sessionID,
            commandID: "cmd-unlock",
            deviceID: "assembler",
            action: "moveForward",
            parameters: [:],
            reason: nil,
            clientSendTimestamp: Date().timeIntervalSince1970
        )

        let armed = manager.arm(sessionID: session.sessionID)
        #expect(armed.accepted == true)

        manager.forceEmergencyStop(reason: "测试急停")
        #expect(manager.lockStateDescription == "急停中")
        #expect(manager.arm(sessionID: session.sessionID).accepted == false)

        let release = manager.releaseEmergencyStop(sessionID: session.sessionID)
        #expect(release.accepted == true)
        #expect(release.message == "已解除急停并恢复控制权限")
        #expect(manager.lockStateDescription == "已授权给 vision-client")

        let validation = manager.validateCommand(sessionID: session.sessionID, message: command)
        #expect(validation.accepted == true)
    }

    @MainActor
    @Test func videoRecording_defaultsToDedicatedFolderUnderApplicationSupport() async throws {
        let appModel = AppModel()

        #expect(appModel.videoRecordingDirectoryPath.contains("/tsjy/video-recordings"))
        #expect(FileManager.default.fileExists(atPath: appModel.videoRecordingDirectoryPath))
        #expect(appModel.videoRecordingStatus == "未录制")
    }

    @MainActor
    @Test func stateExport_defaultsToDesktopDataRecordDirectory() async throws {
        UserDefaults.standard.removeObject(forKey: "StateExportDirectoryPath")
        defer { UserDefaults.standard.removeObject(forKey: "StateExportDirectoryPath") }

        let appModel = AppModel()
        let expectedPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Desktop/数据记录", isDirectory: true)
            .path

        #expect(appModel.stateExportDirectoryPath == expectedPath)
        #expect(FileManager.default.fileExists(atPath: expectedPath))
    }

    @MainActor
    @Test func appModel_canStartAndStopVideoRecordingSession() async throws {
        let appModel = AppModel()

        appModel.startVideoRecording()
        #expect(appModel.isVideoRecording == true)
        #expect(appModel.videoRecordingStatus.contains("录制中"))
        #expect(appModel.activeVideoRecordingFilePath.contains(".mp4"))

        await appModel.stopVideoRecording()
        #expect(appModel.isVideoRecording == false)
    }

    @Test func panoramaVideoRecorder_writesMp4FileIntoRecordingDirectory() async throws {
        let outputDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        let recorder = PanoramaVideoRecorder(outputDirectory: outputDirectory)
        let armedFileURL = try recorder.startRecording(filePrefix: "integration-test")
        #expect(armedFileURL.pathExtension == "mp4")

        let firstFrame = try makeTestPixelBuffer(width: 640, height: 320, rgb: (255, 64, 32))
        let secondFrame = try makeTestPixelBuffer(width: 640, height: 320, rgb: (32, 128, 255))
        try recorder.append(pixelBuffer: firstFrame, at: .zero)
        try recorder.append(pixelBuffer: secondFrame, at: CMTime(value: 1, timescale: 30))

        let finalizedFileURL = try await recorder.stopRecording()
        let exportedFileURL = try #require(finalizedFileURL)

        #expect(exportedFileURL.pathExtension == "mp4")
        #expect(FileManager.default.fileExists(atPath: exportedFileURL.path))
        let attributes = try FileManager.default.attributesOfItem(atPath: exportedFileURL.path)
        let size = attributes[.size] as? NSNumber
        #expect((size?.intValue ?? 0) > 0)
    }

    @MainActor
    @Test func publishedVideoSocketURL_wrapsBareIPv6Host() async throws {
        let appModel = AppModel()
        let url = appModel.publishedVideoSocketURL(host: "2001:da8:8002:1bd1:c00a:6b69:f681:ea80")

        #expect(url == "ws://[2001:da8:8002:1bd1:c00a:6b69:f681:ea80]:8800")
    }

    @MainActor
    @Test func relayStatus_defaultsToUnconfigured() async throws {
        let appModel = AppModel()

        #expect(appModel.relayTargetDescription == "未配置")
        #expect(appModel.relayVideoStatus == "未配置")
        #expect(appModel.relayControlStatus == "未配置")
    }

    @MainActor
    @Test func relayStatus_marksConfiguredHostAsPending() async throws {
        let appModel = AppModel()
        appModel.relayServerHost = "120.55.70.218"
        appModel.refreshRelayStatusForConfiguration()

        #expect(appModel.relayTargetDescription == "120.55.70.218")
        #expect(appModel.relayVideoStatus == "待连接")
        #expect(appModel.relayControlStatus == "待连接")
    }

    @Test func videoQualityMode_profilesMatchExpectedPanoramaResolutions() {
        #expect(VideoQualityMode.fullHD.outputWidth == 1920)
        #expect(VideoQualityMode.fullHD.outputHeight == 960)
        #expect(VideoQualityMode.fullHD.captureWidth == 2880)
        #expect(VideoQualityMode.fullHD.captureHeight == 1440)

        #expect(VideoQualityMode.twoPointSevenK.outputWidth == 2880)
        #expect(VideoQualityMode.twoPointSevenK.outputHeight == 1440)
        #expect(VideoQualityMode.twoPointSevenK.captureWidth == 2880)
        #expect(VideoQualityMode.twoPointSevenK.captureHeight == 1440)

        #expect(VideoQualityMode.fourK.outputWidth == 3840)
        #expect(VideoQualityMode.fourK.outputHeight == 1920)
        #expect(VideoQualityMode.fourK.captureWidth == 3840)
        #expect(VideoQualityMode.fourK.captureHeight == 1920)
    }

    @Test func videoQualityMode_encoderTargetsScaleWithResolution() {
        #expect(VideoQualityMode.fullHD.targetBitrate == 10_000_000)
        #expect(VideoQualityMode.twoPointSevenK.targetBitrate == 16_000_000)
        #expect(VideoQualityMode.fourK.targetBitrate == 22_000_000)
        #expect(VideoQualityMode.fullHD.targetFPS == 30)
        #expect(VideoQualityMode.twoPointSevenK.targetFPS == 30)
        #expect(VideoQualityMode.fourK.targetFPS == 30)
    }

    @MainActor
    @Test func macDirectionTexts_matchANEnumValues() async throws {
        let appModel = AppModel()

        #expect(appModel.travelDirectionText(value: 0) == "停止")
        #expect(appModel.travelDirectionText(value: 1) == "前进")
        #expect(appModel.travelDirectionText(value: 2) == "后退")
        #expect(appModel.rotationDirectionText(value: 0) == "停止")
        #expect(appModel.rotationDirectionText(value: 1) == "顺时针")
        #expect(appModel.rotationDirectionText(value: 2) == "逆时针")
    }

    @Test func directWebSocketSessionConfiguration_disablesSystemProxy() async throws {
        let configuration = makeDirectWebSocketSessionConfiguration()
        let proxy = configuration.connectionProxyDictionary as? [AnyHashable: Any]

        #expect(proxy?.isEmpty == true)
    }

    @MainActor
    @Test func modbusWriteMultipleRegisters_updatesBridgeSnapshotImmediately() async throws {
        let bridge = SiteControlBridge()
        let port = makeUniqueTestPort(offset: 20)

        try await bridge.connect(to: "modbus://0.0.0.0:\(port)")
        try await Task.sleep(nanoseconds: 150_000_000)

        let response = try await sendModbusWriteMultipleRegisters(
            port: port,
            startAddress: 100,
            values: [9, 1, 1, 0, 0]
        )
        #expect(!response.isEmpty)

        try await Task.sleep(nanoseconds: 300_000_000)

        let snapshot = bridge.snapshot()
        let assembler = try #require(snapshot.devices.first(where: { $0.id == "assembler" }))
        let properties = try #require(assembler.properties)

        #expect(properties["heartbeatPLC"] == 9)
        #expect(properties["assemblerRunning"] == 1)
        #expect(properties["vacuumBoxReady"] == 1)
        #expect(properties["vacuumFault"] == 0)
        #expect(properties["pumpFault"] == 0)

        bridge.disconnect()
    }

    @MainActor
    @Test func macAssemblerDirectionCommands_writeANEnumRegisters() async throws {
        let bridge = SiteControlBridge()
        let port = makeUniqueTestPort(offset: 21)

        try await bridge.connect(to: "modbus://0.0.0.0:\(port)")
        _ = await bridge.execute(deviceID: "assembler", action: "moveForward", parameters: [:], commandID: "move-forward")
        _ = await bridge.execute(deviceID: "assembler", action: "rotateCounterclockwise", parameters: [:], commandID: "rotate-ccw")

        let snapshot = bridge.snapshot()
        let assembler = try #require(snapshot.devices.first(where: { $0.id == "assembler" }))
        let properties = try #require(assembler.properties)

        #expect(properties["travelDirectionAN1"] == 1)
        #expect(properties["rotationDirectionAN2"] == 2)

        bridge.disconnect()
    }

    @MainActor
    @Test func macAssemblerPumpCommands_useActiveLowStopPulse() async throws {
        let bridge = SiteControlBridge()
        let port = makeUniqueTestPort(offset: 25)

        try await bridge.connect(to: "modbus://0.0.0.0:\(port)")

        _ = await bridge.execute(deviceID: "assembler", action: "startPump", parameters: [:], commandID: "start-pump")
        var snapshot = bridge.snapshot()
        var assembler = try #require(snapshot.devices.first(where: { $0.id == "assembler" }))
        var properties = try #require(assembler.properties)

        #expect(properties["pumpStartCmd"] == 1)
        #expect(properties["pumpStopCmd"] == 1)

        _ = await bridge.execute(deviceID: "assembler", action: "stopPump", parameters: [:], commandID: "stop-pump")
        snapshot = bridge.snapshot()
        assembler = try #require(snapshot.devices.first(where: { $0.id == "assembler" }))
        properties = try #require(assembler.properties)

        #expect(properties["pumpStartCmd"] == 0)
        #expect(properties["pumpStopCmd"] == 0)

        bridge.disconnect()
    }

    @MainActor
    @Test func macAssemblerSummary_staysWaitingUntilPLCFeedbackArrives() async throws {
        let bridge = SiteControlBridge()
        let port = makeUniqueTestPort(offset: 23)

        try await bridge.connect(to: "modbus://0.0.0.0:\(port)")
        _ = await bridge.execute(deviceID: "assembler", action: "moveForward", parameters: [:], commandID: "move-forward")

        let snapshot = bridge.snapshot()
        let assembler = try #require(snapshot.devices.first(where: { $0.id == "assembler" }))

        #expect(assembler.summary == "等待PLC反馈")

        bridge.disconnect()
    }

    @MainActor
    @Test func localSimulator_rejectsMoveForwardWhenPumpIsNotRunning() async throws {
        let bridge = SiteControlBridge()
        let port = makeUniqueTestPort(offset: 26)

        try await bridge.connect(to: "modbus://0.0.0.0:\(port)")
        _ = await bridge.execute(
            deviceID: "assembler",
            action: "setParameter",
            parameters: ["travelEnable": 1],
            commandID: "enable-travel"
        )

        let result = await bridge.execute(
            deviceID: "assembler",
            action: "moveForward",
            parameters: [:],
            commandID: "move-forward-rejected"
        )
        let snapshot = bridge.snapshot()
        let assembler = try #require(snapshot.devices.first(where: { $0.id == "assembler" }))
        let properties = try #require(assembler.properties)

        #expect(result.accepted == false)
        #expect(result.simulatorAccepted == false)
        #expect(result.simulatorResultCode == 6)
        #expect(result.simulatorRejectReason == "泵未启动")
        #expect(properties["travelDirectionAN1"] != 1)

        bridge.disconnect()
    }

    @MainActor
    @Test func localSimulator_setsTravelDirectionAfterInterlocksPass() async throws {
        let bridge = SiteControlBridge()
        let port = makeUniqueTestPort(offset: 27)

        try await bridge.connect(to: "modbus://0.0.0.0:\(port)")
        let feedbackResponse = try await sendModbusWriteMultipleRegisters(
            port: port,
            startAddress: 100,
            values: [10, 1, 1, 0, 0]
        )
        #expect(!feedbackResponse.isEmpty)
        try await Task.sleep(nanoseconds: 150_000_000)

        _ = await bridge.execute(
            deviceID: "assembler",
            action: "setParameter",
            parameters: ["travelEnable": 1],
            commandID: "enable-travel"
        )
        let result = await bridge.execute(
            deviceID: "assembler",
            action: "moveForward",
            parameters: [:],
            commandID: "move-forward-success"
        )
        let snapshot = bridge.snapshot()
        let assembler = try #require(snapshot.devices.first(where: { $0.id == "assembler" }))
        let properties = try #require(assembler.properties)

        #expect(result.accepted == true)
        #expect(result.simulatorAccepted == true)
        #expect(result.simulatorResultCode == 1)
        #expect(properties["travelDirectionAN1"] == 1)

        bridge.disconnect()
    }

    @MainActor
    @Test func endToEnd_simulatedVisionToMacToPLCFeedbackRoundTrip() async throws {
        let bridge = SiteControlBridge()
        let port = makeUniqueTestPort(offset: 22)

        try await bridge.connect(to: "modbus://0.0.0.0:\(port)")
        try await Task.sleep(nanoseconds: 150_000_000)

        _ = await bridge.execute(deviceID: "assembler", action: "moveForward", parameters: [:], commandID: "cmd-1")
        _ = await bridge.execute(deviceID: "assembler", action: "rotateClockwise", parameters: [:], commandID: "cmd-2")

        let response = try await sendModbusWriteMultipleRegisters(
            port: port,
            startAddress: 100,
            values: [10, 1, 1, 0, 0]
        )
        #expect(!response.isEmpty)

        try await Task.sleep(nanoseconds: 300_000_000)

        let snapshot = bridge.snapshot()
        let assembler = try #require(snapshot.devices.first(where: { $0.id == "assembler" }))
        let properties = try #require(assembler.properties)

        #expect(properties["travelDirectionAN1"] == 1)
        #expect(properties["rotationDirectionAN2"] == 1)
        #expect(properties["heartbeatPLC"] == 10)
        #expect(properties["assemblerRunning"] == 1)
        #expect(properties["vacuumBoxReady"] == 1)
        #expect(properties["vacuumFault"] == 0)
        #expect(properties["pumpFault"] == 0)

        bridge.disconnect()
    }

    @MainActor
    @Test func modbusSequentialFeedbackWrites_refreshHeartbeatAndAllIndicators() async throws {
        let bridge = SiteControlBridge()
        let port = makeUniqueTestPort(offset: 24)

        try await bridge.connect(to: "modbus://0.0.0.0:\(port)")
        try await Task.sleep(nanoseconds: 150_000_000)

        let firstResponse = try await sendModbusWriteMultipleRegisters(
            port: port,
            startAddress: 100,
            values: [9, 1, 0, 1, 0]
        )
        #expect(!firstResponse.isEmpty)
        try await Task.sleep(nanoseconds: 150_000_000)

        let secondResponse = try await sendModbusWriteMultipleRegisters(
            port: port,
            startAddress: 100,
            values: [10, 0, 1, 0, 1]
        )
        #expect(!secondResponse.isEmpty)
        try await Task.sleep(nanoseconds: 150_000_000)

        let snapshot = bridge.snapshot()
        let assembler = try #require(snapshot.devices.first(where: { $0.id == "assembler" }))
        let properties = try #require(assembler.properties)

        #expect(properties["heartbeatPLC"] == 10)
        #expect(properties["assemblerRunning"] == 0)
        #expect(properties["vacuumBoxReady"] == 1)
        #expect(properties["vacuumFault"] == 0)
        #expect(properties["pumpFault"] == 1)
        #expect(assembler.summary == "待命")

        bridge.disconnect()
    }

    @MainActor
    @Test func processRecording_generatesSingleFileOnlyAfterStop() async throws {
        let appModel = AppModel()
        let exportDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: exportDirectory, withIntermediateDirectories: true)

        appModel.configureStateExportDirectory(url: exportDirectory)
        appModel.startNewMonitoringSession()
        appModel.monitoringConditionName = "回转作业"
        appModel.monitoringOperatorID = "测试员"
        let startTime = Date(timeIntervalSince1970: 1_717_171_717)

        appModel.startMonitoringRecordingForTesting(at: startTime)
        appModel.recordVisionOperationForTesting(
            actionName: "顺时针旋转",
            phase: "PLC 已反馈",
            detail: "AN2=1",
            commandID: "cmd-1",
            roundTripMs: 132,
            at: startTime.addingTimeInterval(2)
        )

        let filesBeforeStop = try FileManager.default.contentsOfDirectory(at: exportDirectory, includingPropertiesForKeys: nil)
        #expect(filesBeforeStop.isEmpty)

        appModel.stopMonitoringRecordingForTesting(notes: "完成一次回转作业", at: startTime.addingTimeInterval(10))

        let fileURL = try #require(appModel.activeStateExportFileURLForTesting())
        let contents = try String(contentsOf: fileURL, encoding: .utf8)
        let filesAfterStop = try FileManager.default.contentsOfDirectory(at: exportDirectory, includingPropertiesForKeys: nil)

        #expect(filesAfterStop.count == 1)
        #expect(contents.contains("记录开始"))
        #expect(contents.contains("记录结束"))
        #expect(contents.contains("顺时针旋转"))
        #expect(contents.contains("完成一次回转作业"))
    }

    @MainActor
    @Test func processRecording_collectsMultipleVisionProEventsIntoSameFile() async throws {
        let appModel = AppModel()
        let exportDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: exportDirectory, withIntermediateDirectories: true)

        appModel.configureStateExportDirectory(url: exportDirectory)
        appModel.startNewMonitoringSession()
        appModel.monitoringConditionName = "正常前进"
        appModel.monitoringActionName = "前进"
        appModel.monitoringOperatorID = "操作员A"
        let startTime = Date(timeIntervalSince1970: 1_717_171_800)

        appModel.startMonitoringRecordingForTesting(at: startTime)
        appModel.recordVisionOperationForTesting(
            actionName: "前进",
            phase: "命令已发出",
            detail: "操作员点击前进",
            commandID: "cmd-forward",
            roundTripMs: nil,
            at: startTime.addingTimeInterval(1)
        )
        appModel.recordVisionOperationForTesting(
            actionName: "前进",
            phase: "PLC 已反馈",
            detail: "行走方向 AN1=1",
            commandID: "cmd-forward",
            roundTripMs: 118,
            at: startTime.addingTimeInterval(3)
        )
        appModel.recordVideoMetricBatchForTesting(
            receivedFrameCount: 30,
            decodedFrameCount: 29,
            displayedFrameCount: 29,
            networkMissingFrameCount: 1,
            decodeDroppedFrameCount: 0,
            displayDroppedFrameCount: 0,
            latestEndToEndLatencyMs: 265,
            batchFrameCount: 6,
            at: startTime.addingTimeInterval(4)
        )
        appModel.stopMonitoringRecordingForTesting(notes: "自动采集全过程", at: startTime.addingTimeInterval(8))

        let fileURL = try #require(appModel.activeStateExportFileURLForTesting())
        let contents = try String(contentsOf: fileURL, encoding: .utf8)
        let exportedFiles = try FileManager.default.contentsOfDirectory(at: exportDirectory, includingPropertiesForKeys: nil)

        #expect(exportedFiles.count == 1)
        #expect(contents.contains("会话编号,记录编号,记录开始时间,记录结束时间,事件时间,事件类型"))
        #expect(contents.contains("命令往返时延(ms)"))
        #expect(contents.contains("视频端到端时延(ms)"))
        #expect(contents.contains("正常前进"))
        #expect(contents.contains("操作员A"))
        #expect(contents.contains("命令已发出"))
        #expect(contents.contains("PLC 已反馈"))
        #expect(contents.contains("视频指标"))
        #expect(contents.contains("自动采集全过程"))
    }

    @MainActor
    @Test func monitoringSessionReset_clearsCountersAndAdvancesSessionID() async throws {
        let appModel = AppModel()
        let originalSessionID = appModel.monitoringSessionID

        appModel.monitoringCommandCount = 3
        appModel.monitoringCommandSuccessCount = 2
        appModel.monitoringReceivedFrameCount = 12
        appModel.startNewMonitoringSession()

        #expect(appModel.monitoringSessionID != originalSessionID)
        #expect(appModel.monitoringTrialID == "trial-001")
        #expect(appModel.monitoringCommandCount == 0)
        #expect(appModel.monitoringCommandSuccessCount == 0)
        #expect(appModel.monitoringReceivedFrameCount == 0)
        #expect(appModel.monitoringSummaryText.contains("暂无已完成过程记录"))
    }

    @MainActor
    @Test func silExport_includesResearchColumnsAndCommandJudgement() async throws {
        let appModel = AppModel()
        let exportDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: exportDirectory, withIntermediateDirectories: true)

        appModel.configureStateExportDirectory(url: exportDirectory)
        appModel.startNewMonitoringSession()
        appModel.monitoringConditionName = "正常前进"
        appModel.monitoringOperatorID = "论文实验员"
        appModel.monitoringNotes = "SIL 补充试验"
        let startTime = Date(timeIntervalSince1970: 1_717_172_000)

        appModel.startMonitoringRecordingForTesting(at: startTime)
        appModel.recordCommandLifecycleForTesting(
            actionName: "前进",
            commandID: "cmd-sil-1",
            clientSendTime: startTime.addingTimeInterval(0.10),
            gatewayReceiveTime: startTime.addingTimeInterval(0.15),
            registerWriteTime: startTime.addingTimeInterval(0.21),
            simulatorReadTime: startTime.addingTimeInterval(0.24),
            feedbackWriteTime: startTime.addingTimeInterval(0.31),
            vpFeedbackRenderTime: startTime.addingTimeInterval(0.36),
            expectedFeedback: "travelActualDirection=1",
            actualFeedback: "travelActualDirection=1",
            feedbackMatched: true,
            finalResult: "SUCCESS",
            failureStage: "",
            blockLayer: "NOT_BLOCKED",
            scenarioID: "normal_forward",
            validSample: true,
            invalidReason: "",
            repeatIndex: 2,
            jogCycleID: "jog-001",
            at: startTime.addingTimeInterval(0.36)
        )
        appModel.stopMonitoringRecordingForTesting(notes: "完成 SIL 正常前进试验", at: startTime.addingTimeInterval(5))

        let fileURL = try #require(appModel.activeStateExportFileURLForTesting())
        let contents = try String(contentsOf: fileURL, encoding: .utf8)

        #expect(contents.contains("重复序号"))
        #expect(contents.contains("VisionPro发送时间"))
        #expect(contents.contains("模拟器读取时间"))
        #expect(contents.contains("预期反馈"))
        #expect(contents.contains("反馈是否匹配"))
        #expect(contents.contains("最终结果"))
        #expect(contents.contains("拦截层级"))
        #expect(contents.contains("场景编号"))
        #expect(contents.contains("点动周期ID"))
        #expect(contents.contains("SIL"))
        #expect(contents.contains("travelActualDirection=1"))
        #expect(contents.contains("SUCCESS"))
        #expect(contents.contains("normal_forward"))
    }

    @MainActor
    @Test func silExport_recordsSafetyBlockForRejectedCommand() async throws {
        let appModel = AppModel()
        let exportDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: exportDirectory, withIntermediateDirectories: true)

        appModel.configureStateExportDirectory(url: exportDirectory)
        appModel.startNewMonitoringSession()
        let startTime = Date(timeIntervalSince1970: 1_717_172_100)

        appModel.startMonitoringRecordingForTesting(at: startTime)
        appModel.recordCommandLifecycleForTesting(
            actionName: "启动拼装机泵",
            commandID: "cmd-safe-1",
            clientSendTime: startTime.addingTimeInterval(0.10),
            gatewayReceiveTime: startTime.addingTimeInterval(0.12),
            registerWriteTime: nil,
            simulatorReadTime: nil,
            feedbackWriteTime: nil,
            vpFeedbackRenderTime: startTime.addingTimeInterval(0.18),
            expectedFeedback: "pumpRunningFeedback=1",
            actualFeedback: "",
            feedbackMatched: false,
            finalResult: "REJECTED",
            failureStage: "SAFETY_INTERLOCK",
            blockLayer: "GATEWAY_SESSION",
            scenarioID: "safety_lock",
            validSample: false,
            invalidReason: "未授权会话",
            repeatIndex: 1,
            jogCycleID: "",
            at: startTime.addingTimeInterval(0.18)
        )
        appModel.stopMonitoringRecordingForTesting(notes: "安全联锁拦截", at: startTime.addingTimeInterval(3))

        let fileURL = try #require(appModel.activeStateExportFileURLForTesting())
        let contents = try String(contentsOf: fileURL, encoding: .utf8)

        #expect(contents.contains("REJECTED"))
        #expect(contents.contains("GATEWAY_SESSION"))
        #expect(contents.contains("未授权会话"))
        #expect(contents.contains("safety_lock"))
    }

    @MainActor
    @Test func silFeedbackMatching_prefersExpectedCommandInsteadOfFifoAndNormalizesModbusFeedback() async throws {
        let appModel = AppModel()
        let startTime = Date(timeIntervalSince1970: 1_717_172_200)

        appModel.startNewMonitoringSession()
        appModel.startMonitoringRecordingForTesting(at: startTime)
        appModel.queuePendingCommandLifecycleForTesting(
            action: "moveForward",
            commandID: "cmd-forward",
            clientSendTime: startTime.addingTimeInterval(0.10),
            gatewayReceiveTime: startTime.addingTimeInterval(0.12)
        )
        appModel.queuePendingCommandLifecycleForTesting(
            action: "rotateClockwise",
            commandID: "cmd-rotate",
            clientSendTime: startTime.addingTimeInterval(0.20),
            gatewayReceiveTime: startTime.addingTimeInterval(0.22)
        )

        appModel.recordPLCFeedbackForTesting(
            summary: "15=1, 100=10",
            at: startTime.addingTimeInterval(0.60)
        )

        let forwardOutcome = try #require(appModel.commandLifecycleOutcomeForTesting(commandID: "cmd-forward"))
        let rotateOutcome = try #require(appModel.commandLifecycleOutcomeForTesting(commandID: "cmd-rotate"))

        #expect(forwardOutcome.finalResult == "WAITING_FEEDBACK")
        #expect(forwardOutcome.actualFeedback.isEmpty)
        #expect(rotateOutcome.actualFeedback.contains("rotationActualDirection=1"))
        #expect(rotateOutcome.actualFeedback.contains("heartbeatPLC=10"))
        #expect(rotateOutcome.feedbackMatched == true)
        #expect(rotateOutcome.finalResult == "SUCCESS")
    }

    @MainActor
    @Test func simulatorLifecycleReport_updatesRecordedCommandFromRemoteStages() async throws {
        let appModel = AppModel()
        let exportDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: exportDirectory, withIntermediateDirectories: true)

        let startTime = Date(timeIntervalSince1970: 1_717_172_300)
        appModel.configureStateExportDirectory(url: exportDirectory)
        appModel.startNewMonitoringSession()
        appModel.startMonitoringRecordingForTesting(at: startTime)
        appModel.queuePendingCommandLifecycleForTesting(
            action: "moveForward",
            commandID: "cmd-remote-1",
            clientSendTime: startTime.addingTimeInterval(0.10),
            gatewayReceiveTime: startTime.addingTimeInterval(0.12)
        )

        appModel.applySimulatorLifecycleReportForTesting(
            commandID: "cmd-remote-1",
            simulatorReadTime: startTime.addingTimeInterval(0.20),
            logicFinishTime: startTime.addingTimeInterval(0.27),
            feedbackWriteTime: startTime.addingTimeInterval(0.31),
            feedbackValues: [
                "travelDirectionAN1": 1,
                "heartbeatPLC": 12
            ],
            detail: "Windows 模拟 PLC 已完成处理",
            at: startTime.addingTimeInterval(0.31)
        )
        appModel.stopMonitoringRecordingForTesting(notes: "远程阶段回报", at: startTime.addingTimeInterval(3))

        let outcome = try #require(appModel.commandLifecycleOutcomeForTesting(commandID: "cmd-remote-1"))
        let fileURL = try #require(appModel.activeStateExportFileURLForTesting())
        let contents = try String(contentsOf: fileURL, encoding: .utf8)

        #expect(outcome.actualFeedback.contains("travelActualDirection=1"))
        #expect(outcome.actualFeedback.contains("heartbeatPLC=12"))
        #expect(outcome.feedbackMatched == true)
        #expect(outcome.finalResult == "SUCCESS")
        #expect(contents.contains("模拟器读取时间"))
        #expect(contents.contains("反馈写入时间"))
        #expect(contents.contains("travelActualDirection=1"))
        #expect(contents.contains("Windows 模拟 PLC 已完成处理"))
    }

    @MainActor
    @Test func silExport_usesFeedbackSemanticsAndMismatchResultForUnmatchedFeedback() async throws {
        let appModel = AppModel()
        let exportDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: exportDirectory, withIntermediateDirectories: true)

        let startTime = Date(timeIntervalSince1970: 1_717_172_360)
        appModel.configureStateExportDirectory(url: exportDirectory)
        appModel.startNewMonitoringSession()
        appModel.startMonitoringRecordingForTesting(at: startTime)
        appModel.queuePendingCommandLifecycleForTesting(
            action: "stopTravel",
            commandID: "cmd-stop-travel",
            clientSendTime: startTime.addingTimeInterval(0.10),
            gatewayReceiveTime: startTime.addingTimeInterval(0.12)
        )

        appModel.applySimulatorLifecycleReportForTesting(
            commandID: "cmd-stop-travel",
            simulatorReadTime: startTime.addingTimeInterval(0.20),
            logicFinishTime: startTime.addingTimeInterval(0.24),
            feedbackWriteTime: startTime.addingTimeInterval(0.28),
            feedbackValues: [
                "travelActualDirection": 2
            ],
            detail: "方向反馈未归零",
            at: startTime.addingTimeInterval(0.30)
        )
        appModel.stopMonitoringRecordingForTesting(notes: "反馈失配", at: startTime.addingTimeInterval(3))

        let outcome = try #require(appModel.commandLifecycleOutcomeForTesting(commandID: "cmd-stop-travel"))
        let fileURL = try #require(appModel.activeStateExportFileURLForTesting())
        let contents = try String(contentsOf: fileURL, encoding: .utf8)

        #expect(outcome.actualFeedback.contains("travelActualDirection=2"))
        #expect(outcome.feedbackMatched == false)
        #expect(outcome.finalResult == "FEEDBACK_MISMATCH")
        #expect(contents.contains("反馈前状态"))
        #expect(contents.contains("反馈后状态"))
        #expect(contents.contains("控制闭环时间(ms)"))
        #expect(contents.contains("travelActualDirection=0"))
        #expect(contents.contains("travelActualDirection=2"))
        #expect(contents.contains("FEEDBACK_MISMATCH"))
    }

    @MainActor
    @Test func simulatorFeedback_waitsForTargetValueBeforeMarkingSuccess() async throws {
        let appModel = AppModel()
        let startTime = Date(timeIntervalSince1970: 1_717_172_390)

        appModel.startNewMonitoringSession()
        appModel.startMonitoringRecordingForTesting(at: startTime)
        appModel.queuePendingCommandLifecycleForTesting(
            action: "moveForward",
            commandID: "cmd-wait-target",
            clientSendTime: startTime.addingTimeInterval(0.10),
            gatewayReceiveTime: startTime.addingTimeInterval(0.12)
        )

        appModel.recordPLCFeedbackForTesting(
            summary: "heartbeatPLC=11, travelActualDirection=0",
            at: startTime.addingTimeInterval(0.30)
        )
        let waitingOutcome = try #require(appModel.commandLifecycleOutcomeForTesting(commandID: "cmd-wait-target"))
        #expect(waitingOutcome.feedbackMatched == false)
        #expect(waitingOutcome.finalResult == "WAITING_FEEDBACK")

        appModel.recordPLCFeedbackForTesting(
            summary: "heartbeatPLC=12, travelActualDirection=1",
            at: startTime.addingTimeInterval(0.65)
        )
        let successOutcome = try #require(appModel.commandLifecycleOutcomeForTesting(commandID: "cmd-wait-target"))
        #expect(successOutcome.feedbackMatched == true)
        #expect(successOutcome.actualFeedback.contains("travelActualDirection=1"))
        #expect(successOutcome.finalResult == "SUCCESS")
    }

    @MainActor
    @Test func simulatorFeedback_marksTimeoutWhenTargetValueNeverArrives() async throws {
        let appModel = AppModel()
        let startTime = Date(timeIntervalSince1970: 1_717_172_395)

        appModel.startNewMonitoringSession()
        appModel.monitoringResponseTimeoutMs = 800
        appModel.startMonitoringRecordingForTesting(at: startTime)
        appModel.queuePendingCommandLifecycleForTesting(
            action: "moveForward",
            commandID: "cmd-timeout",
            clientSendTime: startTime.addingTimeInterval(0.10),
            gatewayReceiveTime: startTime.addingTimeInterval(0.12)
        )

        appModel.recordPLCFeedbackForTesting(
            summary: "heartbeatPLC=13, travelActualDirection=0",
            at: startTime.addingTimeInterval(1.20)
        )

        let timeoutOutcome = try #require(appModel.commandLifecycleOutcomeForTesting(commandID: "cmd-timeout"))
        #expect(timeoutOutcome.feedbackMatched == false)
        #expect(timeoutOutcome.actualFeedback.contains("travelActualDirection=0"))
        #expect(timeoutOutcome.finalResult == "TIMEOUT")
    }

    @MainActor
    @Test func simulatorFeedback_marksMismatchOnlyForExplicitOppositeValue() async throws {
        let appModel = AppModel()
        let startTime = Date(timeIntervalSince1970: 1_717_172_398)

        appModel.startNewMonitoringSession()
        appModel.startMonitoringRecordingForTesting(at: startTime)
        appModel.queuePendingCommandLifecycleForTesting(
            action: "moveForward",
            commandID: "cmd-opposite",
            clientSendTime: startTime.addingTimeInterval(0.10),
            gatewayReceiveTime: startTime.addingTimeInterval(0.12)
        )

        appModel.recordPLCFeedbackForTesting(
            summary: "heartbeatPLC=14, travelActualDirection=2",
            at: startTime.addingTimeInterval(0.35)
        )

        let mismatchOutcome = try #require(appModel.commandLifecycleOutcomeForTesting(commandID: "cmd-opposite"))
        #expect(mismatchOutcome.feedbackMatched == false)
        #expect(mismatchOutcome.actualFeedback.contains("travelActualDirection=2"))
        #expect(mismatchOutcome.finalResult == "FEEDBACK_MISMATCH")
    }

    @MainActor
    @Test func stopCommand_isMarkedNoActionRequiredWhenDeviceWasAlreadyStopped() async throws {
        let appModel = AppModel()
        let exportDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: exportDirectory, withIntermediateDirectories: true)

        let startTime = Date(timeIntervalSince1970: 1_717_173_700)
        appModel.configureStateExportDirectory(url: exportDirectory)
        appModel.startNewMonitoringSession()
        appModel.startMonitoringRecordingForTesting(at: startTime)
        appModel.queuePendingCommandLifecycleForTesting(
            action: "stopTravel",
            commandID: "cmd-stop-no-action",
            clientSendTime: startTime.addingTimeInterval(0.10),
            gatewayReceiveTime: startTime.addingTimeInterval(0.12)
        )

        appModel.recordPLCFeedbackForTesting(
            summary: "travelActualDirection=0",
            at: startTime.addingTimeInterval(0.40)
        )
        appModel.stopMonitoringRecordingForTesting(notes: "停止前本来为0", at: startTime.addingTimeInterval(2))

        let outcome = try #require(appModel.commandLifecycleOutcomeForTesting(commandID: "cmd-stop-no-action"))
        let fileURL = try #require(appModel.activeStateExportFileURLForTesting())
        let rows = makeCSVRows(from: try String(contentsOf: fileURL, encoding: .utf8))
        let stopRow = try #require(firstCSVRow(commandID: "cmd-stop-no-action", eventType: "PLC 反馈", in: rows))

        #expect(outcome.finalResult == "NO_ACTION_REQUIRED")
        #expect(stopRow["有效样本"] == "否")
        #expect(stopRow["无效原因"] == "停止前设备未处于运动状态")
    }

    @MainActor
    @Test func simulatorLifecycleReport_marksRejectedInsteadOfFeedbackMismatch() async throws {
        let appModel = AppModel()
        let startTime = Date(timeIntervalSince1970: 1_717_172_405)

        appModel.startNewMonitoringSession()
        appModel.startMonitoringRecordingForTesting(at: startTime)
        appModel.queuePendingCommandLifecycleForTesting(
            action: "moveForward",
            commandID: "cmd-rejected-by-simulator",
            clientSendTime: startTime.addingTimeInterval(0.10),
            gatewayReceiveTime: startTime.addingTimeInterval(0.12)
        )

        appModel.applySimulatorLifecycleReportForTesting(
            commandID: "cmd-rejected-by-simulator",
            simulatorReadTime: startTime.addingTimeInterval(0.20),
            logicFinishTime: startTime.addingTimeInterval(0.24),
            feedbackWriteTime: startTime.addingTimeInterval(0.25),
            feedbackValues: [:],
            detail: "泵未启动，拒绝前进",
            accepted: false,
            resultCode: 2,
            rejectReason: "泵未启动",
            executedAction: "moveForward",
            at: startTime.addingTimeInterval(0.26)
        )

        let outcome = try #require(appModel.commandLifecycleOutcomeForTesting(commandID: "cmd-rejected-by-simulator"))
        #expect(outcome.feedbackMatched == false)
        #expect(outcome.finalResult == "REJECTED")
    }

    @MainActor
    @Test func monitoringExport_includesTargetFeedbackDiagnosticsAndSimulatorRejectReason() async throws {
        let appModel = AppModel()
        let exportDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: exportDirectory, withIntermediateDirectories: true)

        let startTime = Date(timeIntervalSince1970: 1_717_172_410)
        appModel.configureStateExportDirectory(url: exportDirectory)
        appModel.startNewMonitoringSession()
        appModel.startMonitoringRecordingForTesting(at: startTime)
        appModel.queuePendingCommandLifecycleForTesting(
            action: "moveForward",
            commandID: "cmd-export-diagnostics",
            clientSendTime: startTime.addingTimeInterval(0.10),
            gatewayReceiveTime: startTime.addingTimeInterval(0.12)
        )

        appModel.applySimulatorLifecycleReportForTesting(
            commandID: "cmd-export-diagnostics",
            simulatorReadTime: startTime.addingTimeInterval(0.20),
            logicFinishTime: startTime.addingTimeInterval(0.22),
            feedbackWriteTime: startTime.addingTimeInterval(0.24),
            feedbackValues: [:],
            detail: "联锁未满足",
            accepted: false,
            resultCode: 2,
            rejectReason: "泵未启动",
            executedAction: "moveForward",
            at: startTime.addingTimeInterval(0.25)
        )
        appModel.stopMonitoringRecordingForTesting(notes: "导出诊断字段", at: startTime.addingTimeInterval(2))

        let fileURL = try #require(appModel.activeStateExportFileURLForTesting())
        let contents = try String(contentsOf: fileURL, encoding: .utf8)
        let rows = makeCSVRows(from: contents)
        let rejectRow = try #require(firstCSVRow(commandID: "cmd-export-diagnostics", eventType: "模拟PLC阶段回报", in: rows))

        #expect(contents.contains("命令语义"))
        #expect(contents.contains("目标反馈名称"))
        #expect(contents.contains("目标反馈期望值"))
        #expect(contents.contains("目标反馈当前值"))
        #expect(contents.contains("反馈等待开始时间"))
        #expect(contents.contains("反馈匹配时间"))
        #expect(contents.contains("反馈超时时间"))
        #expect(contents.contains("反馈等待耗时(ms)"))
        #expect(contents.contains("模拟器结果码"))
        #expect(contents.contains("模拟器拒绝原因"))
        #expect(rejectRow["命令语义"] == "moveForward")
        #expect(rejectRow["目标反馈名称"] == "travelActualDirection")
        #expect(rejectRow["目标反馈期望值"] == "1")
        #expect(rejectRow["模拟器结果码"] == "2")
        #expect(rejectRow["模拟器拒绝原因"] == "泵未启动")
        #expect(rejectRow["最终结果"] == "REJECTED")
    }

    @MainActor
    @Test func rawRegisterFeedback_isMappedToSemanticTargetFeedbackAndSucceeds() async throws {
        let appModel = AppModel()
        let exportDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: exportDirectory, withIntermediateDirectories: true)

        let startTime = Date(timeIntervalSince1970: 1_717_173_600)
        appModel.configureStateExportDirectory(url: exportDirectory)
        appModel.startNewMonitoringSession()
        appModel.startMonitoringRecordingForTesting(at: startTime)
        appModel.queuePendingCommandLifecycleForTesting(
            action: "moveForward",
            commandID: "cmd-raw-forward",
            clientSendTime: startTime.addingTimeInterval(0.10),
            gatewayReceiveTime: startTime.addingTimeInterval(0.12)
        )

        appModel.recordPLCFeedbackForTesting(
            summary: "105=1,106=1,107=1,108=0,109=15",
            at: startTime.addingTimeInterval(0.35)
        )
        appModel.stopMonitoringRecordingForTesting(notes: "地址映射验证", at: startTime.addingTimeInterval(1.5))

        let outcome = try #require(appModel.commandLifecycleOutcomeForTesting(commandID: "cmd-raw-forward"))
        let fileURL = try #require(appModel.activeStateExportFileURLForTesting())
        let contents = try String(contentsOf: fileURL, encoding: .utf8)
        let rows = makeCSVRows(from: contents)
        let feedbackRow = try #require(firstCSVRow(commandID: "cmd-raw-forward", eventType: "PLC 反馈", in: rows))

        #expect(outcome.finalResult == "SUCCESS")
        #expect(outcome.actualFeedback.contains("travelActualDirection=1"))
        #expect(feedbackRow["目标反馈名称"] == "travelActualDirection")
        #expect(feedbackRow["目标反馈当前值"] == "1")
    }

    @MainActor
    @Test func monitoringExport_leavesStopFieldsEmptyForNonStopCommands() async throws {
        let appModel = AppModel()
        let exportDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: exportDirectory, withIntermediateDirectories: true)

        let startTime = Date(timeIntervalSince1970: 1_717_173_620)
        appModel.configureStateExportDirectory(url: exportDirectory)
        appModel.startNewMonitoringSession()
        appModel.startMonitoringRecordingForTesting(at: startTime)
        appModel.queuePendingCommandLifecycleForTesting(
            action: "moveForward",
            commandID: "cmd-no-stop-fields",
            clientSendTime: startTime.addingTimeInterval(0.10),
            gatewayReceiveTime: startTime.addingTimeInterval(0.12)
        )
        appModel.recordPLCFeedbackForTesting(
            summary: "travelActualDirection=1",
            at: startTime.addingTimeInterval(0.40)
        )
        appModel.stopMonitoringRecordingForTesting(notes: "停止字段语义", at: startTime.addingTimeInterval(2))

        let fileURL = try #require(appModel.activeStateExportFileURLForTesting())
        let rows = makeCSVRows(from: try String(contentsOf: fileURL, encoding: .utf8))
        let feedbackRow = try #require(firstCSVRow(commandID: "cmd-no-stop-fields", eventType: "PLC 反馈", in: rows))

        #expect(feedbackRow["停止响应时间(ms)"] == "")
        #expect(feedbackRow["停止成功"] == "")
    }

    @MainActor
    @Test func monitoringExport_marksVideoLatencyInvalidWhenClockSyncIsFalse() async throws {
        let appModel = AppModel()
        let exportDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: exportDirectory, withIntermediateDirectories: true)

        let startTime = Date(timeIntervalSince1970: 1_717_173_640)
        appModel.configureStateExportDirectory(url: exportDirectory)
        appModel.startNewMonitoringSession()
        appModel.startMonitoringRecordingForTesting(at: startTime)
        appModel.recordDetailedVideoMetricBatchForTesting(
            receivedFrameCount: 20,
            decodedFrameCount: 19,
            displayedFrameCount: 18,
            networkMissingFrameCount: 1,
            decodeDroppedFrameCount: 0,
            displayDroppedFrameCount: 1,
            latestEndToEndLatencyMs: 88,
            batchFrameCount: 3,
            clockOffsetMs: 0,
            clockRoundTripMs: 0,
            clockSyncValid: false,
            stallCount: 0,
            maxFrameIntervalMs: 0,
            at: startTime.addingTimeInterval(0.5)
        )
        appModel.stopMonitoringRecordingForTesting(notes: "视频无效样本", at: startTime.addingTimeInterval(2))

        let fileURL = try #require(appModel.activeStateExportFileURLForTesting())
        let rows = makeCSVRows(from: try String(contentsOf: fileURL, encoding: .utf8))
        let lastRow = try #require(rows.last)

        #expect(lastRow["视频端到端时延(ms)"] == "")
        #expect(lastRow["视频时延有效"] == "否")
        #expect(lastRow["视频时延无效原因"] == "clock_not_synchronized")
    }

    @MainActor
    @Test func monitoringExport_recordsVideoBaselineAndDeltaCounts() async throws {
        let appModel = AppModel()
        let exportDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: exportDirectory, withIntermediateDirectories: true)

        let startTime = Date(timeIntervalSince1970: 1_717_172_420)
        appModel.configureStateExportDirectory(url: exportDirectory)
        appModel.startNewMonitoringSession()
        appModel.recordVideoMetricBatchForTesting(
            receivedFrameCount: 120,
            decodedFrameCount: 115,
            displayedFrameCount: 110,
            networkMissingFrameCount: 1,
            decodeDroppedFrameCount: 2,
            displayDroppedFrameCount: 3,
            latestEndToEndLatencyMs: 88,
            batchFrameCount: 4,
            at: startTime.addingTimeInterval(-1)
        )
        appModel.startMonitoringRecordingForTesting(at: startTime)
        appModel.recordVideoMetricBatchForTesting(
            receivedFrameCount: 150,
            decodedFrameCount: 140,
            displayedFrameCount: 135,
            networkMissingFrameCount: 3,
            decodeDroppedFrameCount: 5,
            displayDroppedFrameCount: 7,
            latestEndToEndLatencyMs: 92,
            batchFrameCount: 6,
            at: startTime.addingTimeInterval(1)
        )
        appModel.stopMonitoringRecordingForTesting(notes: "视频基准验证", at: startTime.addingTimeInterval(3))

        let fileURL = try #require(appModel.activeStateExportFileURLForTesting())
        let contents = try String(contentsOf: fileURL, encoding: .utf8)
        let lastRow = try #require(makeCSVRows(from: contents).last)

        #expect(contents.contains("起始接收帧数"))
        #expect(contents.contains("结束接收帧数"))
        #expect(lastRow["起始接收帧数"] == "120")
        #expect(lastRow["起始解码帧数"] == "115")
        #expect(lastRow["起始显示帧数"] == "110")
        #expect(lastRow["结束接收帧数"] == "150")
        #expect(lastRow["结束解码帧数"] == "140")
        #expect(lastRow["结束显示帧数"] == "135")
        #expect(lastRow["接收帧数"] == "30")
        #expect(lastRow["解码帧数"] == "25")
        #expect(lastRow["显示帧数"] == "25")
        #expect(lastRow["网络缺帧数"] == "2")
        #expect(lastRow["解码丢帧数"] == "3")
        #expect(lastRow["显示丢帧数"] == "4")
    }

    @MainActor
    @Test func monitoringExport_recordsClockSyncAndStallMetrics() async throws {
        let appModel = AppModel()
        let exportDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: exportDirectory, withIntermediateDirectories: true)

        let startTime = Date(timeIntervalSince1970: 1_717_172_500)
        appModel.configureStateExportDirectory(url: exportDirectory)
        appModel.startNewMonitoringSession()
        appModel.startMonitoringRecordingForTesting(at: startTime)
        appModel.recordDetailedVideoMetricBatchForTesting(
            receivedFrameCount: 48,
            decodedFrameCount: 46,
            displayedFrameCount: 45,
            networkMissingFrameCount: 2,
            decodeDroppedFrameCount: 1,
            displayDroppedFrameCount: 1,
            latestEndToEndLatencyMs: 132,
            batchFrameCount: 8,
            clockOffsetMs: 17,
            clockRoundTripMs: 9,
            clockSyncValid: true,
            stallCount: 2,
            maxFrameIntervalMs: 366,
            at: startTime.addingTimeInterval(1)
        )
        appModel.stopMonitoringRecordingForTesting(notes: "视频同步与卡顿", at: startTime.addingTimeInterval(3))

        let fileURL = try #require(appModel.activeStateExportFileURLForTesting())
        let contents = try String(contentsOf: fileURL, encoding: .utf8)
        let lastRow = try #require(makeCSVRows(from: contents).last)

        #expect(contents.contains("时钟偏移(ms)"))
        #expect(contents.contains("时钟往返(ms)"))
        #expect(contents.contains("时钟同步有效"))
        #expect(contents.contains("卡顿次数"))
        #expect(contents.contains("最大帧间隔(ms)"))
        #expect(lastRow["时钟偏移(ms)"] == "17")
        #expect(lastRow["时钟往返(ms)"] == "9")
        #expect(lastRow["时钟同步有效"] == "是")
        #expect(lastRow["卡顿次数"] == "2")
        #expect(lastRow["最大帧间隔(ms)"] == "366")
    }

    @MainActor
    @Test func jogCycle_pairsStartAndStopCommandsIntoSingleCycle() async throws {
        let appModel = AppModel()
        let exportDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: exportDirectory, withIntermediateDirectories: true)

        let startTime = Date(timeIntervalSince1970: 1_717_172_560)
        appModel.configureStateExportDirectory(url: exportDirectory)
        appModel.startNewMonitoringSession()
        appModel.startMonitoringRecordingForTesting(at: startTime)

        appModel.queuePendingCommandLifecycleForTesting(
            action: "moveForward",
            commandID: "cmd-jog-start",
            clientSendTime: startTime.addingTimeInterval(0.10),
            gatewayReceiveTime: startTime.addingTimeInterval(0.12)
        )
        appModel.recordPLCFeedbackForTesting(
            summary: "14=1",
            at: startTime.addingTimeInterval(0.30)
        )

        appModel.queuePendingCommandLifecycleForTesting(
            action: "stopTravel",
            commandID: "cmd-jog-stop",
            clientSendTime: startTime.addingTimeInterval(0.90),
            gatewayReceiveTime: startTime.addingTimeInterval(0.92)
        )
        appModel.recordPLCFeedbackForTesting(
            summary: "14=0",
            at: startTime.addingTimeInterval(1.10)
        )
        appModel.stopMonitoringRecordingForTesting(notes: "点动配对", at: startTime.addingTimeInterval(2))

        let fileURL = try #require(appModel.activeStateExportFileURLForTesting())
        let rows = makeCSVRows(from: try String(contentsOf: fileURL, encoding: .utf8))
        let startRow = try #require(firstCSVRow(commandID: "cmd-jog-start", eventType: "PLC 反馈", in: rows))
        let stopRow = try #require(firstCSVRow(commandID: "cmd-jog-stop", eventType: "PLC 反馈", in: rows))

        #expect(startRow["点动周期ID"]?.isEmpty == false)
        #expect(startRow["点动周期ID"] == stopRow["点动周期ID"])
        #expect(stopRow["启动命令ID"] == "cmd-jog-start")
        #expect(stopRow["停止命令ID"] == "cmd-jog-stop")
        #expect(stopRow["保持时长(ms)"] == "800")
        #expect(stopRow["停止成功"] == "是")
    }

}

private func makeUniqueTestPort(offset: Int) -> UInt16 {
    let pid = Int(ProcessInfo.processInfo.processIdentifier)
    return UInt16(15_000 + ((pid + offset) % 10_000))
}

private func makeCSVRows(from contents: String) -> [[String: String]] {
    let lines = contents
        .split(separator: "\n", omittingEmptySubsequences: true)
        .map(String.init)
    guard let headerLine = lines.first else { return [] }
    let headers = headerLine.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
    return lines.dropFirst().map { line in
        let values = line.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        var row: [String: String] = [:]
        for (index, header) in headers.enumerated() {
            row[header] = index < values.count ? values[index] : ""
        }
        return row
    }
}

private func firstCSVRow(
    commandID: String,
    eventType: String,
    in rows: [[String: String]]
) -> [String: String]? {
    rows.first { row in
        row["命令ID"] == commandID && row["事件类型"] == eventType
    }
}

private func sendModbusWriteMultipleRegisters(
    port: UInt16,
    startAddress: UInt16,
    values: [UInt16]
) async throws -> Data {
    let queue = DispatchQueue(label: "tsjyTests.modbusClient")
    let connection = NWConnection(
        host: NWEndpoint.Host("127.0.0.1"),
        port: NWEndpoint.Port(rawValue: port)!,
        using: .tcp
    )

    let resumeGate = ResumeGate()
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                guard resumeGate.claim() else { return }
                continuation.resume()
            case .failed(let error):
                guard resumeGate.claim() else { return }
                continuation.resume(throwing: error)
            default:
                break
            }
        }
        connection.start(queue: queue)
    }

    let request = buildWriteMultipleRegistersFrame(
        transactionID: 1,
        unitID: 1,
        startAddress: startAddress,
        values: values
    )

    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
        connection.send(content: request, completion: .contentProcessed { error in
            if let error {
                continuation.resume(throwing: error)
            } else {
                continuation.resume()
            }
        })
    }

    let response = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
        connection.receive(minimumIncompleteLength: 1, maximumLength: 256) { content, _, _, error in
            if let error {
                continuation.resume(throwing: error)
            } else if let content {
                continuation.resume(returning: content)
            } else {
                continuation.resume(throwing: ModbusTestClientError.emptyResponse)
            }
        }
    }

    connection.cancel()
    return response
}

private func buildWriteMultipleRegistersFrame(
    transactionID: UInt16,
    unitID: UInt8,
    startAddress: UInt16,
    values: [UInt16]
) -> Data {
    let quantity = UInt16(values.count)
    let byteCount = UInt8(values.count * 2)
    let length = UInt16(7 + Int(byteCount))

    var bytes: [UInt8] = [
        UInt8(transactionID >> 8), UInt8(transactionID & 0xFF),
        0x00, 0x00,
        UInt8(length >> 8), UInt8(length & 0xFF),
        unitID,
        0x10,
        UInt8(startAddress >> 8), UInt8(startAddress & 0xFF),
        UInt8(quantity >> 8), UInt8(quantity & 0xFF),
        byteCount
    ]

    for value in values {
        bytes.append(UInt8(value >> 8))
        bytes.append(UInt8(value & 0xFF))
    }

    return Data(bytes)
}

private func makeTestPixelBuffer(
    width: Int,
    height: Int,
    rgb: (UInt8, UInt8, UInt8)
) throws -> CVPixelBuffer {
    var pixelBuffer: CVPixelBuffer?
    let status = CVPixelBufferCreate(
        kCFAllocatorDefault,
        width,
        height,
        kCVPixelFormatType_32BGRA,
        [
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ] as CFDictionary,
        &pixelBuffer
    )
    guard status == kCVReturnSuccess, let pixelBuffer else {
        struct PixelBufferError: Error {}
        throw PixelBufferError()
    }

    CVPixelBufferLockBaseAddress(pixelBuffer, [])
    defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

    let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
    guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
        struct PixelBufferError: Error {}
        throw PixelBufferError()
    }

    let buffer = baseAddress.bindMemory(to: UInt8.self, capacity: bytesPerRow * height)
    for y in 0..<height {
        let row = buffer.advanced(by: y * bytesPerRow)
        for x in 0..<width {
            let offset = x * 4
            row[offset + 0] = rgb.2
            row[offset + 1] = rgb.1
            row[offset + 2] = rgb.0
            row[offset + 3] = 255
        }
    }
    return pixelBuffer
}

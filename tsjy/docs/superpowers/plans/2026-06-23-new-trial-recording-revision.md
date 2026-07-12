# New Trial Recording Revision Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 按《新版试验记录系统进一步修改建议》修正反馈地址映射、目标反馈提取、停止字段语义和无效视频时延导出。

**Architecture:** 保持 `AppModel` 作为命令生命周期与单表导出中心，在现有结构上做最小增量修改。先用测试锁定 105–109 地址映射成功判定、非停止命令停止字段为空、未同步视频时延不写 0，再收口到统一 CSV 导出。

**Tech Stack:** Swift, Swift Testing, Observation, SwiftUI, CSV 单表导出

---

### Task 1: 修正反馈地址映射与目标反馈提取

**Files:**
- Modify: `tsjy/tsjyTests/tsjyTests.swift`
- Modify: `tsjy/tsjy/AppModel.swift`

- [ ] **Step 1: 写失败测试，验证裸地址反馈能映射为统一变量名并判定成功**

```swift
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
```

- [ ] **Step 2: 运行测试确认红灯**

Run: `xcodebuild test -project tsjy.xcodeproj -scheme tsjy -destination 'platform=macOS' -only-testing:tsjyTests/tsjyTests/rawRegisterFeedback_isMappedToSemanticTargetFeedbackAndSucceeds`
Expected: FAIL，当前 `105–109` 地址未完整映射

- [ ] **Step 3: 写最小实现**

```swift
private let modbusFeedbackAddressNames: [Int: String] = [
    105: "travelEnableFeedback",
    106: "cylinderEnableFeedback",
    107: "travelActualDirection",
    108: "rotationActualDirection",
    109: "actionCounter"
]
```

- [ ] **Step 4: 运行测试确认转绿**

Run: `xcodebuild test -project tsjy.xcodeproj -scheme tsjy -destination 'platform=macOS' -only-testing:tsjyTests/tsjyTests/rawRegisterFeedback_isMappedToSemanticTargetFeedbackAndSucceeds`
Expected: PASS

### Task 2: 修正停止字段语义

**Files:**
- Modify: `tsjy/tsjyTests/tsjyTests.swift`
- Modify: `tsjy/tsjy/AppModel.swift`

- [ ] **Step 1: 写失败测试，验证非停止命令的停止字段为空**

```swift
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
```

- [ ] **Step 2: 运行测试确认红灯**

Run: `xcodebuild test -project tsjy.xcodeproj -scheme tsjy -destination 'platform=macOS' -only-testing:tsjyTests/tsjyTests/monitoringExport_leavesStopFieldsEmptyForNonStopCommands`
Expected: FAIL，当前非停止命令可能仍会写入停止字段

- [ ] **Step 3: 写最小实现**

```swift
private func isStopAction(_ action: String) -> Bool {
    action == "stopPump" || action == "stopTravel" || action == "stopRotation"
}
```

```swift
stopResponseMsText: isStopAction(record?.action ?? "") ? record?.stopResponseMs.map(String.init) ?? "" : "",
stopSuccessfulText: isStopAction(record?.action ?? "") ? boolText(record?.stopSuccessful) : "",
```

- [ ] **Step 4: 运行测试确认转绿**

Run: `xcodebuild test -project tsjy.xcodeproj -scheme tsjy -destination 'platform=macOS' -only-testing:tsjyTests/tsjyTests/monitoringExport_leavesStopFieldsEmptyForNonStopCommands`
Expected: PASS

### Task 3: 修正未同步视频时延导出

**Files:**
- Modify: `tsjy/tsjyTests/tsjyTests.swift`
- Modify: `tsjy/tsjy/AppModel.swift`

- [ ] **Step 1: 写失败测试，验证未同步时视频时延为空且带无效原因**

```swift
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
```

- [ ] **Step 2: 运行测试确认红灯**

Run: `xcodebuild test -project tsjy.xcodeproj -scheme tsjy -destination 'platform=macOS' -only-testing:tsjyTests/tsjyTests/monitoringExport_marksVideoLatencyInvalidWhenClockSyncIsFalse`
Expected: FAIL，当前未同步时仍写入 `0` 或直接写入时延值

- [ ] **Step 3: 写最小实现**

```swift
let videoLatencyText = monitoringClockSyncValid ? String(event.endToEndLatencyMs) : ""
let videoLatencyValidText = monitoringClockSyncValid ? "是" : "否"
let videoLatencyInvalidReason = monitoringClockSyncValid ? "" : "clock_not_synchronized"
```

- [ ] **Step 4: 运行测试确认转绿**

Run: `xcodebuild test -project tsjy.xcodeproj -scheme tsjy -destination 'platform=macOS' -only-testing:tsjyTests/tsjyTests/monitoringExport_marksVideoLatencyInvalidWhenClockSyncIsFalse`
Expected: PASS

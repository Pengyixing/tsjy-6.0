# Simulator PLC Feedback Logic Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 按“模拟PLC反馈判定逻辑修改建议”把 Mac 端命令反馈判定改成等待目标反馈、区分超时与失配，并把结果稳定写入单张中文试验表。

**Architecture:** 保持现有 `AppModel` 为命令生命周期中心，不引入新子系统。先在测试中锁定 `WAITING_FEEDBACK`、`TIMEOUT`、目标反馈精确匹配和 `setParameter` 语义展开，再最小化扩展 `CommandLifecycleRecord` 与 PLC 反馈处理路径。

**Tech Stack:** Swift, Swift Testing, SwiftUI Observation, CSV 单表导出

---

### Task 1: 锁定反馈等待与超时语义

**Files:**
- Modify: `tsjy/tsjyTests/tsjyTests.swift`
- Modify: `tsjy/tsjy/AppModel.swift`

- [ ] **Step 1: 写失败测试，验证首次旧反馈不能直接判失败**

```swift
@MainActor
@Test func plcFeedback_keepsWaitingWhenTargetValueHasNotArrivedYet() async throws {
    let appModel = AppModel()
    let startTime = Date(timeIntervalSince1970: 1_717_173_000)

    appModel.startNewMonitoringSession()
    appModel.startMonitoringRecordingForTesting(at: startTime)
    appModel.queuePendingCommandLifecycleForTesting(
        action: "moveForward",
        commandID: "cmd-waiting",
        clientSendTime: startTime.addingTimeInterval(0.10),
        gatewayReceiveTime: startTime.addingTimeInterval(0.12)
    )
    appModel.recordPLCFeedbackForTesting(
        summary: "travelActualDirection=0, heartbeatPLC=100",
        at: startTime.addingTimeInterval(0.30)
    )

    let outcome = try #require(appModel.commandLifecycleOutcomeForTesting(commandID: "cmd-waiting"))
    #expect(outcome.finalResult == "WAITING_FEEDBACK")
    #expect(outcome.feedbackMatched == false)
}
```

- [ ] **Step 2: 运行单测确认红灯**

Run: `xcodebuild test -project tsjy.xcodeproj -scheme tsjy -destination 'platform=macOS' -only-testing:tsjyTests/tsjyTests/plcFeedback_keepsWaitingWhenTargetValueHasNotArrivedYet`
Expected: FAIL，当前实现会把旧值直接判成 `FEEDBACK_MISMATCH`

- [ ] **Step 3: 写最小实现**

```swift
if targetValue == expectedValue {
    record.finalResult = "SUCCESS"
} else if explicitMismatch {
    record.finalResult = "FEEDBACK_MISMATCH"
} else {
    record.finalResult = "WAITING_FEEDBACK"
}
```

- [ ] **Step 4: 运行单测确认转绿**

Run: `xcodebuild test -project tsjy.xcodeproj -scheme tsjy -destination 'platform=macOS' -only-testing:tsjyTests/tsjyTests/plcFeedback_keepsWaitingWhenTargetValueHasNotArrivedYet`
Expected: PASS

- [ ] **Step 5: 提交**

```bash
git add tsjy/tsjyTests/tsjyTests.swift tsjy/tsjy/AppModel.swift
git commit -m "feat: wait for simulator plc target feedback"
```

### Task 2: 锁定目标反馈精确比较与 setParameter 展开

**Files:**
- Modify: `tsjy/tsjyTests/tsjyTests.swift`
- Modify: `tsjy/tsjy/AppModel.swift`

- [ ] **Step 1: 写失败测试，验证心跳变化不应触发成功判定**

```swift
@MainActor
@Test func plcFeedback_ignoresHeartbeatChangesWhenTargetFeedbackIsUnchanged() async throws {
    let appModel = AppModel()
    let startTime = Date(timeIntervalSince1970: 1_717_173_100)

    appModel.startNewMonitoringSession()
    appModel.startMonitoringRecordingForTesting(at: startTime)
    appModel.queuePendingCommandLifecycleForTesting(
        action: "moveForward",
        commandID: "cmd-heartbeat-only",
        clientSendTime: startTime.addingTimeInterval(0.10),
        gatewayReceiveTime: startTime.addingTimeInterval(0.12)
    )
    appModel.recordPLCFeedbackForTesting(
        summary: "heartbeatPLC=101, actionCounter=7, travelActualDirection=0",
        at: startTime.addingTimeInterval(0.40)
    )

    let outcome = try #require(appModel.commandLifecycleOutcomeForTesting(commandID: "cmd-heartbeat-only"))
    #expect(outcome.finalResult == "WAITING_FEEDBACK")
}
```

- [ ] **Step 2: 写失败测试，验证 `setParameter` 会展开到具体反馈**

```swift
@MainActor
@Test func setParameter_expandsToConcreteExpectedFeedback() async throws {
    let appModel = AppModel()
    let startTime = Date(timeIntervalSince1970: 1_717_173_120)

    appModel.startNewMonitoringSession()
    appModel.startMonitoringRecordingForTesting(at: startTime)
    appModel.recordCommandLifecycleForTesting(
        actionName: "setParameter",
        commandID: "cmd-enable-travel",
        clientSendTime: startTime.addingTimeInterval(0.10),
        gatewayReceiveTime: startTime.addingTimeInterval(0.12),
        registerWriteTime: startTime.addingTimeInterval(0.16),
        simulatorReadTime: nil,
        feedbackWriteTime: nil,
        vpFeedbackRenderTime: nil,
        expectedFeedback: "travelEnableFeedback=1",
        actualFeedback: "",
        feedbackMatched: false,
        finalResult: "WAITING_FEEDBACK",
        failureStage: "",
        blockLayer: "NOT_BLOCKED",
        scenarioID: "enable_travel",
        validSample: true,
        invalidReason: "",
        repeatIndex: 1,
        jogCycleID: "",
        at: startTime.addingTimeInterval(0.16)
    )
}
```

- [ ] **Step 3: 运行这两条测试确认红灯**

Run: `xcodebuild test -project tsjy.xcodeproj -scheme tsjy -destination 'platform=macOS' -only-testing:tsjyTests/tsjyTests/plcFeedback_ignoresHeartbeatChangesWhenTargetFeedbackIsUnchanged -only-testing:tsjyTests/tsjyTests/setParameter_expandsToConcreteExpectedFeedback`
Expected: FAIL，当前逻辑仍按整帧字符串判断

- [ ] **Step 4: 写最小实现**

```swift
struct FeedbackExpectation {
    var name: String
    var expectedValue: Int?
}
```

```swift
switch action {
case "setParameter" where parameters["travelEnable"] == 1:
    return "travelEnableFeedback=1"
default:
    ...
}
```

- [ ] **Step 5: 运行测试确认转绿**

Run: `xcodebuild test -project tsjy.xcodeproj -scheme tsjy -destination 'platform=macOS' -only-testing:tsjyTests/tsjyTests/plcFeedback_ignoresHeartbeatChangesWhenTargetFeedbackIsUnchanged -only-testing:tsjyTests/tsjyTests/setParameter_expandsToConcreteExpectedFeedback`
Expected: PASS

### Task 3: 锁定超时结果和单表导出

**Files:**
- Modify: `tsjy/tsjyTests/tsjyTests.swift`
- Modify: `tsjy/tsjy/AppModel.swift`

- [ ] **Step 1: 写失败测试，验证等待超过阈值判 TIMEOUT**

```swift
@MainActor
@Test func plcFeedback_marksTimeoutAfterConfiguredDeadline() async throws {
    let appModel = AppModel()
    let startTime = Date(timeIntervalSince1970: 1_717_173_200)

    appModel.startNewMonitoringSession()
    appModel.startMonitoringRecordingForTesting(at: startTime)
    appModel.queuePendingCommandLifecycleForTesting(
        action: "moveForward",
        commandID: "cmd-timeout",
        clientSendTime: startTime.addingTimeInterval(0.10),
        gatewayReceiveTime: startTime.addingTimeInterval(0.12)
    )
    appModel.recordPLCFeedbackForTesting(
        summary: "travelActualDirection=0",
        at: startTime.addingTimeInterval(4.00)
    )

    let outcome = try #require(appModel.commandLifecycleOutcomeForTesting(commandID: "cmd-timeout"))
    #expect(outcome.finalResult == "TIMEOUT")
}
```

- [ ] **Step 2: 运行测试确认红灯**

Run: `xcodebuild test -project tsjy.xcodeproj -scheme tsjy -destination 'platform=macOS' -only-testing:tsjyTests/tsjyTests/plcFeedback_marksTimeoutAfterConfiguredDeadline`
Expected: FAIL，当前实现不会产出 `TIMEOUT`

- [ ] **Step 3: 写最小实现**

```swift
if elapsedMs > record.responseTimeoutMs {
    record.finalResult = "TIMEOUT"
    record.failureStage = "FEEDBACK_TIMEOUT"
}
```

- [ ] **Step 4: 补导出断言并跑测试**

Run: `xcodebuild test -project tsjy.xcodeproj -scheme tsjy -destination 'platform=macOS' -only-testing:tsjyTests/tsjyTests/plcFeedback_marksTimeoutAfterConfiguredDeadline`
Expected: PASS，并且 CSV 行包含 `TIMEOUT`

- [ ] **Step 5: 提交**

```bash
git add tsjy/tsjyTests/tsjyTests.swift tsjy/tsjy/AppModel.swift
git commit -m "feat: record simulator plc timeout results"
```

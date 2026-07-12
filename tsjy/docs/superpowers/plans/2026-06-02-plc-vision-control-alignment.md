# PLC Vision Control Alignment Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 修复 PLC 回写在 Mac 不显示的问题，并把 Mac 与 Vision Pro 的 6 路控制指令统一调整为新的拼装机点表语义。

**Architecture:** 保持现有 `Vision Pro -> Mac WebSocket -> SiteControlBridge -> Modbus TCP Server -> PLC` 主链路不变，重点修复两件事：第一，给 Modbus 底层增加可见的诊断与写回验证，明确 PLC 是否真的向 Mac 写入反馈区；第二，把 `40011~40016` 的控制语义收敛为同一份点表定义，由 Mac 和 Vision Pro 共用。`40015/40016` 采用 `0/1/2` 枚举，分别对应 `AN1/AN2` 的方向语义。

**Tech Stack:** SwiftUI, Foundation, Network.framework, Swift Testing/XCTest, Xcode `tsjy` + `tsjy-V`

---

### Task 1: 固化点表与控制语义

**Files:**
- Modify: `清单/TSJY-0_Modbus_Register_Map.md`
- Modify: `TSJY-0/tsjy/tsjy/SiteControlBridge.swift`
- Modify: `TSJY-0/tsjy/tsjy/ContentView.swift`
- Modify: `TSJY-0/tsjy-V/tsjy-V/ControlClient.swift`
- Modify: `TSJY-0/tsjy-V/tsjy-V/DeviceControlWindow.swift`
- Test: `TSJY-0/tsjy/tsjyTests/SiteConnectionConfigTests.swift`

- [ ] **Step 1: 写失败测试，先固定新的控制点语义**

```swift
import Testing
@testable import tsjy

struct SiteConnectionConfigTests {
    @Test func controlRegisterMap_matchesAssemblerSignalBook() async throws {
        let bridge = await MainActor.run { SiteControlBridge() }
        let map = await MainActor.run { bridge.debugControlRegisterMap() }

        #expect(map["pumpStartCmd"] == 10)
        #expect(map["pumpStopCmd"] == 11)
        #expect(map["travelEnable"] == 12)
        #expect(map["cylinderEnable"] == 13)
        #expect(map["travelDirectionAN1"] == 14)
        #expect(map["rotationDirectionAN2"] == 15)
    }
}
```

- [ ] **Step 2: 运行测试，确认当前代码还保留旧的吸取/释放语义**

Run: `xcodebuild test -project tsjy.xcodeproj -scheme tsjy -destination 'platform=macOS' -only-testing:tsjyTests/SiteConnectionConfigTests`
Expected: FAIL with missing `debugControlRegisterMap()` or mismatched register names.

- [ ] **Step 3: 修改点表文档，明确最终控制语义**

```md
| 控制方向 | 保持寄存器地址 | 40001风格地址 | 变量名 | 数据类型 | 说明 |
|---|---:|---:|---|---|---|
| Mac -> PLC | 10 | 40011 | pumpStartCmd | UInt16 | 启动拼装机泵，0=无动作，1=触发 |
| Mac -> PLC | 11 | 40012 | pumpStopCmd | UInt16 | 停止拼装机泵，0=无动作，1=触发 |
| Mac -> PLC | 12 | 40013 | travelEnable | UInt16 | 旋转/行走允许，0=禁止，1=允许 |
| Mac -> PLC | 13 | 40014 | cylinderEnable | UInt16 | 伸缩油缸允许，0=禁止，1=允许 |
| Mac -> PLC | 14 | 40015 | travelDirectionAN1 | UInt16 | AN1 枚举，0=停止，1=前进，2=后退 |
| Mac -> PLC | 15 | 40016 | rotationDirectionAN2 | UInt16 | AN2 枚举，0=停止，1=顺时针，2=逆时针 |
```

- [ ] **Step 4: 在 `SiteControlBridge` 中统一地址表，并提供测试用调试映射**

```swift
private let addressMap: [String: UInt16] = [
    "pumpStartCmd": 10,
    "pumpStopCmd": 11,
    "travelEnable": 12,
    "cylinderEnable": 13,
    "travelDirectionAN1": 14,
    "rotationDirectionAN2": 15
]

func debugControlRegisterMap() -> [String: UInt16] {
    addressMap
}
```

- [ ] **Step 5: 同步更新 Mac 端按钮文案和 Vision Pro 端按钮文案**

```swift
// Mac
Button("前进") { appModel.executeLocalSiteCommand(deviceID: "assembler", action: "moveForward") }
Button("后退") { appModel.executeLocalSiteCommand(deviceID: "assembler", action: "moveBackward") }
Button("顺时针") { appModel.executeLocalSiteCommand(deviceID: "assembler", action: "rotateClockwise") }
Button("逆时针") { appModel.executeLocalSiteCommand(deviceID: "assembler", action: "rotateCounterclockwise") }

// Vision Pro
try await controlClient.sendCommand(deviceID: "assembler", action: "moveForward", parameters: [:])
try await controlClient.sendCommand(deviceID: "assembler", action: "rotateClockwise", parameters: [:])
```

- [ ] **Step 6: 重新运行测试，确认点表语义已锁定**

Run: `xcodebuild test -project tsjy.xcodeproj -scheme tsjy -destination 'platform=macOS' -only-testing:tsjyTests/SiteConnectionConfigTests`
Expected: PASS

- [ ] **Step 7: 提交点表语义调整**

```bash
git add ../清单/TSJY-0_Modbus_Register_Map.md tsjy/SiteControlBridge.swift tsjy/ContentView.swift ../tsjy-V/tsjy-V/ControlClient.swift ../tsjy-V/tsjy-V/DeviceControlWindow.swift tsjyTests/SiteConnectionConfigTests.swift
git commit -m "feat: align assembler control register map"
```

### Task 2: 修复 PLC 回写不显示，并把底层诊断打到 Mac UI

**Files:**
- Modify: `TSJY-0/tsjy/tsjy/ModbusTCPServer.swift`
- Modify: `TSJY-0/tsjy/tsjy/SiteControlBridge.swift`
- Modify: `TSJY-0/tsjy/tsjy/AppModel.swift`
- Modify: `TSJY-0/tsjy/tsjy/ContentView.swift`
- Test: `TSJY-0/tsjy/tsjyTests/ModbusTCPServerTests.swift`
- Test: `TSJY-0/tsjy/tsjyTests/tsjyTests.swift`

- [ ] **Step 1: 写失败测试，先证明 PLC 批量写反馈区后，Mac 快照必须立即更新**

```swift
@MainActor
@Test func modbusWriteMultipleRegisters_updatesBridgeSnapshotImmediately() async throws {
    let bridge = SiteControlBridge()
    let port: UInt16 = 15020

    try await bridge.connect(to: "modbus://0.0.0.0:\(port)")
    let _ = try await sendModbusWriteMultipleRegisters(
        port: port,
        startAddress: 100,
        values: [9, 1, 1, 0, 0]
    )

    try await Task.sleep(nanoseconds: 300_000_000)

    let snapshot = bridge.snapshot()
    let assembler = try #require(snapshot.devices.first(where: { $0.id == "assembler" }))
    let properties = try #require(assembler.properties)
    #expect(properties["heartbeatPLC"] == 9)
    #expect(properties["assemblerRunning"] == 1)
}
```

- [ ] **Step 2: 写失败测试，要求底层诊断日志进入可观察回调**

```swift
func testWriteSingleRegister_EmitsDiagnosticLog() {
    var messages: [String] = []
    server.onDiagnosticLog = { messages.append($0) }

    let requestBytes: [UInt8] = [
        0x00, 0x02, 0x00, 0x00, 0x00, 0x06, 0x01,
        0x06, 0x00, 0x02, 0x00, 0x58
    ]

    _ = server.handleModbusRequest(data: Data(requestBytes))

    XCTAssertTrue(messages.contains(where: { $0.contains("FC6") && $0.contains("2=88") }))
}
```

- [ ] **Step 3: 运行测试，确认当前诊断链路或即时刷新链路缺失时会失败**

Run: `xcodebuild test -project tsjy.xcodeproj -scheme tsjy -destination 'platform=macOS' -parallel-testing-enabled NO -only-testing:tsjyTests/ModbusTCPServerTests -only-testing:tsjyTests/tsjyTests/modbusWriteMultipleRegisters_updatesBridgeSnapshotImmediately`
Expected: FAIL before implementation is complete.

- [ ] **Step 4: 给 `ModbusTCPServer` 增加分层诊断和寄存器写入回调**

```swift
var onDiagnosticLog: ((String) -> Void)?
var onRegistersWritten: (([(address: Int, value: UInt16)]) -> Void)?

private func emitDiagnosticLog(_ message: String) {
    print(message)
    onDiagnosticLog?(message)
}

private func notifyRemoteRegisterWrites(_ writes: [(address: Int, value: UInt16)], functionCode: UInt8) {
    guard !writes.isEmpty else { return }
    let summary = writes.map { "\($0.address)=\($0.value)" }.joined(separator: ", ")
    emitDiagnosticLog("ModbusTCPServer remote write FC\(functionCode): \(summary)")
    onRegistersWritten?(writes)
}
```

- [ ] **Step 5: 在 `SiteControlBridge` 中把底层诊断转发到运行日志，并在 PLC 写入反馈区时立即刷新设备快照**

```swift
server.onDiagnosticLog = { [weak self] message in
    Task { @MainActor in
        self?.onLog?(message)
    }
}

server.onRegistersWritten = { [weak self] writes in
    Task { @MainActor in
        self?.handleModbusRegistersWritten(writes)
    }
}

private func handleModbusRegistersWritten(_ writes: [(address: Int, value: UInt16)]) {
    let summary = writes.map { "\($0.address)=\($0.value)" }.joined(separator: ", ")
    onLog?("PLC 写入本地 Modbus 寄存器: \(summary)")
    guard let modbusServer else { return }
    refreshModbusFeedback(from: modbusServer)
    onStateChanged?(currentState)
}
```

- [ ] **Step 6: 确认 Mac 日志面板能看到 Modbus 底层链路**

```swift
DashboardPanel(title: "运行日志", systemImage: "terminal") {
    ScrollView {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(appModel.logEntries.prefix(80)) { entry in
                Text("[\(entry.timestamp)] \(entry.message)")
                    .font(.caption.monospaced())
            }
        }
    }
}
```

- [ ] **Step 7: 重新运行测试，确认回写即时刷新和诊断链路都通过**

Run: `xcodebuild test -project tsjy.xcodeproj -scheme tsjy -destination 'platform=macOS' -parallel-testing-enabled NO -only-testing:tsjyTests/ModbusTCPServerTests -only-testing:tsjyTests/tsjyTests/modbusWriteMultipleRegisters_updatesBridgeSnapshotImmediately`
Expected: PASS

- [ ] **Step 8: 提交 PLC 回写修复**

```bash
git add tsjy/ModbusTCPServer.swift tsjy/SiteControlBridge.swift tsjy/AppModel.swift tsjy/ContentView.swift tsjyTests/ModbusTCPServerTests.swift tsjyTests/tsjyTests.swift
git commit -m "fix: surface plc feedback diagnostics"
```

### Task 3: 在 Mac 端实现新的 6 路控制下发

**Files:**
- Modify: `TSJY-0/tsjy/tsjy/SiteControlBridge.swift`
- Modify: `TSJY-0/tsjy/tsjy/AppModel.swift`
- Modify: `TSJY-0/tsjy/tsjy/ContentView.swift`
- Test: `TSJY-0/tsjy/tsjyTests/tsjyTests.swift`

- [ ] **Step 1: 写失败测试，要求新动作能映射到 `40015/40016` 的枚举值**

```swift
@MainActor
@Test func macAssemblerDirectionCommands_writeANEnumRegisters() async throws {
    let bridge = SiteControlBridge()
    try await bridge.connect(to: "modbus://0.0.0.0:15021")

    _ = await bridge.execute(deviceID: "assembler", action: "moveForward", parameters: [:], commandID: "1")
    let snapshot = bridge.snapshot()
    let assembler = try #require(snapshot.devices.first(where: { $0.id == "assembler" }))
    let properties = try #require(assembler.properties)

    #expect(properties["travelDirectionAN1"] == 1)
}
```

- [ ] **Step 2: 运行测试，确认旧动作名无法满足新语义**

Run: `xcodebuild test -project tsjy.xcodeproj -scheme tsjy -destination 'platform=macOS' -parallel-testing-enabled NO -only-testing:tsjyTests/tsjyTests/macAssemblerDirectionCommands_writeANEnumRegisters`
Expected: FAIL because `moveForward` and AN enum properties are not implemented.

- [ ] **Step 3: 在 `SiteControlBridge.execute()` 中实现新的 6 路动作**

```swift
if action == "moveForward" {
    modbusServer.setRegister(address: Int(addressMap["travelDirectionAN1"]!), value: 1)
    onLog?("已下发前进指令(AN1=1)")
} else if action == "moveBackward" {
    modbusServer.setRegister(address: Int(addressMap["travelDirectionAN1"]!), value: 2)
    onLog?("已下发后退指令(AN1=2)")
} else if action == "stopTravel" {
    modbusServer.setRegister(address: Int(addressMap["travelDirectionAN1"]!), value: 0)
} else if action == "rotateClockwise" {
    modbusServer.setRegister(address: Int(addressMap["rotationDirectionAN2"]!), value: 1)
    onLog?("已下发顺时针旋转指令(AN2=1)")
} else if action == "rotateCounterclockwise" {
    modbusServer.setRegister(address: Int(addressMap["rotationDirectionAN2"]!), value: 2)
    onLog?("已下发逆时针旋转指令(AN2=2)")
} else if action == "stopRotation" {
    modbusServer.setRegister(address: Int(addressMap["rotationDirectionAN2"]!), value: 0)
}
```

- [ ] **Step 4: 把新控制值写回到 Mac 本地快照，便于调试和回显**

```swift
newProps["travelDirectionAN1"] = Double(modbusServer.getRegister(address: 14))
newProps["rotationDirectionAN2"] = Double(modbusServer.getRegister(address: 15))
```

- [ ] **Step 5: 在 Mac 界面替换旧的吸取/释放控制区**

```swift
Button("前进") { appModel.executeLocalSiteCommand(deviceID: "assembler", action: "moveForward") }
Button("后退") { appModel.executeLocalSiteCommand(deviceID: "assembler", action: "moveBackward") }
Button("停止行走") { appModel.executeLocalSiteCommand(deviceID: "assembler", action: "stopTravel") }
Button("顺时针") { appModel.executeLocalSiteCommand(deviceID: "assembler", action: "rotateClockwise") }
Button("逆时针") { appModel.executeLocalSiteCommand(deviceID: "assembler", action: "rotateCounterclockwise") }
Button("停止旋转") { appModel.executeLocalSiteCommand(deviceID: "assembler", action: "stopRotation") }
```

- [ ] **Step 6: 运行测试，确认新动作写入正确的寄存器值**

Run: `xcodebuild test -project tsjy.xcodeproj -scheme tsjy -destination 'platform=macOS' -parallel-testing-enabled NO -only-testing:tsjyTests/tsjyTests/macAssemblerDirectionCommands_writeANEnumRegisters`
Expected: PASS

- [ ] **Step 7: 提交 Mac 控制动作更新**

```bash
git add tsjy/SiteControlBridge.swift tsjy/AppModel.swift tsjy/ContentView.swift tsjyTests/tsjyTests.swift
git commit -m "feat: update mac assembler control actions"
```

### Task 4: 在 Vision Pro 上对齐新的控制指令，并显示 PLC 状态反馈

**Files:**
- Modify: `TSJY-0/tsjy-V/tsjy-V/ControlClient.swift`
- Modify: `TSJY-0/tsjy-V/tsjy-V/AppModel.swift`
- Modify: `TSJY-0/tsjy-V/tsjy-V/DeviceControlWindow.swift`
- Modify: `TSJY-0/tsjy-V/tsjy-V/ContentView.swift`
- Test: `TSJY-0/tsjy-V/tsjy-VTests/tsjy_VTests.swift`

- [ ] **Step 1: 写失败测试，先锁定 Vision Pro 动作名与状态映射**

```swift
import Testing
@testable import tsjy_V

struct tsjy_VTests {
    @MainActor
    @Test func assemblerSnapshot_mapsDirectionEnumsToVisionState() async throws {
        let appModel = AppModel()
        let snapshot = GatewaySnapshot(
            gatewayName: "tsjy",
            gatewayStatus: "已启动",
            siteStatus: "ready",
            videoStatus: "ok",
            lockState: "已解锁",
            videoPort: 8800,
            controlPort: 8801,
            videoClientCount: 0,
            controlClientCount: 0,
            devices: [
                SiteDeviceState(
                    id: "assembler",
                    name: "管片拼装机",
                    summary: "运行中",
                    isRunning: true,
                    rpm: nil,
                    minRPM: nil,
                    maxRPM: nil,
                    properties: [
                        "heartbeatPLC": 9,
                        "assemblerRunning": 1,
                        "vacuumBoxReady": 1,
                        "vacuumFault": 0,
                        "pumpFault": 0,
                        "travelDirectionAN1": 2,
                        "rotationDirectionAN2": 1
                    ]
                )
            ],
            contentSources: [],
            defaultSourceIDs: []
        )

        appModel.apply(snapshot: snapshot)
        #expect(appModel.assemblerTravelDirectionText == "后退")
        #expect(appModel.assemblerRotationDirectionText == "顺时针")
    }
}
```

- [ ] **Step 2: 运行测试，确认 Vision 端还没有新状态文本与新动作接口**

Run: `xcodebuild test -project tsjy-V/tsjy-V.xcodeproj -scheme tsjy-V -destination 'platform=visionOS Simulator,name=Apple Vision Pro' -only-testing:tsjy_VTests`
Expected: FAIL with missing state mapping helpers.

- [ ] **Step 3: 在 `ControlClient` 中新增新的动作封装**

```swift
func moveForward() async throws {
    try await sendCommand(deviceID: "assembler", action: "moveForward", parameters: [:])
}

func moveBackward() async throws {
    try await sendCommand(deviceID: "assembler", action: "moveBackward", parameters: [:])
}

func stopTravel() async throws {
    try await sendCommand(deviceID: "assembler", action: "stopTravel", parameters: [:])
}

func rotateClockwise() async throws {
    try await sendCommand(deviceID: "assembler", action: "rotateClockwise", parameters: [:])
}

func rotateCounterclockwise() async throws {
    try await sendCommand(deviceID: "assembler", action: "rotateCounterclockwise", parameters: [:])
}

func stopRotation() async throws {
    try await sendCommand(deviceID: "assembler", action: "stopRotation", parameters: [:])
}
```

- [ ] **Step 4: 在 Vision `AppModel` 中补充 PLC 反馈字段与状态文案**

```swift
var assemblerHeartbeatText = "--"
var assemblerTravelDirectionText = "停止"
var assemblerRotationDirectionText = "停止"

func apply(snapshot: GatewaySnapshot) {
    latestSnapshot = snapshot
    if let assembler = snapshot.devices.first(where: { $0.id == "assembler" }) {
        let props = assembler.properties ?? [:]
        assemblerHeartbeatText = String(Int(props["heartbeatPLC"] ?? 0))
        assemblerTravelDirectionText = Self.travelDirectionText(for: Int(props["travelDirectionAN1"] ?? 0))
        assemblerRotationDirectionText = Self.rotationDirectionText(for: Int(props["rotationDirectionAN2"] ?? 0))
    }
}
```

- [ ] **Step 5: 在 `DeviceControlWindow` 中替换旧的吸取/释放控件，并显示反馈区**

```swift
LabeledContent("PLC 心跳", value: appModel.assemblerHeartbeatText)
LabeledContent("行走方向", value: appModel.assemblerTravelDirectionText)
LabeledContent("旋转方向", value: appModel.assemblerRotationDirectionText)

Button("前进") { Task { try? await appModel.moveForward() } }
Button("后退") { Task { try? await appModel.moveBackward() } }
Button("停止行走") { Task { try? await appModel.stopTravel() } }
Button("顺时针") { Task { try? await appModel.rotateClockwise() } }
Button("逆时针") { Task { try? await appModel.rotateCounterclockwise() } }
Button("停止旋转") { Task { try? await appModel.stopRotation() } }
```

- [ ] **Step 6: 在主界面增加“现场 PLC 状态”摘要，避免必须开控制窗口才能看到反馈**

```swift
InfoCard(title: "PLC 心跳", value: appModel.assemblerHeartbeatText, detail: "来自反馈寄存器 100")
InfoCard(title: "行走方向", value: appModel.assemblerTravelDirectionText, detail: "AN1 当前状态")
InfoCard(title: "旋转方向", value: appModel.assemblerRotationDirectionText, detail: "AN2 当前状态")
```

- [ ] **Step 7: 运行 Vision 端测试，确认快照解析和控制接口已生效**

Run: `xcodebuild test -project tsjy-V/tsjy-V.xcodeproj -scheme tsjy-V -destination 'platform=visionOS Simulator,name=Apple Vision Pro' -only-testing:tsjy_VTests`
Expected: PASS

- [ ] **Step 8: 提交 Vision Pro 联动更新**

```bash
git add ../tsjy-V/tsjy-V/ControlClient.swift ../tsjy-V/tsjy-V/AppModel.swift ../tsjy-V/tsjy-V/DeviceControlWindow.swift ../tsjy-V/tsjy-V/ContentView.swift ../tsjy-V/tsjy-VTests/tsjy_VTests.swift
git commit -m "feat: align vision control with plc register map"
```

### Task 5: 做一次跨端联调模拟，并给现场排障留观察项

**Files:**
- Modify: `TSJY-0/tsjy/tsjyTests/tsjyTests.swift`
- Modify: `TSJY-0/docs/拼装机远程管控准备方案.md`
- Modify: `TSJY-0/清单/管片拼装远程控制开发顺序清单.md`

- [ ] **Step 1: 写失败测试，模拟 Vision 指令经 Mac 写入 PLC 控制区，再模拟 PLC 写回反馈区**

```swift
@MainActor
@Test func endToEnd_simulatedVisionToMacToPLCFeedbackRoundTrip() async throws {
    let bridge = SiteControlBridge()
    try await bridge.connect(to: "modbus://0.0.0.0:15022")

    _ = await bridge.execute(deviceID: "assembler", action: "moveForward", parameters: [:], commandID: "cmd-1")
    let _ = try await sendModbusWriteMultipleRegisters(
        port: 15022,
        startAddress: 100,
        values: [10, 1, 1, 0, 0]
    )

    try await Task.sleep(nanoseconds: 300_000_000)
    let snapshot = bridge.snapshot()
    let assembler = try #require(snapshot.devices.first(where: { $0.id == "assembler" }))
    let props = try #require(assembler.properties)
    #expect(props["travelDirectionAN1"] == 1)
    #expect(props["heartbeatPLC"] == 10)
}
```

- [ ] **Step 2: 运行测试，确认端到端模拟通过**

Run: `xcodebuild test -project tsjy.xcodeproj -scheme tsjy -destination 'platform=macOS' -parallel-testing-enabled NO -only-testing:tsjyTests/tsjyTests/endToEnd_simulatedVisionToMacToPLCFeedbackRoundTrip`
Expected: PASS

- [ ] **Step 3: 更新联调文档，给现场留最小观察项**

```md
1. 先确认 Mac 运行日志出现 `ModbusTCPServer accepted connection from PLC`
2. 再确认 PLC 读取控制区时出现 `parsed request FC3`
3. 再确认 PLC 写反馈区时出现 `remote write FC16: 100=..., 101=...`
4. 如果只有 FC3 没有 FC16，优先查 PLC 程序未发写请求
5. 如果出现 `waiting for complete frame`，优先查 PLC 发送流程或断线
```

- [ ] **Step 4: 提交联调基线**

```bash
git add tsjyTests/tsjyTests.swift ../docs/拼装机远程管控准备方案.md ../清单/管片拼装远程控制开发顺序清单.md
git commit -m "docs: add plc vision joint-debug checklist"
```

---

**Self-Review**
- 本计划覆盖了三块用户要求：PLC 回写排障与修复、Mac/Vision Pro 新控制点表调整、Vision Pro 控制与状态回显联动。
- 关键约束已固定：`40011~40014` 保持原四路，`40015/40016` 改为 `AN1/AN2` 的 `0/1/2` 枚举语义，反馈区 `100~104` 不改。
- 计划没有保留 “TODO/TBD/稍后补充” 占位语句；每个任务都给了测试、实现、验证与提交步骤。

**Plan complete and saved to `docs/superpowers/plans/2026-06-02-plc-vision-control-alignment.md`. Two execution options:**

**1. Subagent-Driven (recommended)** - 我按任务拆成独立子代理逐个执行、逐个验证，速度更快，回滚也更清晰

**2. Inline Execution** - 我就在这个会话里按计划直接改代码、跑测试、给你阶段性结果

**Which approach?**

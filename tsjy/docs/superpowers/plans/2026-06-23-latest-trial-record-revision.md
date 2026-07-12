# Latest Trial Record Revision Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 按《最新试验记录进一步修改建议》修正本地模拟器运动状态机、模拟器拒绝结果回传和无效停止样本判定。

**Architecture:** 远端 Windows 模拟器源码当前不在本仓库，因此先把仓库内可直接落地的两层补齐：`SiteControlBridge` 的本地 mock/Modbus 模拟行为，以及 `AppModel` 的命令结果语义与单表导出。先写红灯测试锁定联锁拒绝、运动状态变化和 `NO_ACTION_REQUIRED`，再最小化实现。

**Tech Stack:** Swift, Swift Testing, Observation, Modbus TCP, CSV 单表导出

---

### Task 1: 本地模拟器联锁与结果码

**Files:**
- Modify: `tsjy/tsjyTests/tsjyTests.swift`
- Modify: `tsjy/tsjy/SiteControlBridge.swift`
- Modify: `tsjy/tsjy/StreamingModels.swift`

- [ ] **Step 1: 写失败测试**
- [ ] **Step 2: 跑本地模拟器拒绝/成功路径测试确认红灯**
- [ ] **Step 3: 给 `SiteCommandResult` 增加 `simulatorAccepted/resultCode/rejectReason/executedAction/blockLayer`**
- [ ] **Step 4: 在本地 Modbus 模拟路径增加泵运行、允许信号和故障联锁判断**
- [ ] **Step 5: 重新运行测试确认转绿**

### Task 2: 停止样本有效性

**Files:**
- Modify: `tsjy/tsjyTests/tsjyTests.swift`
- Modify: `tsjy/tsjy/AppModel.swift`

- [ ] **Step 1: 写失败测试，验证停止前本来就是 0 时记为 `NO_ACTION_REQUIRED`**
- [ ] **Step 2: 跑该测试确认红灯**
- [ ] **Step 3: 在 `AppModel` 中基于 `startCommandID`、停止前方向和值判定无效停止样本**
- [ ] **Step 4: 确认导出 `有效样本/无效原因` 正确**
- [ ] **Step 5: 重新运行测试确认转绿**

### Task 3: 命令结果回传与导出对齐

**Files:**
- Modify: `tsjy/tsjy/AppModel.swift`
- Test: `tsjy/tsjyTests/tsjyTests.swift`

- [ ] **Step 1: 让本地模拟器拒绝进入 `REJECTED` 而不是 `COMMUNICATION_FAILED`**
- [ ] **Step 2: 把本地模拟器的结果码/拒绝原因回传到 `ControlServerMessage` 和 CSV**
- [ ] **Step 3: 进行语法级校验与 `build-for-testing` 验证**

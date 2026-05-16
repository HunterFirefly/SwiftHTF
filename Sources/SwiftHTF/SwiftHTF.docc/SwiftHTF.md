# ``SwiftHTF``

Swift 移植版的 OpenHTF —— 硬件测试框架。

## Overview

SwiftHTF 把 [OpenHTF](https://github.com/google/openhtf) 的核心模型搬到 Swift，专为
macOS / SwiftUI 上的下位机测试程序设计：

- **声明式 Plan**：`TestPlan { Phase(...); Group(...); Subtest(...) }` 用 result builder 拼装
- **三态 outcome**：每个 phase 自动按 measurement 校验聚合 `.pass / .marginalPass / .fail`，
  并附带 `.timeout / .skip / .error` 等细分终态
- **强类型 plug**：依赖注入风格的 plug 系统（电源 / 万用表 / 扫码枪等），
  setUp / tearDown 自动调度
- **Concurrency safe**：基于 actor / Sendable / `@MainActor`，跨 SwiftUI / 后台 actor
  零数据竞争
- **多 DUT 并发**：`TestExecutor.startSession(...)` 派生独立 session，
  共用 plan 但各自独立的 plug 实例和事件流

## Topics

### 快速入门

- <doc:GettingStarted>
- <doc:WritingPhases>

### 计划与执行

- ``TestPlan``
- ``TestExecutor``
- ``TestSession``
- ``TestEvent``
- ``TestRecord``
- ``TestOutcome``
- ``TestLoop``

### Phase 模型

- ``Phase``
- ``PhaseDefinition``
- ``PhaseResult``
- ``PhaseNode``
- ``Group``
- ``Subtest``
- ``Checkpoint``
- ``DynamicPhases``
- ``PhaseRecord``
- ``PhaseOutcomeType``

### Measurement 与 Trace

- ``Measurement``
- ``MeasurementSpec``
- ``MeasurementValidator``
- ``MeasurementValidationResult``
- ``SeriesMeasurement``
- ``SeriesMeasurementSpec``
- ``SeriesRecorder``
- ``Dimension``
- ``MonitorSpec``

### 单位维度

- ``Unit``
- ``PhysicalDimension``
- ``UnitRegistry``

### Plug 系统

- ``PlugProtocol``
- ``PlugManager``
- ``PromptPlug``

### 配置与诊断

- ``TestConfig``
- ``ConfigSchema``
- ``ConfigDeclaration``
- ``PhaseDiagnoser``
- ``TestDiagnoser``
- ``Diagnosis``
- ``DiagnoserTrigger``
- ``ClosureDiagnoser``
- ``ClosureTestDiagnoser``

### 输出与历史

- ``OutputCallback``
- ``ConsoleOutput``
- ``JSONOutput``
- ``CSVOutput``
- ``OutputFilenameTemplate``
- ``HistoryStore``

### 上下文与状态

- ``TestContext``
- ``PhaseState``
- ``PhaseArguments``
- ``Attachment``
- ``LogEntry``
- ``AnyCodableValue``

### 工站元数据 / 互斥

- ``StationInfo``
- ``DUTInfo``
- ``CodeInfo``
- ``SessionMetadata``
- ``StationLock``
- ``StationLockError``
- ``AbortRegistry``

### 错误类型

- ``TestError``

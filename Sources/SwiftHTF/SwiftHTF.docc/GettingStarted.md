# 快速入门

5 分钟跑出第一个 SwiftHTF 测试。

## Overview

本文用最小例子覆盖一次完整的测试流程：声明 plan → 注册 plug → 跑 phase →
读 record。先从单 DUT 同步入口开始，再扩展到 SwiftUI / 多 DUT。

## 1. 安装

Swift Package Manager 依赖：

```swift
.package(url: "https://github.com/LumenMarch/SwiftHTF.git", from: "0.3.0")
```

target 依赖：

```swift
.target(name: "MyTester", dependencies: ["SwiftHTF"])
```

## 2. 最小例子

```swift
import SwiftHTF

let plan = TestPlan(name: "Hello") {
    Phase(name: "Connect") { _ in .continue }
    Phase(
        name: "VccCheck",
        measurements: [.named("vcc").units(.volt).inRange(3.0, 3.6)]
    ) { ctx in
        ctx.measure("vcc", 3.3, unit: "V")
        return .continue
    }
    Phase(name: "Disconnect") { _ in .continue }
}

let executor = TestExecutor(plan: plan, outputCallbacks: [ConsoleOutput()])
let record = await executor.execute(serialNumber: "SN-001")
print("outcome:", record.outcome.rawValue)
```

`execute(...)` 内部派生一个 ``TestSession``，跑完后返回 ``TestRecord`` —— 终态、
phase 列表、measurement / attachment / log 等都挂在上面。

## 3. 加 plug

plug 是测试用到的"外设"抽象（电源、万用表、扫码枪……）。SwiftHTF 用类型驱动注入：

```swift
import SwiftHTF

final class MyPowerSupply: PlugProtocol {
    func setUp() async throws { /* connect */ }
    func tearDown() async throws { /* disconnect */ }

    @MainActor func setVoltage(_ v: Double) async throws { /* SCPI */ }
    @MainActor func readVoltage() async throws -> Double { /* SCPI */ 3.3 }
}

let plan = TestPlan(name: "PSU") {
    Phase(name: "Init") { @MainActor ctx in
        let psu = ctx.getPlug(MyPowerSupply.self)
        try await psu.setVoltage(3.3)
        return .continue
    }
}

let executor = TestExecutor(plan: plan)
await executor.register(MyPowerSupply.self)
_ = await executor.execute(serialNumber: "SN-001")
```

注册后每个 session 拥有独立的 plug 实例；setUp / tearDown 由框架自动调度。

## 4. SwiftUI 接入

`SwiftHTFUI` target 提供 `TestRunnerViewModel` 把事件流绑到 SwiftUI：

```swift
import SwiftHTFUI

@StateObject var runner = TestRunnerViewModel(executor: executor)

var body: some View {
    VStack {
        Text(runner.outcome?.rawValue ?? "idle")
        ForEach(runner.phases) { phase in
            Text("\(phase.name) \(phase.outcome.rawValue)")
        }
        Button("Start") {
            Task { await runner.start(serialNumber: "SN-001") }
        }
    }
}
```

## 5. 下一步

- <doc:WritingPhases>：phase 修饰符（timeout / monitor / withArgs / withPlug）
- ``DynamicPhases``：运行时由 ctx 决定后续 phase 列表
- ``TestExecutor``：多 DUT 并发 / abort / SIGINT 集成
- ``StationLock``：多进程互斥跑同一工站

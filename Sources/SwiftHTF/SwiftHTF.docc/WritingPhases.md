# 编写 Phase

Phase 是 SwiftHTF 的基本测试单元。本文介绍声明、measurement 校验、修饰符、
retry / timeout / monitor、参数化等常用模式。

## Overview

最简形式：

```swift
Phase(name: "Connect") { ctx in
    // 测试代码
    return .continue
}
```

闭包签名 `(TestContext) async throws -> PhaseResult`：

- `ctx` 是 ``TestContext``，可读 plug / 写 measurement / attach 文件 / log
- 返回 ``PhaseResult`` 决定流程：`.continue / .failAndContinue / .retry / .skip /
  .stop / .failSubtest`
- 抛错被 retry 配额吸收；用尽后按 `failureExceptions` 归类为 `.fail` 或 `.error`

## Measurement 校验

声明式 spec + 运行时写入：

```swift
Phase(
    name: "VccCheck",
    measurements: [
        .named("vcc").units(.volt).inRange(3.0, 3.6).marginalRange(3.1, 3.5),
        .named("ripple").units(.millivolt).atMost(50).optional(),
    ]
) { ctx in
    ctx.measure("vcc", 3.32, unit: "V")
    ctx.measure("ripple", 23.5, unit: "mV")
    return .continue
}
```

- `inRange(...)` 硬限值；落外 → phase outcome `.fail`
- `marginalRange(...)` 警告带；硬限内但接近边界 → `.marginalPass`
- `units(.volt)`：与 OpenHTF `with_units(units.VOLT)` 等价；harvest 时若
  measurement 入参 unit 维度与 spec 不符 → outcome `.fail`
- `optional()`：phase 内未写也不报 missing

完整 validator 列表见 ``MeasurementSpec``。

## Retry / Timeout / Monitor

链式修饰符：

```swift
Phase(name: "Soak", retryCount: 2) { @MainActor ctx in
    try await Task.sleep(nanoseconds: 30 * 1_000_000_000)
    return .continue
}
.timeout(35)                                          // 35s 超时 → outcome .timeout
.monitor("temp_C", unit: "°C", every: 1.0) { ctx in   // 周期采样写入 ctx.series
    try await ctx.getPlug(Thermo.self).read()
}
```

- ``Phase/timeout(_:)-(TimeInterval)`` 包一层 `withThrowingTaskGroup`；超时仍消耗 retry 配额
- ``Phase/monitor(_:unit:every:drainTimeout:errorThreshold:_:)-(_,_,TimeInterval,_,_,_)``
  与 phase 主体并发采样；主体结束自动 cancel + drain
- macOS 13+ 提供 `Duration` 重载（`.timeout(.seconds(35))`）

## 参数化（withArgs / withPlug）

跑同一 phase 的多个变体：

```swift
TestPlan(name: "Boards") {
    for rail in ["3v3", "5v", "12v"] {
        Phase(name: "Rail", measurements: [.named("v").units(.volt)]) { ctx in
            let target = ctx.args.double("target") ?? 0
            ctx.measure("v", try await readRail(rail), unit: "V")
            return .continue
        }
        .withArgs(["target": .double(targetFor(rail))], nameSuffix: "_\(rail)")
    }
}
```

- `withArgs(_:nameSuffix:)`：注入运行时参数，phase 内通过 `ctx.args.string / double`
  读出；持久化到 `PhaseRecord.arguments`
- `withPlug(Real.self, replacedWith: Mock.self)`：本 phase 内重定向 plug，
  PlugManager 注册表不变

## 动态注入

运行时由前一个 phase 决定后续节点：

```swift
TestPlan(name: "FanOut") {
    Phase(name: "Scan") { ctx in
        ctx.state.set("dut_count", 8)
        return .continue
    }
    DynamicPhases("PerDUT") { ctx in
        let n = ctx.state.int("dut_count") ?? 0
        return (0..<n).map { i in
            .phase(Phase(name: "Check_\(i)") { _ in .continue })
        }
    }
}
```

详见 ``DynamicPhases``。

## 诊断器

phase 失败时跑额外分析：

```swift
Phase(
    name: "VccCheck",
    measurements: [.named("vcc").inRange(3.0, 3.6)],
    diagnosers: [
        ClosureDiagnoser("vcc-overshoot") { record, ctx in
            guard let v = record.measurements["vcc"]?.value.asDouble, v > 4.0 else { return [] }
            return [Diagnosis(code: "VCC_OVERSHOOT", message: "vcc=\(v) > 4V")]
        },
    ]
) { ctx in
    ctx.measure("vcc", 4.5)
    return .continue
}
```

诊断器按 ``DiagnoserTrigger`` 控制触发时机：`.onlyOnFail`（phase 失败族终态触发，
默认）或 `.always`（含 pass 终态都跑，用作 metric / log）。

## 子流程容器

- ``Group``：嵌套作用域，独立 setup / children / teardown + 局部 `continueOnFail`
- ``Subtest``：失败被隔离，内部短路但不污染外层 outcome
- ``Checkpoint``：在某点检查"本作用域是否已有失败"，决定是否短路后续节点

## 下一步

- ``MeasurementSpec``：内置 validator 全集（inRange / withinPercent / oneOf /
  setEquals / regex / custom / ...）
- ``SeriesMeasurement``：多维序列测量（IV 曲线 / 扫频 / 扫温）
- ``MonitorSpec``：周期采样底层 spec

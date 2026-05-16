import Foundation

/// 运行时动态生成的节点集合。
///
/// 与 `Group / Subtest` 等容器节点并列；执行到本节点时调闭包生成 `[PhaseNode]`，
/// 把它们串入当前作用域剩余节点 **之前**（即紧接在 DynamicPhases 后立即跑）。
///
/// 典型用法：根据前一个 phase 的扫码 / 配置决定后续 fan-out。
///
/// ```swift
/// TestPlan(name: "fan-out") {
///     Phase(name: "Scan") { ctx in
///         ctx.state.set("rails", AnyCodableValue.array([
///             .string("3v3"), .string("5v"), .string("12v"),
///         ]))
///         return .continue
///     }
///     DynamicPhases("PerRail") { ctx in
///         let arr = ctx.state.value("rails", as: [String].self) ?? []
///         return arr.map { rail in
///             Phase(name: "Check_\(rail)") { _ in .continue }
///         }.map(PhaseNode.phase)
///     }
/// }
/// ```
///
/// 语义：
/// - **作用域**：生成的节点继承当前 `groupPath`（顶层 / Group / Subtest 内表现一致）
/// - **错误处理**：闭包抛错时不向外冒泡，写一条 `PhaseRecord(outcome: .error)`
///   占位（name 用 DynamicPhases.name），剩余兄弟节点继续执行
/// - **嵌套**：生成的节点本身可以是 Phase / Group / Subtest / 另一个 DynamicPhases，
///   实现递归 fan-out
public struct DynamicPhases: Sendable, Identifiable {
    public typealias Generator = @Sendable @MainActor (TestContext) async throws -> [PhaseNode]

    public let id: UUID
    public let name: String
    public let generate: Generator

    /// 主初始化。
    ///
    /// - Parameters:
    ///   - id: 唯一标识；不指定时自动生成 UUID
    ///   - name: 容器名（用于 trace 日志 / 错误占位 PhaseRecord 的 name）
    ///   - generate: 生成节点的异步闭包；可读 ctx 拿前一个 phase 的 state / measurement
    public init(
        id: UUID = UUID(),
        name: String,
        _ generate: @escaping Generator
    ) {
        self.id = id
        self.name = name
        self.generate = generate
    }

    /// 便捷构造：`DynamicPhases("PerRail") { ctx in ... }`
    ///
    /// - Parameters:
    ///   - name: 容器名
    ///   - generate: 生成节点的异步闭包
    public init(_ name: String, _ generate: @escaping Generator) {
        self.init(name: name, generate)
    }
}

// MARK: - DSL builder 兼容

public extension TestPlanBuilder {
    static func buildExpression(_ dynamic: DynamicPhases) -> [PhaseNode] {
        [.dynamic(dynamic)]
    }
}

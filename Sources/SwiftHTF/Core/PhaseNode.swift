import Foundation

/// 测试计划节点：单个 Phase、一个嵌套的 Group、一个 Subtest、Checkpoint，或 DynamicPhases。
///
/// 通过 `@TestPlanBuilder` 自动从 `Phase` / `Group` / `Subtest` / `Checkpoint` /
/// `DynamicPhases` 表达式包装，使用方很少直接构造。
public enum PhaseNode: Sendable {
    case phase(Phase)
    indirect case group(Group)
    indirect case subtest(Subtest)
    case checkpoint(Checkpoint)
    /// 运行时动态生成节点的容器；执行时调用闭包拿到 `[PhaseNode]` 串入剩余节点之前。
    case dynamic(DynamicPhases)

    /// 节点名（phase 名 / group 名 / subtest 名 / checkpoint 名 / dynamic 名）
    public var name: String {
        switch self {
        case let .phase(p): p.definition.name
        case let .group(g): g.name
        case let .subtest(s): s.name
        case let .checkpoint(c): c.name
        case let .dynamic(d): d.name
        }
    }

    public var asPhase: Phase? {
        if case let .phase(p) = self { return p }
        return nil
    }

    public var asGroup: Group? {
        if case let .group(g) = self { return g }
        return nil
    }

    public var asSubtest: Subtest? {
        if case let .subtest(s) = self { return s }
        return nil
    }

    public var asCheckpoint: Checkpoint? {
        if case let .checkpoint(c) = self { return c }
        return nil
    }

    public var asDynamic: DynamicPhases? {
        if case let .dynamic(d) = self { return d }
        return nil
    }
}

/// Checkpoint：测试流中的"汇合点"，扫描本作用域已收集的 phase outcomes 决定是否继续。
///
/// 应用场景：排错期"先标记不阻断"模式 —— 把若干 phase 都跑完拿数据，最后由
/// checkpoint 决定本轮是否进入更耗时的 phase（FullSuite / Stress Test 等）。
///
/// 默认行为：
/// - 失败定义：本作用域内任一已完成 phase outcome 为 `.fail` 或 `.error`
/// - 失败时：写入 `PhaseRecord(name: checkpoint.name, outcome: .fail)`，短路剩余兄弟节点
///   （Group 内：触发本 Group 短路 + 上传 outcome.failed；Subtest 内：仅触发 subtest 短路，不冒泡）
/// - 通过时：写入 `PhaseRecord(name: checkpoint.name, outcome: .pass)`，继续
///
/// 作用域：仅看**本作用域**（顶层看顶层 phases；group 看本 group；subtest 看本 subtest），
/// 嵌套 group / subtest 内部的失败不传染外层 checkpoint（与 Subtest 隔离语义一致）。
///
/// ```swift
/// TestPlan(name: "DUT") {
///     Phase(name: "Connect") { _ in .continue }
///     Phase(name: "VccCheck") { _ in .failAndContinue }
///     Checkpoint("Sanity")                            // 之前有 fail → 短路；写入 PhaseRecord(.fail)
///     Phase(name: "FullSuite") { _ in .continue }     // 不会跑
/// }
/// ```
public struct Checkpoint: Sendable, Identifiable {
    public let id: UUID
    public let name: String

    public init(id: UUID = UUID(), name: String) {
        self.id = id
        self.name = name
    }

    /// 便捷构造：`Checkpoint("Sanity")`
    public init(_ name: String) {
        self.init(id: UUID(), name: name)
    }
}

/// Subtest：一组 phase 形成的"可隔离失败"单元。
///
/// 与 `Group` 的关键差异：
/// - 内部任一节点 `.fail` / `.error` / `.failSubtest` → **短路**剩余节点；
/// - subtest 失败 **不传播** 到外层（外层 TestRecord.outcome 不因此变 .fail）；
/// - 终态写入独立的 `SubtestRecord`（id / outcome / phaseIDs / failureReason），
///   供 UI 与输出 sink 单独渲染聚合视图。
///
/// ```swift
/// TestPlan(name: "Board") {
///     Phase(name: "Connect") { _ in .continue }
///     Subtest("PowerTests") {
///         Phase(name: "VccCheck") { _ in .continue }
///         Phase(name: "VddCheck") { _ in .failAndContinue }   // 短路：下一个不跑
///         Phase(name: "VbatCheck") { _ in .continue }
///     }
///     Phase(name: "Cleanup") { _ in .continue }   // 仍然会跑
/// }
/// ```
public struct Subtest: Sendable, Identifiable {
    public let id: UUID
    public let name: String
    public let nodes: [PhaseNode]
    /// 运行时条件门：返回 false 时整 subtest 跳过（SubtestRecord.outcome=.skip，phaseIDs=[]，不计 fail）。
    public let runIf: RunIfPredicate?

    public init(
        id: UUID = UUID(),
        name: String,
        nodes: [PhaseNode],
        runIf: RunIfPredicate? = nil
    ) {
        self.id = id
        self.name = name
        self.nodes = nodes
        self.runIf = runIf
    }
}

public extension Subtest {
    /// DSL builder 形式
    init(
        _ name: String,
        runIf: RunIfPredicate? = nil,
        @TestPlanBuilder nodes: () -> [PhaseNode]
    ) {
        self.init(name: name, nodes: nodes(), runIf: runIf)
    }
}

/// 嵌套 Group：含独立的 setup / children / teardown 与局部 `continueOnFail`。
///
/// ```swift
/// Group("PowerRail") {
///     Phase(name: "PowerOn") { _ in .continue }
///     Phase(name: "VccCheck") { _ in .continue }
/// } setup: {
///     Phase(name: "Connect") { _ in .continue }
/// } teardown: {
///     Phase(name: "Disconnect") { _ in .continue }
/// }
/// ```
///
/// 执行语义（`TestExecutor` 实现）：
/// - 依次跑 setup → children → teardown
/// - setup 任一节点 `.fail/.error` 视为 group 失败，**跳过 children**，仍跑 teardown
/// - children 内 fail 时，看 `continueOnFail`（局部），后续兄弟是否继续
/// - teardown 必跑
public struct Group: Sendable, Identifiable {
    public let id: UUID
    public let name: String
    public let setup: [PhaseNode]
    public let children: [PhaseNode]
    public let teardown: [PhaseNode]
    public let continueOnFail: Bool
    /// 运行时条件门：返回 false 时整 group 跳过（合成一条 skip PhaseRecord，
    /// setup / children / teardown 全不跑），不计 fail。
    public let runIf: RunIfPredicate?

    public init(
        id: UUID = UUID(),
        name: String,
        setup: [PhaseNode] = [],
        children: [PhaseNode],
        teardown: [PhaseNode] = [],
        continueOnFail: Bool = false,
        runIf: RunIfPredicate? = nil
    ) {
        self.id = id
        self.name = name
        self.setup = setup
        self.children = children
        self.teardown = teardown
        self.continueOnFail = continueOnFail
        self.runIf = runIf
    }
}

// MARK: - DSL 友好 init

public extension Group {
    /// 仅 children 的 builder 形式
    init(
        _ name: String,
        continueOnFail: Bool = false,
        runIf: RunIfPredicate? = nil,
        @TestPlanBuilder children: () -> [PhaseNode]
    ) {
        self.init(
            name: name,
            setup: [],
            children: children(),
            teardown: [],
            continueOnFail: continueOnFail,
            runIf: runIf
        )
    }

    /// 同时声明 setup / teardown 的 builder 形式
    init(
        _ name: String,
        continueOnFail: Bool = false,
        runIf: RunIfPredicate? = nil,
        @TestPlanBuilder children: () -> [PhaseNode],
        @TestPlanBuilder setup: () -> [PhaseNode] = { [] },
        @TestPlanBuilder teardown: () -> [PhaseNode] = { [] }
    ) {
        self.init(
            name: name,
            setup: setup(),
            children: children(),
            teardown: teardown(),
            continueOnFail: continueOnFail,
            runIf: runIf
        )
    }
}

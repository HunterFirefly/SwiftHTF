import Foundation

/// 测试计划 result builder
///
/// 用法：
/// ```swift
/// let plan = TestPlan(name: "X3531") {
///     Phase(name: "Connect_DUT") { ctx in ... }
///     Phase(name: "Get_FW") { ctx in ... }
///     if config.includeBootTest {
///         Phase(name: "Boot_Test") { ctx in ... }
///     }
///     for item in items {
///         Phase(name: item.name) { ctx in ... }
///     }
/// }
/// ```
@resultBuilder
public enum TestPlanBuilder {
    public static func buildBlock(_ components: [Phase]...) -> [Phase] {
        components.flatMap { $0 }
    }

    public static func buildExpression(_ phase: Phase) -> [Phase] {
        [phase]
    }

    public static func buildExpression(_ phases: [Phase]) -> [Phase] {
        phases
    }

    public static func buildOptional(_ phases: [Phase]?) -> [Phase] {
        phases ?? []
    }

    public static func buildEither(first phases: [Phase]) -> [Phase] {
        phases
    }

    public static func buildEither(second phases: [Phase]) -> [Phase] {
        phases
    }

    public static func buildArray(_ components: [[Phase]]) -> [Phase] {
        components.flatMap { $0 }
    }

    public static func buildLimitedAvailability(_ phases: [Phase]) -> [Phase] {
        phases
    }
}

extension TestPlan {
    /// 使用 result builder 构建测试计划
    public init(
        name: String,
        setup: [Phase]? = nil,
        teardown: [Phase]? = nil,
        continueOnFail: Bool = false,
        @TestPlanBuilder phases: () -> [Phase]
    ) {
        self.init(
            name: name,
            phases: phases(),
            setup: setup,
            teardown: teardown,
            continueOnFail: continueOnFail
        )
    }
}

@testable import SwiftHTF
import XCTest

/// `DynamicPhases` 动态注入：闭包生成节点串入剩余兄弟前，
/// 含错误 / 嵌套作用域 / 失败传播。
final class DynamicPhasesTests: XCTestCase {
    // MARK: - 基本 fan-out

    func testGeneratesPhasesInline() async {
        let plan = TestPlan(name: "dyn-basic") {
            Phase(name: "Scan") { ctx in
                ctx.state.set("rails", AnyCodableValue.array([
                    .string("3v3"), .string("5v"), .string("12v"),
                ]))
                return .continue
            }
            DynamicPhases("PerRail") { ctx in
                let arr = ctx.state.value("rails", as: [AnyCodableValue].self) ?? []
                return arr.compactMap { v -> PhaseNode? in
                    guard case let .string(rail) = v else { return nil }
                    return .phase(Phase(name: "Check_\(rail)") { _ in .continue })
                }
            }
            Phase(name: "Final") { _ in .continue }
        }
        let record = await TestExecutor(plan: plan).execute()
        XCTAssertEqual(record.outcome, .pass)
        // Scan + 3 个 Check_* + Final
        XCTAssertEqual(record.phases.map(\.name), [
            "Scan", "Check_3v3", "Check_5v", "Check_12v", "Final",
        ])
    }

    // MARK: - 空生成列表不影响后续

    func testEmptyGenerationDoesNothing() async {
        let plan = TestPlan(name: "dyn-empty") {
            DynamicPhases("Spawn") { _ in [] }
            Phase(name: "After") { _ in .continue }
        }
        let record = await TestExecutor(plan: plan).execute()
        XCTAssertEqual(record.outcome, .pass)
        XCTAssertEqual(record.phases.map(\.name), ["After"])
    }

    // MARK: - 生成的 phase 失败按外层 continueOnFail 处理

    func testGeneratedFailureShortCircuitsByDefault() async {
        let plan = TestPlan(name: "dyn-fail") {
            DynamicPhases("Spawn") { _ in
                [
                    .phase(Phase(name: "A") { _ in .failAndContinue }),
                    .phase(Phase(name: "B") { _ in .continue }),
                ]
            }
            Phase(name: "After") { _ in .continue }
        }
        let record = await TestExecutor(plan: plan).execute()
        XCTAssertEqual(record.outcome, .fail)
        // 默认 continueOnFail=false → A 失败短路：B 不跑、After 也不跑
        XCTAssertEqual(record.phases.map(\.name), ["A"])
    }

    func testGeneratedFailureContinuesWithFlag() async {
        let plan = TestPlan(name: "dyn-fail-cont", continueOnFail: true) {
            DynamicPhases("Spawn") { _ in
                [
                    .phase(Phase(name: "A") { _ in .failAndContinue }),
                    .phase(Phase(name: "B") { _ in .continue }),
                ]
            }
            Phase(name: "After") { _ in .continue }
        }
        let record = await TestExecutor(plan: plan).execute()
        XCTAssertEqual(record.outcome, .fail)
        XCTAssertEqual(record.phases.map(\.name), ["A", "B", "After"])
    }

    // MARK: - 闭包抛错时占位 .error，剩余兄弟继续跑

    func testGeneratorThrowsPlacesErrorRecord() async {
        let plan = TestPlan(name: "dyn-throw", continueOnFail: true) {
            DynamicPhases("Boom") { _ in
                throw DynamicPhasesTestError.boom
            }
            Phase(name: "After") { _ in .continue }
        }
        let record = await TestExecutor(plan: plan).execute()
        XCTAssertEqual(record.phases.count, 2)
        XCTAssertEqual(record.phases[0].name, "Boom")
        XCTAssertEqual(record.phases[0].outcome, .error)
        XCTAssertTrue(record.phases[0].errorMessage?.contains("DynamicPhases generator threw") == true)
        // 占位是 framework 错误而非测试失败：record.outcome 不被传染
        XCTAssertEqual(record.outcome, .pass)
        XCTAssertEqual(record.phases[1].name, "After")
        XCTAssertEqual(record.phases[1].outcome, .pass)
    }

    // MARK: - groupPath 继承

    func testInheritsGroupPath() async {
        let plan = TestPlan(name: "dyn-path") {
            Group("Power") {
                DynamicPhases("Spawn") { _ in
                    [.phase(Phase(name: "Inner") { _ in .continue })]
                }
            }
        }
        let record = await TestExecutor(plan: plan).execute()
        XCTAssertEqual(record.outcome, .pass)
        let inner = record.phases.first { $0.name == "Inner" }
        XCTAssertEqual(inner?.groupPath, ["Power"])
    }

    // MARK: - 在 subtest 内：失败被 subtest 隔离

    func testInsideSubtestFailureIsolated() async {
        let plan = TestPlan(name: "dyn-subtest") {
            Subtest("InnerSuite") {
                DynamicPhases("Spawn") { _ in
                    [.phase(Phase(name: "BoomChild") { _ in .failAndContinue })]
                }
            }
            Phase(name: "After") { _ in .continue }
        }
        let record = await TestExecutor(plan: plan).execute()
        // subtest 失败不冒泡：record.outcome=.pass
        XCTAssertEqual(record.outcome, .pass)
        XCTAssertEqual(record.subtests.count, 1)
        XCTAssertEqual(record.subtests[0].outcome, .fail)
        XCTAssertEqual(record.phases.last?.name, "After")
    }

    // MARK: - 递归 fan-out（生成的节点本身也是 dynamic）

    func testRecursiveDynamic() async {
        let plan = TestPlan(name: "dyn-recursive") {
            DynamicPhases("Outer") { _ in
                [
                    .phase(Phase(name: "First") { _ in .continue }),
                    .dynamic(DynamicPhases(name: "Inner") { _ in
                        [.phase(Phase(name: "Last") { _ in .continue })]
                    }),
                ]
            }
        }
        let record = await TestExecutor(plan: plan).execute()
        XCTAssertEqual(record.outcome, .pass)
        XCTAssertEqual(record.phases.map(\.name), ["First", "Last"])
    }
}

private enum DynamicPhasesTestError: Error { case boom }

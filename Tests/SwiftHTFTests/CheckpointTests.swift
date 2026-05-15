@testable import SwiftHTF
import XCTest

final class CheckpointTests: XCTestCase {
    // MARK: - 顶层 pass / fail

    func testCheckpointPassesWhenNoPriorFail() async {
        let plan = TestPlan(name: "pass") {
            Phase(name: "p1") { _ in .continue }
            Phase(name: "p2") { _ in .continue }
            Checkpoint("Sanity")
            Phase(name: "p3") { _ in .continue }
        }
        let record = await TestExecutor(plan: plan).execute()
        XCTAssertEqual(record.outcome, .pass)
        XCTAssertEqual(record.phases.map(\.name), ["p1", "p2", "Sanity", "p3"])
        let cp = record.phases.first { $0.name == "Sanity" }
        XCTAssertEqual(cp?.outcome, .pass)
        XCTAssertNil(cp?.errorMessage)
    }

    func testCheckpointFailsAndShortCircuits() async {
        // 典型用法：continueOnFail=true 让 fail 后续 phase 仍跑，由 checkpoint 汇合判断
        let plan = TestPlan(name: "fail", continueOnFail: true) {
            Phase(name: "p1") { _ in .continue }
            Phase(name: "p2") { _ in .failAndContinue }
            Checkpoint("Sanity")
            Phase(name: "p3") { _ in .continue } // 不应跑
        }
        let record = await TestExecutor(plan: plan).execute()
        XCTAssertEqual(record.outcome, .fail)
        XCTAssertEqual(record.phases.map(\.name), ["p1", "p2", "Sanity"])
        let cp = record.phases.first { $0.name == "Sanity" }
        XCTAssertEqual(cp?.outcome, .fail)
        XCTAssertNotNil(cp?.errorMessage)
    }

    // MARK: - continueOnFail 不影响 checkpoint 短路

    func testCheckpointShortCircuitsRegardlessOfContinueOnFail() async {
        let plan = TestPlan(name: "ctn", continueOnFail: true) {
            Phase(name: "boom") { _ in .failAndContinue }
            Checkpoint("CP")
            Phase(name: "after_cp") { _ in .continue } // 不应跑（checkpoint 短路）
        }
        let record = await TestExecutor(plan: plan).execute()
        XCTAssertEqual(record.outcome, .fail)
        XCTAssertEqual(record.phases.map(\.name), ["boom", "CP"])
    }

    // MARK: - error 也触发

    func testCheckpointTriggeredByError() async {
        // continueOnFail=true 让 p1 抛错后仍跑到 checkpoint
        struct BadError: Error {}
        let plan = TestPlan(name: "err", continueOnFail: true) {
            Phase(name: "p1") { _ in throw BadError() }
            Checkpoint("CP")
            Phase(name: "p2") { _ in .continue }
        }
        let record = await TestExecutor(plan: plan).execute()
        XCTAssertEqual(record.outcome, .fail)
        XCTAssertEqual(record.phases.count, 2)
        XCTAssertEqual(record.phases[0].outcome, .error)
        XCTAssertEqual(record.phases[1].name, "CP")
        XCTAssertEqual(record.phases[1].outcome, .fail)
        XCTAssertFalse(record.phases.contains { $0.name == "p2" })
    }

    // MARK: - skip / marginalPass 不触发

    func testSkipDoesNotTriggerCheckpoint() async {
        let plan = TestPlan(name: "skip") {
            Phase(name: "skipped", runIf: { _ in false }) { _ in .continue }
            Phase(name: "p2") { _ in .continue }
            Checkpoint("CP")
            Phase(name: "after") { _ in .continue }
        }
        let record = await TestExecutor(plan: plan).execute()
        XCTAssertEqual(record.outcome, .pass)
        XCTAssertTrue(record.phases.contains { $0.name == "after" })
        XCTAssertEqual(record.phases.first { $0.name == "CP" }?.outcome, .pass)
    }

    func testMarginalPassDoesNotTriggerCheckpoint() async {
        let plan = TestPlan(name: "marginal") {
            Phase(name: "warn", measurements: [.named("v").inRange(2.5, 4.0).marginalRange(3.0, 3.6)]) { ctx in
                ctx.measure("v", 3.8)
                return .continue
            }
            Checkpoint("CP")
            Phase(name: "after") { _ in .continue }
        }
        let record = await TestExecutor(plan: plan).execute()
        XCTAssertEqual(record.outcome, TestOutcome.marginalPass)
        XCTAssertEqual(record.phases.first { $0.name == "CP" }?.outcome, .pass)
        XCTAssertTrue(record.phases.contains { $0.name == "after" })
    }

    // MARK: - 多 checkpoint 串联

    func testMultipleCheckpointsInSequence() async {
        let plan = TestPlan(name: "chain", continueOnFail: true) {
            Phase(name: "p1") { _ in .continue }
            Checkpoint("CP1")
            Phase(name: "p2") { _ in .failAndContinue }
            Checkpoint("CP2")
            Phase(name: "p3") { _ in .continue } // 不应跑
        }
        let record = await TestExecutor(plan: plan).execute()
        XCTAssertEqual(record.phases.map(\.name), ["p1", "CP1", "p2", "CP2"])
        XCTAssertEqual(record.phases.first { $0.name == "CP1" }?.outcome, .pass)
        XCTAssertEqual(record.phases.first { $0.name == "CP2" }?.outcome, .fail)
    }

    // MARK: - Group 内独立作用域

    func testCheckpointInsideGroupSeesOnlyGroupScope() async {
        // 外层 phase fail；group 内 checkpoint 在本 group 内无 fail，应通过
        let plan = TestPlan(name: "scope", continueOnFail: true) {
            Phase(name: "outer_fail") { _ in .failAndContinue }
            Group("G") {
                Phase(name: "g1") { _ in .continue }
                Checkpoint("InnerCP")
                Phase(name: "g2") { _ in .continue }
            }
        }
        let record = await TestExecutor(plan: plan).execute()
        // InnerCP 看的是 group 内 phase outcomes，无 fail
        let innerCP = record.phases.first { $0.name == "InnerCP" }
        XCTAssertEqual(innerCP?.outcome, .pass)
        XCTAssertTrue(record.phases.contains { $0.name == "g2" })
    }

    func testCheckpointInsideGroupShortCircuitsLocally() async {
        let plan = TestPlan(name: "gshort") {
            Group("G", continueOnFail: true) {
                Phase(name: "g1") { _ in .failAndContinue }
                Checkpoint("CP")
                Phase(name: "g2") { _ in .continue } // 不应跑
            }
        }
        let record = await TestExecutor(plan: plan).execute()
        XCTAssertEqual(record.phases.map(\.name), ["g1", "CP"])
        XCTAssertEqual(record.phases.first { $0.name == "CP" }?.outcome, .fail)
    }

    // MARK: - Subtest 内 checkpoint（subtest 自身已经"phase fail 即短路"，checkpoint 在此作为占位 milestone）

    func testCheckpointInsideSubtestPassesWhenNoPriorFail() async throws {
        let plan = TestPlan(name: "subcp") {
            Subtest("S") {
                Phase(name: "s1") { _ in .continue }
                Checkpoint("CP")
                Phase(name: "s2") { _ in .continue }
            }
            Phase(name: "after") { _ in .continue }
        }
        let record = await TestExecutor(plan: plan).execute()
        XCTAssertEqual(record.outcome, .pass)
        XCTAssertEqual(record.phases.map(\.name), ["s1", "CP", "s2", "after"])
        XCTAssertEqual(record.phases.first { $0.name == "CP" }?.outcome, .pass)
        XCTAssertEqual(record.subtests[0].outcome, .pass)
        // CP 也应该出现在 subtest.phaseIDs 中
        let cpID = record.phases.first { $0.name == "CP" }?.id
        XCTAssertNotNil(cpID)
        XCTAssertTrue(try record.subtests[0].phaseIDs.contains(XCTUnwrap(cpID)))
    }

    // MARK: - 嵌套 Subtest 失败不算外层作用域 fail

    func testNestedSubtestFailDoesNotTriggerOuterCheckpoint() async {
        let plan = TestPlan(name: "nestiso") {
            Subtest("Inner") {
                Phase(name: "boom") { _ in .failAndContinue }
            }
            // 顶层 outcome.failed 不应被 Subtest fail 污染，所以 checkpoint 通过
            Checkpoint("OuterCP")
            Phase(name: "after") { _ in .continue }
        }
        let record = await TestExecutor(plan: plan).execute()
        XCTAssertEqual(record.outcome, .pass)
        let cp = record.phases.first { $0.name == "OuterCP" }
        XCTAssertEqual(cp?.outcome, .pass, "Subtest 隔离失败不应让外层 checkpoint fail")
        XCTAssertTrue(record.phases.contains { $0.name == "after" })
    }

    // MARK: - DSL 节点结构

    func testTestPlanNodesContainCheckpoint() {
        let plan = TestPlan(name: "dsl") {
            Phase(name: "p") { _ in .continue }
            Checkpoint("CP")
        }
        XCTAssertEqual(plan.nodes.count, 2)
        XCTAssertNotNil(plan.nodes[1].asCheckpoint)
        XCTAssertEqual(plan.nodes[1].asCheckpoint?.name, "CP")
    }
}

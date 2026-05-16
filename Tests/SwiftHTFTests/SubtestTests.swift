@testable import SwiftHTF
import XCTest

final class SubtestTests: XCTestCase {
    // MARK: - 基本通过 / 路径 / 记录关联

    func testSubtestPassRecordsAllPhases() async {
        let plan = TestPlan(name: "pass") {
            Subtest("Power") {
                Phase(name: "p1") { _ in .continue }
                Phase(name: "p2") { _ in .continue }
            }
        }
        let record = await TestExecutor(plan: plan).execute()
        XCTAssertEqual(record.outcome, .pass)
        XCTAssertEqual(record.phases.map(\.name), ["p1", "p2"])
        XCTAssertTrue(record.phases.allSatisfy { $0.groupPath == ["Power"] })
        XCTAssertEqual(record.subtests.count, 1)
        let st = record.subtests[0]
        XCTAssertEqual(st.name, "Power")
        XCTAssertEqual(st.outcome, .pass)
        XCTAssertNil(st.failureReason)
        XCTAssertEqual(st.phaseIDs.count, 2)
        XCTAssertEqual(st.phaseIDs, record.phases.map(\.id))
    }

    // MARK: - 隔离失败：subtest fail 不影响 TestRecord.outcome

    func testSubtestFailDoesNotFailTestRecord() async {
        let plan = TestPlan(name: "iso") {
            Subtest("FlakyBlock") {
                Phase(name: "boom") { _ in .failAndContinue }
                Phase(name: "skipped") { _ in .continue }
            }
            Phase(name: "after") { _ in .continue }
        }
        let record = await TestExecutor(plan: plan).execute()
        XCTAssertEqual(record.outcome, .pass, "subtest 失败不应让 TestRecord 整体 fail")
        XCTAssertEqual(record.subtests.count, 1)
        XCTAssertEqual(record.subtests[0].outcome, .fail)
        XCTAssertNotNil(record.subtests[0].failureReason)
        // 短路：skipped 不应进 record.phases
        XCTAssertEqual(record.phases.map(\.name), ["boom", "after"])
        // after 必须跑（subtest 隔离）
        XCTAssertTrue(record.phases.contains { $0.name == "after" })
    }

    // MARK: - 短路

    func testSubtestShortCircuitsOnPhaseFail() async {
        let plan = TestPlan(name: "short") {
            Subtest("S") {
                Phase(name: "p1") { _ in .continue }
                Phase(name: "p2") { _ in .failAndContinue }
                Phase(name: "p3") { _ in .continue }
            }
        }
        let record = await TestExecutor(plan: plan).execute()
        XCTAssertEqual(record.phases.map(\.name), ["p1", "p2"], "短路：p3 不应出现在 record.phases")
        XCTAssertEqual(record.subtests[0].outcome, .fail)
    }

    // MARK: - .failSubtest result

    func testFailSubtestResultShortCircuits() async {
        let plan = TestPlan(name: "fs") {
            Subtest("S") {
                Phase(name: "p1") { _ in .failSubtest }
                Phase(name: "p2") { _ in .continue }
            }
        }
        let record = await TestExecutor(plan: plan).execute()
        XCTAssertEqual(record.phases.count, 1)
        XCTAssertEqual(record.phases[0].name, "p1")
        XCTAssertEqual(record.phases[0].outcome, .fail)
        XCTAssertTrue(record.phases[0].subtestFailRequested)
        XCTAssertEqual(record.subtests[0].outcome, .fail)
        XCTAssertEqual(record.subtests[0].failureReason, "p1: failSubtest")
    }

    func testFailSubtestOutsideSubtestEquivalentToFail() async {
        // 不在 subtest 内时 .failSubtest 等价 .failAndContinue
        let plan = TestPlan(name: "fs-out") {
            Phase(name: "p1") { _ in .failSubtest }
        }
        let record = await TestExecutor(plan: plan).execute()
        XCTAssertEqual(record.outcome, .fail)
        XCTAssertEqual(record.phases.count, 1)
        XCTAssertEqual(record.phases[0].outcome, .fail)
        XCTAssertTrue(record.phases[0].subtestFailRequested)
        XCTAssertTrue(record.subtests.isEmpty)
    }

    // MARK: - runIf

    func testSubtestRunIfFalseSkipsEntirely() async {
        let plan = TestPlan(name: "runif") {
            Subtest("S", runIf: { _ in false }) {
                Phase(name: "p1") { _ in .continue }
            }
        }
        let record = await TestExecutor(plan: plan).execute()
        XCTAssertTrue(record.phases.isEmpty, "runIf=false 整 subtest 不应跑任何 phase")
        XCTAssertEqual(record.subtests.count, 1)
        XCTAssertEqual(record.subtests[0].outcome, .skip)
        XCTAssertEqual(record.subtests[0].failureReason, "runIf=false")
        XCTAssertEqual(record.outcome, .pass)
    }

    // MARK: - 嵌套

    func testNestedSubtestIsolation() async throws {
        // 内层 subtest fail，外层 subtest 仍 .pass
        let plan = TestPlan(name: "nest") {
            Subtest("Outer") {
                Phase(name: "outer1") { _ in .continue }
                Subtest("Inner") {
                    Phase(name: "innerBoom") { _ in .failAndContinue }
                }
                Phase(name: "outer2") { _ in .continue }
            }
        }
        let record = await TestExecutor(plan: plan).execute()
        XCTAssertEqual(record.outcome, .pass)
        XCTAssertEqual(record.subtests.count, 2)
        let outer = try XCTUnwrap(record.subtests.first { $0.name == "Outer" })
        let inner = try XCTUnwrap(record.subtests.first { $0.name == "Inner" })
        XCTAssertEqual(inner.outcome, .fail)
        XCTAssertEqual(outer.outcome, .pass, "内层 subtest fail 不应让外层 subtest fail")
        // outer2 应执行（内层 subtest 隔离失败）
        XCTAssertTrue(record.phases.contains { $0.name == "outer2" })
        // innerBoom 的 groupPath
        let innerBoom = try XCTUnwrap(record.phases.first { $0.name == "innerBoom" })
        XCTAssertEqual(innerBoom.groupPath, ["Outer", "Inner"])
    }

    func testGroupInsideSubtestFailShortCircuits() async {
        let plan = TestPlan(name: "g_in_s") {
            Subtest("S") {
                Group("G") {
                    Phase(name: "g1") { _ in .failAndContinue }
                }
                Phase(name: "after") { _ in .continue }
            }
        }
        let record = await TestExecutor(plan: plan).execute()
        // Group fail → subtest 短路：after 不应跑
        XCTAssertFalse(record.phases.contains { $0.name == "after" })
        XCTAssertEqual(record.subtests[0].outcome, .fail)
        XCTAssertEqual(record.subtests[0].failureReason, "Group G failed")
    }

    // MARK: - .stop 冒泡

    func testStopInsideSubtestPropagates() async {
        let plan = TestPlan(name: "stop") {
            Subtest("S") {
                Phase(name: "p1") { _ in .stop }
                Phase(name: "p2") { _ in .continue }
            }
            Phase(name: "after") { _ in .continue }
        }
        let record = await TestExecutor(plan: plan).execute()
        // .stop 在 PhaseExecutor 内仍标 outcome=.error
        XCTAssertEqual(record.phases.count, 1)
        XCTAssertEqual(record.phases[0].name, "p1")
        XCTAssertEqual(record.phases[0].outcome, .error)
        // after 不应执行（.stop 冒泡终止整测试）
        XCTAssertFalse(record.phases.contains { $0.name == "after" })
    }

    // MARK: - phase 内 runIf

    func testPhaseRunIfInsideSubtest() async throws {
        let plan = TestPlan(name: "p_runif") {
            Subtest("S") {
                Phase(name: "skipped", runIf: { _ in false }) { _ in .continue }
                Phase(name: "ran") { _ in .continue }
            }
        }
        let record = await TestExecutor(plan: plan).execute()
        let skipped = try XCTUnwrap(record.phases.first { $0.name == "skipped" })
        XCTAssertEqual(skipped.outcome, .skip)
        XCTAssertTrue(record.phases.contains { $0.name == "ran" })
        XCTAssertEqual(record.subtests[0].outcome, .pass)
        XCTAssertEqual(record.subtests[0].phaseIDs.count, 2)
    }

    // MARK: - Codable

    func testTestRecordCodableRoundTrip() async throws {
        let plan = TestPlan(name: "codec") {
            Subtest("S") {
                Phase(name: "p1") { _ in .continue }
                Phase(name: "p2") { _ in .failAndContinue }
            }
        }
        let record = await TestExecutor(plan: plan).execute()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(record)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(TestRecord.self, from: data)
        XCTAssertEqual(decoded.subtests.count, 1)
        XCTAssertEqual(decoded.subtests[0].outcome, .fail)
        XCTAssertEqual(decoded.subtests[0].phaseIDs, record.subtests[0].phaseIDs)
        XCTAssertEqual(decoded.phases.map(\.subtestFailRequested), record.phases.map(\.subtestFailRequested))
    }

    // MARK: - phaseID 链接

    func testSubtestPhaseIDsMatchRecordPhases() async throws {
        let plan = TestPlan(name: "ids") {
            Phase(name: "before") { _ in .continue }
            Subtest("S") {
                Phase(name: "p1") { _ in .continue }
                Phase(name: "p2") { _ in .continue }
            }
            Phase(name: "after") { _ in .continue }
        }
        let record = await TestExecutor(plan: plan).execute()
        let st = record.subtests[0]
        let p1 = try XCTUnwrap(record.phases.first { $0.name == "p1" })
        let p2 = try XCTUnwrap(record.phases.first { $0.name == "p2" })
        XCTAssertEqual(st.phaseIDs, [p1.id, p2.id])
        // before / after 不应在 subtest.phaseIDs 内
        let outsideIDs = record.phases.filter { ["before", "after"].contains($0.name) }.map(\.id)
        XCTAssertTrue(st.phaseIDs.allSatisfy { !outsideIDs.contains($0) })
    }

    // MARK: - SubtestRecord 中间字段：duration

    func testSubtestRecordDuration() async {
        let plan = TestPlan(name: "dur") {
            Subtest("S") {
                Phase(name: "p") { _ in .continue }
            }
        }
        let record = await TestExecutor(plan: plan).execute()
        let st = record.subtests[0]
        XCTAssertNotNil(st.endTime)
        XCTAssertGreaterThanOrEqual(st.duration, 0)
    }

    // MARK: - DSL 节点结构

    func testTestPlanNodesContainSubtest() {
        let plan = TestPlan(name: "dsl") {
            Phase(name: "top") { _ in .continue }
            Subtest("S") {
                Phase(name: "inner") { _ in .continue }
            }
        }
        XCTAssertEqual(plan.nodes.count, 2)
        XCTAssertNotNil(plan.nodes[1].asSubtest)
        XCTAssertEqual(plan.nodes[1].asSubtest?.name, "S")
        XCTAssertEqual(plan.nodes[1].asSubtest?.nodes.count, 1)
    }
}

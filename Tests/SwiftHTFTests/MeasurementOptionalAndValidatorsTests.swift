@testable import SwiftHTF
import XCTest

final class MeasurementOptionalAndValidatorsTests: XCTestCase {
    // MARK: - oneOf

    func testOneOfPassFail() {
        let v = OneOfValidator(allowed: [.string("A"), .string("B"), .string("C")])
        XCTAssertEqual(v.validate(.string("A")), .pass)
        XCTAssertEqual(v.validate(.string("B")), .pass)
        if case .pass = v.validate(.string("D")) { XCTFail("D 不在集合中") }
    }

    func testOneOfWithIntegersViaSpec() async {
        let plan = TestPlan(name: "p") {
            Phase(
                name: "k",
                measurements: [.named("grade").oneOf([1, 2, 3])]
            ) { ctx in
                ctx.measure("grade", 2)
                return .continue
            }
        }
        let record = await TestExecutor(plan: plan).execute()
        XCTAssertEqual(record.outcome, .pass)
        XCTAssertEqual(record.phases.first?.measurements["grade"]?.outcome, .pass)
    }

    func testOneOfMissFailsPhase() async {
        let plan = TestPlan(name: "p") {
            Phase(
                name: "k",
                measurements: [.named("color").oneOf(["red", "green", "blue"])]
            ) { ctx in
                ctx.measure("color", "yellow")
                return .continue
            }
        }
        let record = await TestExecutor(plan: plan).execute()
        XCTAssertEqual(record.outcome, .fail)
        XCTAssertEqual(record.phases.first?.measurements["color"]?.outcome, .fail)
    }

    // MARK: - lengthEquals (measurement)

    func testLengthEqualsString() {
        let v = LengthEqualsValidator(expected: 4)
        XCTAssertEqual(v.validate(.string("ABCD")), .pass)
        if case .pass = v.validate(.string("ABC")) { XCTFail() }
    }

    func testLengthEqualsArray() {
        let v = LengthEqualsValidator(expected: 3)
        XCTAssertEqual(v.validate(.array([.int(1), .int(2), .int(3)])), .pass)
        if case .pass = v.validate(.array([.int(1)])) { XCTFail() }
    }

    func testLengthEqualsRejectsNumeric() {
        let v = LengthEqualsValidator(expected: 3)
        if case .pass = v.validate(.int(3)) { XCTFail("数字无长度概念") }
    }

    // MARK: - setEquals

    func testSetEqualsIgnoresOrderAndDuplicates() {
        let v = SetEqualsValidator(expected: [.int(1), .int(2), .int(3)])
        XCTAssertEqual(v.validate(.array([.int(3), .int(1), .int(2)])), .pass)
        XCTAssertEqual(v.validate(.array([.int(2), .int(1), .int(3), .int(1)])), .pass)
        if case .pass = v.validate(.array([.int(1), .int(2)])) { XCTFail("缺 3") }
        if case .pass = v.validate(.array([.int(1), .int(2), .int(3), .int(4)])) { XCTFail("多 4") }
    }

    func testSetEqualsRejectsNonArray() {
        let v = SetEqualsValidator(expected: [.int(1)])
        if case .pass = v.validate(.int(1)) { XCTFail("值必须是数组") }
    }

    func testSetEqualsViaSpec() async {
        let plan = TestPlan(name: "p") {
            Phase(
                name: "k",
                measurements: [.named("tags").setEquals(["a", "b", "c"])]
            ) { ctx in
                ctx.measure("tags", ["c", "a", "b"])
                return .continue
            }
        }
        let record = await TestExecutor(plan: plan).execute()
        XCTAssertEqual(record.outcome, .pass)
    }

    // MARK: - SeriesSpec.lengthEquals

    func testSeriesLengthEqualsPass() async {
        let plan = TestPlan(name: "p") {
            Phase(
                name: "iv",
                series: [
                    .named("curve").dimension("v").value("i").lengthEquals(3),
                ]
            ) { ctx in
                await ctx.recordSeries("curve") { rec in
                    rec.append(0.0, 0.1)
                    rec.append(1.0, 0.2)
                    rec.append(2.0, 0.3)
                }
                return .continue
            }
        }
        let record = await TestExecutor(plan: plan).execute()
        XCTAssertEqual(record.outcome, .pass)
    }

    func testSeriesLengthEqualsFail() async {
        let plan = TestPlan(name: "p") {
            Phase(
                name: "iv",
                series: [
                    .named("curve").dimension("v").value("i").lengthEquals(5),
                ]
            ) { ctx in
                await ctx.recordSeries("curve") { rec in
                    rec.append(0.0, 0.1)
                    rec.append(1.0, 0.2)
                }
                return .continue
            }
        }
        let record = await TestExecutor(plan: plan).execute()
        XCTAssertEqual(record.outcome, .fail)
    }

    // MARK: - optional 语义

    func testRequiredMeasurementMissingFailsPhase() async {
        let plan = TestPlan(name: "p") {
            Phase(name: "k", measurements: [.named("vcc").inRange(3.0, 3.6)]) { _ in
                // 故意不调用 ctx.measure
                .continue
            }
        }
        let record = await TestExecutor(plan: plan).execute()
        XCTAssertEqual(record.outcome, .fail, "声明的 measurement 未记录 → phase fail")
        let m = record.phases.first?.measurements["vcc"]
        XCTAssertEqual(m?.outcome, .fail)
        XCTAssertTrue(m?.validatorMessages.first?.contains("missing") ?? false)
    }

    func testOptionalMeasurementMissingDoesNotFail() async {
        let plan = TestPlan(name: "p") {
            Phase(
                name: "k",
                measurements: [.named("vcc").inRange(3.0, 3.6).optional()]
            ) { _ in
                .continue
            }
        }
        let record = await TestExecutor(plan: plan).execute()
        XCTAssertEqual(record.outcome, .pass, "optional 缺测不算 fail")
        XCTAssertNil(record.phases.first?.measurements["vcc"], "缺测时不写占位")
    }

    func testOptionalMeasurementWhenRecordedStillValidates() async {
        let plan = TestPlan(name: "p") {
            Phase(
                name: "k",
                measurements: [.named("vcc").inRange(3.0, 3.6).optional()]
            ) { ctx in
                ctx.measure("vcc", 2.0)
                return .continue
            }
        }
        let record = await TestExecutor(plan: plan).execute()
        XCTAssertEqual(record.outcome, .fail, "optional 但已录入仍跑 validator")
    }

    func testRequiredSeriesMissingFailsPhase() async {
        let plan = TestPlan(name: "p") {
            Phase(
                name: "iv",
                series: [.named("curve").dimension("v").value("i").lengthAtLeast(1)]
            ) { _ in
                .continue
            }
        }
        let record = await TestExecutor(plan: plan).execute()
        XCTAssertEqual(record.outcome, .fail)
        XCTAssertEqual(record.phases.first?.traces["curve"]?.outcome, .fail)
    }

    func testOptionalSeriesMissingPasses() async {
        let plan = TestPlan(name: "p") {
            Phase(
                name: "iv",
                series: [
                    .named("curve").dimension("v").value("i").lengthAtLeast(1).optional(),
                ]
            ) { _ in
                .continue
            }
        }
        let record = await TestExecutor(plan: plan).execute()
        XCTAssertEqual(record.outcome, .pass)
    }
}

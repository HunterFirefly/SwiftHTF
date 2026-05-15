@testable import SwiftHTF
import XCTest

final class MeasurementTransformTests: XCTestCase {
    // MARK: - 基本 transform

    func testTransformAppliedBeforeValidator() async {
        // 原始 mV，spec 用 V 校验
        let plan = TestPlan(name: "p") {
            Phase(
                name: "k",
                measurements: [
                    .named("vcc", unit: "V")
                        .transform { raw in .double((raw.asDouble ?? 0) / 1000.0) }
                        .inRange(3.0, 3.6),
                ]
            ) { ctx in
                ctx.measure("vcc", 3300) // 3300 mV → 3.3 V，应 pass
                return .continue
            }
        }
        let record = await TestExecutor(plan: plan).execute()
        XCTAssertEqual(record.outcome, .pass)
        let m = record.phases.first?.measurements["vcc"]
        XCTAssertEqual(m?.value.asDouble, 3.3)
        XCTAssertEqual(m?.rawValue?.asInt, 3300, "原值保留在 rawValue")
    }

    func testTransformedValueFailsValidator() async {
        let plan = TestPlan(name: "p") {
            Phase(
                name: "k",
                measurements: [
                    .named("vcc")
                        .transform { raw in .double((raw.asDouble ?? 0) / 1000.0) }
                        .inRange(3.0, 3.6),
                ]
            ) { ctx in
                ctx.measure("vcc", 5000) // 5 V，超上限
                return .continue
            }
        }
        let record = await TestExecutor(plan: plan).execute()
        XCTAssertEqual(record.outcome, .fail)
        XCTAssertEqual(record.phases.first?.measurements["vcc"]?.rawValue?.asInt, 5000)
        XCTAssertEqual(record.phases.first?.measurements["vcc"]?.value.asDouble, 5.0)
    }

    func testNoTransformLeavesRawValueNil() async {
        let plan = TestPlan(name: "p") {
            Phase(
                name: "k",
                measurements: [.named("vcc").inRange(3.0, 3.6)]
            ) { ctx in
                ctx.measure("vcc", 3.3)
                return .continue
            }
        }
        let record = await TestExecutor(plan: plan).execute()
        let m = record.phases.first?.measurements["vcc"]
        XCTAssertEqual(m?.value.asDouble, 3.3)
        XCTAssertNil(m?.rawValue, "未配 transform 时 rawValue 为 nil")
    }

    // MARK: - 链式行为

    func testTransformOverwritesOnSecondCall() async {
        // 后者覆盖前者：×100 不会先 ×10 再 ×10
        let plan = TestPlan(name: "p") {
            Phase(
                name: "k",
                measurements: [
                    .named("x")
                        .transform { v in .double((v.asDouble ?? 0) * 10) }
                        .transform { v in .double((v.asDouble ?? 0) * 100) }
                        .inRange(0, 1000),
                ]
            ) { ctx in
                ctx.measure("x", 5) // 5 × 100 = 500
                return .continue
            }
        }
        let record = await TestExecutor(plan: plan).execute()
        let m = record.phases.first?.measurements["x"]
        XCTAssertEqual(m?.value.asDouble, 500)
        XCTAssertEqual(m?.rawValue?.asInt, 5)
    }

    func testTransformPreservedAcrossWith() async {
        // .transform 后再链 .inRange 不应丢失 transform
        let plan = TestPlan(name: "p") {
            Phase(
                name: "k",
                measurements: [
                    .named("x")
                        .transform { v in .double((v.asDouble ?? 0) - 1) }
                        .inRange(0, 5)
                        .marginalRange(1, 4),
                ]
            ) { ctx in
                ctx.measure("x", 3) // 3 - 1 = 2 → pass + marginal range 1..4 OK → pass
                return .continue
            }
        }
        let record = await TestExecutor(plan: plan).execute()
        XCTAssertEqual(record.outcome, .pass)
        XCTAssertEqual(record.phases.first?.measurements["x"]?.value.asDouble, 2)
        XCTAssertEqual(record.phases.first?.measurements["x"]?.rawValue?.asInt, 3)
    }

    // MARK: - Codable 兼容

    func testRoundTripWithRawValue() throws {
        let m = SwiftHTF.Measurement(
            name: "vcc",
            value: .double(3.3),
            rawValue: .int(3300),
            unit: "V"
        )
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .secondsSince1970
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .secondsSince1970
        let data = try enc.encode(m)
        let decoded = try dec.decode(SwiftHTF.Measurement.self, from: data)
        XCTAssertEqual(decoded.value.asDouble, 3.3)
        XCTAssertEqual(decoded.rawValue?.asInt, 3300)
    }

    func testDecodesOldJSONWithoutRawValue() throws {
        let oldJSON = """
        {
          "name": "vcc",
          "value": 3.3,
          "unit": "V",
          "timestamp": 1715760000,
          "outcome": "PASS",
          "validatorMessages": []
        }
        """
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .secondsSince1970
        let m = try dec.decode(SwiftHTF.Measurement.self, from: Data(oldJSON.utf8))
        XCTAssertEqual(m.value.asDouble, 3.3)
        XCTAssertNil(m.rawValue)
    }
}

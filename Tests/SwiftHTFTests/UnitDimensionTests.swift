@testable import SwiftHTF
import XCTest

/// `PhysicalUnit` / `UnitRegistry` / `MeasurementSpec.units(_:)` 维度校验。
final class UnitDimensionTests: XCTestCase {
    // MARK: - UnitRegistry：内置反查 + 自定义注册

    func testRegistryResolvesBuiltinUnits() {
        let reg = UnitRegistry.default
        XCTAssertEqual(reg.unit(named: "V")?.dimension, .voltage)
        XCTAssertEqual(reg.unit(named: "mV")?.dimension, .voltage)
        XCTAssertEqual(reg.unit(named: "A")?.dimension, .current)
        XCTAssertEqual(reg.unit(named: "Hz")?.dimension, .frequency)
        XCTAssertEqual(reg.unit(named: "°C")?.dimension, .temperature)
        XCTAssertEqual(reg.unit(named: "Ω")?.dimension, .resistance)
    }

    func testRegistryUnknownReturnsNil() {
        XCTAssertNil(UnitRegistry.default.unit(named: "fnord"))
    }

    func testRegistryAcceptsCustomUnit() {
        let reg = UnitRegistry(builtins: false)
        let lux = Unit(name: "lx", dimension: .custom("illuminance"))
        reg.register(lux)
        XCTAssertEqual(reg.unit(named: "lx"), lux)
        // 未注册的查询仍 nil
        XCTAssertNil(reg.unit(named: "V"))
    }

    // MARK: - Custom dimension 按 name 相等判定

    func testCustomDimensionEqualityByName() {
        let a = PhysicalDimension.custom("X")
        let b = PhysicalDimension.custom("X")
        let c = PhysicalDimension.custom("Y")
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
        XCTAssertNotEqual(a, .voltage)
    }

    // MARK: - MeasurementSpec.units 派生 unit name

    func testUnitsDerivesUnitName() {
        let spec = MeasurementSpec.named("vcc").units(.volt)
        XCTAssertEqual(spec.unit, "V")
        XCTAssertEqual(spec.unitObject, .volt)
    }

    // MARK: - 维度匹配：写入与 spec 同维度 → pass（含 SI 前缀互通）

    func testSameDimensionPasses() async {
        let plan = TestPlan(name: "u-ok") {
            Phase(
                name: "vcheck",
                measurements: [
                    .named("vcc").units(.volt).inRange(3.0, 3.6),
                ]
            ) { ctx in
                // 写入用 mV，与 spec 的 V 同 dimension=voltage → 不报维度错；
                // value 仍按 ctx.measure 入参原样保留（用户若需 mV→V 用 transform）
                ctx.measure("vcc", 3.3, unit: "mV")
                return .continue
            }
        }
        let record = await TestExecutor(plan: plan).execute()
        // 维度 OK；但因为 inRange(3.0, 3.6) 跑在 mV 原值 3.3 上 pass（数值层面恰好通过）
        let m = record.phases[0].measurements["vcc"]
        XCTAssertEqual(m?.outcome, .pass)
        XCTAssertFalse(m?.validatorMessages.contains(where: { $0.contains("unit_dimension") }) ?? false)
    }

    // MARK: - 维度不匹配：spec=V 写入="A" → outcome=.fail

    func testWrongDimensionFails() async {
        let plan = TestPlan(name: "u-mismatch") {
            Phase(
                name: "vcheck",
                measurements: [
                    .named("vcc").units(.volt).inRange(3.0, 3.6),
                ]
            ) { ctx in
                ctx.measure("vcc", 3.3, unit: "A")
                return .continue
            }
        }
        let record = await TestExecutor(plan: plan).execute()
        XCTAssertEqual(record.outcome, .fail)
        let m = record.phases[0].measurements["vcc"]
        XCTAssertEqual(m?.outcome, .fail)
        let hasDimMsg = m?.validatorMessages.contains { $0.contains("unit_dimension") } ?? false
        XCTAssertTrue(hasDimMsg, "应有 unit_dimension 错误信息：\(m?.validatorMessages ?? [])")
    }

    // MARK: - measurement 没传 unit 时不强制校验

    func testNoMeasurementUnitSkipsCheck() async {
        let plan = TestPlan(name: "u-no-unit") {
            Phase(
                name: "v",
                measurements: [
                    .named("vcc").units(.volt).inRange(3.0, 3.6),
                ]
            ) { ctx in
                ctx.measure("vcc", 3.3) // 没传 unit
                return .continue
            }
        }
        let record = await TestExecutor(plan: plan).execute()
        let m = record.phases[0].measurements["vcc"]
        XCTAssertEqual(m?.outcome, .pass)
        XCTAssertFalse(m?.validatorMessages.contains(where: { $0.contains("unit_dimension") }) ?? false)
    }

    // MARK: - 自定义单位（未在 registry 注册）跳过校验

    func testUnregisteredUnitStringSkipsCheck() async {
        let plan = TestPlan(name: "u-unknown") {
            Phase(
                name: "v",
                measurements: [
                    .named("vcc").units(.volt).inRange(3.0, 3.6),
                ]
            ) { ctx in
                ctx.measure("vcc", 3.3, unit: "weirdo")
                return .continue
            }
        }
        let record = await TestExecutor(plan: plan).execute()
        let m = record.phases[0].measurements["vcc"]
        // 未注册 unit 不强制校验；3.3 在 [3.0, 3.6] 内 → pass
        XCTAssertEqual(m?.outcome, .pass)
    }

    // MARK: - spec 没声明 units 时不校验

    func testSpecWithoutUnitsSkipsCheck() async {
        let plan = TestPlan(name: "u-no-spec") {
            Phase(
                name: "v",
                measurements: [
                    .named("vcc").inRange(3.0, 3.6),
                ]
            ) { ctx in
                // 用了乱七八糟的 unit 字符串：没声明 .units() 时不校验
                ctx.measure("vcc", 3.3, unit: "A")
                return .continue
            }
        }
        let record = await TestExecutor(plan: plan).execute()
        let m = record.phases[0].measurements["vcc"]
        XCTAssertEqual(m?.outcome, .pass)
    }

    // MARK: - 维度校验与 transform 同时存在：transform 不影响 unit 校验

    func testDimensionCheckWorksWithTransform() async {
        let plan = TestPlan(name: "u-transform") {
            Phase(
                name: "v",
                measurements: [
                    .named("vcc")
                        .units(.volt)
                        .transform { raw in .double((raw.asDouble ?? 0) / 1000) } // mV → V
                        .inRange(3.0, 3.6),
                ]
            ) { ctx in
                ctx.measure("vcc", 3300, unit: "mV")
                return .continue
            }
        }
        let record = await TestExecutor(plan: plan).execute()
        let m = record.phases[0].measurements["vcc"]
        XCTAssertEqual(m?.outcome, .pass)
        // value 经 transform 后是 3.3
        XCTAssertEqual(m?.value.asDouble, 3.3)
        // rawValue 保留原 3300
        XCTAssertEqual(m?.rawValue?.asDouble, 3300)
    }

    // MARK: - 维度错配 + 数值通过：仍 fail（维度优先级最高）

    func testDimensionFailsEvenIfValuePasses() async {
        let plan = TestPlan(name: "u-strict") {
            Phase(
                name: "f",
                measurements: [
                    .named("freq").units(.hertz).inRange(0, 1_000_000),
                ]
            ) { ctx in
                // 1000 数值在 [0, 1_000_000] 内、validators pass；但 unit=ms 维度是 time
                ctx.measure("freq", 1000, unit: "ms")
                return .continue
            }
        }
        let record = await TestExecutor(plan: plan).execute()
        let m = record.phases[0].measurements["freq"]
        XCTAssertEqual(m?.outcome, .fail)
        XCTAssertTrue(m?.validatorMessages.contains(where: { $0.contains("unit_dimension") }) ?? false)
    }

    // MARK: - MeasurementSpec Codable 兼容（unitObject 不入 Codable，spec 不强求序列化）

    func testSpecConstructionRoundTrip() {
        let spec1 = MeasurementSpec.named("v").units(.volt).inRange(3.0, 3.6)
        let spec2 = spec1.optional()
        // optional() 不应丢失 unitObject
        XCTAssertEqual(spec2.unitObject, .volt)
        XCTAssertEqual(spec2.unit, "V")
        XCTAssertTrue(spec2.isOptional)
    }
}

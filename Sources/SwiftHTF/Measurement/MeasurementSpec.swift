import Foundation

// MARK: - 协议

/// 作用在 `AnyCodableValue` 上的 measurement 验证器。
///
/// 由 `MeasurementSpec` 链式 builder 装配，phase harvest 阶段对 `ctx.measure(...)`
/// 写入的同名 measurement 跑全套校验，聚合为 pass / marginal / fail 三态。
public protocol MeasurementValidator: Sendable {
    /// 校验单个值
    func validate(_ value: AnyCodableValue) -> MeasurementValidationResult

    /// 用于诊断输出的简短标签（如 "in_range[3.0, 3.6]"）
    var label: String { get }
}

/// Measurement 校验结果
public enum MeasurementValidationResult: Sendable, Equatable {
    case pass
    /// 在硬限值内但接近边界 — 警告但放行
    case marginal(String)
    case fail(String)
}

// MARK: - 声明式 measurement 规约

/// 测量规约：声明一条 measurement 的元数据 + validator 链
///
/// ```swift
/// Phase(
///     name: "VccCheck",
///     measurements: [
///         .named("vcc", unit: "V").inRange(3.0, 3.6)
///     ]
/// ) { @MainActor ctx in
///     ctx.measure("vcc", 3.32, unit: "V")
///     return .continue
/// }
/// ```
public struct MeasurementSpec: Sendable {
    public let name: String
    public let unit: String?
    /// 带物理维度的单位声明（OpenHTF `with_units(...)` 等价）。
    ///
    /// - 与 `unit: String?` 平行：`unitObject != nil` 时 `unit` 字段派生自 `unitObject.name`
    /// - harvest 时若 measurement.unit 字符串在 `UnitRegistry.default` 能反查到 Unit，
    ///   且该 Unit 的 dimension 与 `unitObject.dimension` 不符 → outcome=.fail
    /// - measurement.unit 为 nil 或字符串不在 registry → 跳过维度校验（视为自定义单位）
    public let unitObject: Unit?
    public let description: String?
    public let validators: [any MeasurementValidator]
    /// `true` 表示 phase 内未调用 `ctx.measure(name, ...)` 也不算 fail（OpenHTF `is_optional`）；
    /// 默认 `false`：声明即必需，缺测会让 phase outcome 降级为 `.fail`。
    public let isOptional: Bool
    /// 可选 pre-validate 处理：在跑 validators 之前把原始值转换为物理量。
    /// 配置后，harvest 用 transform 结果替换 `Measurement.value`，原值保留在
    /// `Measurement.rawValue` 供 BI / 审计读取。
    /// 对齐 OpenHTF `with_args(transform_fn=…)`，常用于单位换算（mV→V）/ ADC 线性化。
    public let transform: (@Sendable (AnyCodableValue) -> AnyCodableValue)?

    public init(
        name: String,
        unit: String? = nil,
        unitObject: Unit? = nil,
        description: String? = nil,
        validators: [any MeasurementValidator] = [],
        isOptional: Bool = false,
        transform: (@Sendable (AnyCodableValue) -> AnyCodableValue)? = nil
    ) {
        self.name = name
        // unitObject 非 nil 时优先派生 unit name；显式 unit 参数仅在 unitObject=nil 时生效
        self.unit = unitObject?.name ?? unit
        self.unitObject = unitObject
        self.description = description
        self.validators = validators
        self.isOptional = isOptional
        self.transform = transform
    }

    /// 工厂入口
    public static func named(
        _ name: String,
        unit: String? = nil,
        description: String? = nil
    ) -> MeasurementSpec {
        MeasurementSpec(name: name, unit: unit, description: description)
    }

    /// 追加任意 validator，返回新 spec（值语义）
    public func with(_ validator: any MeasurementValidator) -> MeasurementSpec {
        MeasurementSpec(
            name: name,
            unit: unit,
            unitObject: unitObject,
            description: description,
            validators: validators + [validator],
            isOptional: isOptional,
            transform: transform
        )
    }

    /// 标记为可选：未记录值时不进 phase outcome 聚合；记录后仍按 validator 链校验。
    public func optional() -> MeasurementSpec {
        MeasurementSpec(
            name: name,
            unit: unit,
            unitObject: unitObject,
            description: description,
            validators: validators,
            isOptional: true,
            transform: transform
        )
    }

    /// 配置 pre-validate 转换：把原始 ctx.measure 值映射成物理量后再跑 validator。
    /// 多次调用：后者覆盖前者（保持调用链可读，不做隐式 compose）。
    /// ```swift
    /// .named("vcc", unit: "V")
    ///     .transform { raw in .double((raw.asDouble ?? 0) / 1000) } // mV → V
    ///     .inRange(3.0, 3.6)
    /// ```
    public func transform(
        _ block: @escaping @Sendable (AnyCodableValue) -> AnyCodableValue
    ) -> MeasurementSpec {
        MeasurementSpec(
            name: name,
            unit: unit,
            unitObject: unitObject,
            description: description,
            validators: validators,
            isOptional: isOptional,
            transform: block
        )
    }

    /// 声明带维度的单位（OpenHTF `with_units(units.VOLT)` 等价）。
    /// 设置后 `unit` 字段派生自 `Unit.name`；harvest 阶段对 measurement.unit 做维度校验。
    /// ```swift
    /// .named("vcc").units(.volt).inRange(3.0, 3.6)
    /// ```
    public func units(_ unit: Unit) -> MeasurementSpec {
        MeasurementSpec(
            name: name,
            unit: nil,
            unitObject: unit,
            description: description,
            validators: validators,
            isOptional: isOptional,
            transform: transform
        )
    }

    /// 跑全部 validator 聚合三态判定
    /// - Returns: 三态 verdict + 触发的所有消息
    func run(on value: AnyCodableValue) -> (verdict: Verdict, messages: [String]) {
        var messages: [String] = []
        var failed = false
        var marginal = false
        for v in validators {
            switch v.validate(value) {
            case .pass: break
            case let .marginal(msg):
                marginal = true
                messages.append(msg)
            case let .fail(msg):
                failed = true
                messages.append(msg)
            }
        }
        if failed { return (.fail, messages) }
        if marginal { return (.marginal, messages) }
        return (.pass, messages)
    }

    /// 三态 spec 判定（fail 优先级最高 → marginal → pass）
    enum Verdict {
        case pass
        case marginal
        case fail
    }
}

// MARK: - 链式 builder（内置 validator）

public extension MeasurementSpec {
    /// 数值落在 [lower, upper]（默认闭区间）
    func inRange(_ lower: Double, _ upper: Double, inclusive: Bool = true) -> MeasurementSpec {
        with(InRangeValidator(lower: lower, upper: upper, inclusive: inclusive))
    }

    /// 仅下限
    func atLeast(_ lower: Double, inclusive: Bool = true) -> MeasurementSpec {
        with(InRangeValidator(lower: lower, upper: nil, inclusive: inclusive))
    }

    /// 仅上限
    func atMost(_ upper: Double, inclusive: Bool = true) -> MeasurementSpec {
        with(InRangeValidator(lower: nil, upper: upper, inclusive: inclusive))
    }

    /// 等于某 Encodable 值
    func equals(_ expected: some Encodable) -> MeasurementSpec {
        with(EqualsValueValidator(expected: AnyCodableValue.from(expected)))
    }

    /// 字符串值匹配正则
    func matchesRegex(_ pattern: String) -> MeasurementSpec {
        with(RegexMeasurementValidator(pattern: pattern))
    }

    /// 数值在 target 的 ±percent% 范围内
    func withinPercent(of target: Double, percent: Double) -> MeasurementSpec {
        with(WithinPercentValidator(target: target, percent: percent))
    }

    /// 字符串 / 数组 / 对象非空（忽略前后空白）
    func notEmpty() -> MeasurementSpec {
        with(NotEmptyMeasurementValidator())
    }

    /// 值必须命中给定集合（OpenHTF `oneOf`）。任意 Encodable 项内部归一化为 AnyCodableValue。
    func oneOf(_ values: [some Encodable]) -> MeasurementSpec {
        with(OneOfValidator(allowed: values.map { AnyCodableValue.from($0) }))
    }

    /// 值长度等于 N：作用于 `.string`（字符数）/ `.array`（元素数）/ `.object`（键数）。
    func lengthEquals(_ n: Int) -> MeasurementSpec {
        with(LengthEqualsValidator(expected: n))
    }

    /// 值（必须是 array）按集合相等：忽略顺序与重复，与给定集合一一对应（OpenHTF `set_equals`）。
    func setEquals(_ values: [some Encodable]) -> MeasurementSpec {
        with(SetEqualsValidator(expected: values.map { AnyCodableValue.from($0) }))
    }

    /// 数值在 [lower, upper] 内为 pass，否则报 marginal（不算 fail）。
    /// 与 `inRange` 配合使用：硬限值用 `inRange`，警告带用 `marginalRange`。
    /// ```swift
    /// .named("vcc").inRange(3.0, 3.6).marginalRange(3.1, 3.5)
    /// ```
    func marginalRange(_ lower: Double, _ upper: Double) -> MeasurementSpec {
        with(MarginalRangeValidator(lower: lower, upper: upper))
    }

    /// 自定义闭包
    func custom(
        label: String,
        _ block: @escaping @Sendable (AnyCodableValue) -> MeasurementValidationResult
    ) -> MeasurementSpec {
        with(CustomMeasurementValidator(label: label, block: block))
    }
}

// MARK: - 内置 validator 实现

/// 数值范围（lower / upper 任选；inclusive 控端点是否包含）
public struct InRangeValidator: MeasurementValidator {
    public let lower: Double?
    public let upper: Double?
    public let inclusive: Bool

    public init(lower: Double?, upper: Double?, inclusive: Bool = true) {
        self.lower = lower
        self.upper = upper
        self.inclusive = inclusive
    }

    public func validate(_ value: AnyCodableValue) -> MeasurementValidationResult {
        guard let n = value.asDouble else {
            return .fail("\(label): 值非数字 (\(value.displayString))")
        }
        if let lower {
            let ok = inclusive ? n >= lower : n > lower
            if !ok { return .fail("\(label): \(n) < \(lower)") }
        }
        if let upper {
            let ok = inclusive ? n <= upper : n < upper
            if !ok { return .fail("\(label): \(n) > \(upper)") }
        }
        return .pass
    }

    public var label: String {
        let lo = lower.map { String($0) } ?? "-∞"
        let hi = upper.map { String($0) } ?? "+∞"
        return inclusive ? "in_range[\(lo), \(hi)]" : "in_range(\(lo), \(hi))"
    }
}

/// 值相等（按 AnyCodableValue.Equatable）
public struct EqualsValueValidator: MeasurementValidator {
    public let expected: AnyCodableValue

    public init(expected: AnyCodableValue) {
        self.expected = expected
    }

    public func validate(_ value: AnyCodableValue) -> MeasurementValidationResult {
        if value == expected { return .pass }
        return .fail("\(label): 实际 \(value.displayString)")
    }

    public var label: String {
        "equals(\(expected.displayString))"
    }
}

/// 正则匹配（仅作用在 string 值）
public struct RegexMeasurementValidator: MeasurementValidator {
    public let pattern: String

    public init(pattern: String) {
        self.pattern = pattern
    }

    public func validate(_ value: AnyCodableValue) -> MeasurementValidationResult {
        guard let s = value.asString else {
            return .fail("\(label): 非字符串值")
        }
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return .fail("\(label): 无效正则")
        }
        let range = NSRange(s.startIndex..., in: s)
        if regex.firstMatch(in: s, range: range) != nil {
            return .pass
        }
        return .fail("\(label): \"\(s)\" 不匹配")
    }

    public var label: String {
        "regex(\(pattern))"
    }
}

/// 数值在 target 的 ±percent% 容差内（percent 用百分号原值，例如 5 表示 ±5%）
public struct WithinPercentValidator: MeasurementValidator {
    public let target: Double
    public let percent: Double

    public init(target: Double, percent: Double) {
        self.target = target
        self.percent = percent
    }

    public func validate(_ value: AnyCodableValue) -> MeasurementValidationResult {
        guard let n = value.asDouble else {
            return .fail("\(label): 非数字")
        }
        let tolerance = abs(target) * (percent / 100.0)
        if abs(n - target) <= tolerance { return .pass }
        return .fail("\(label): 实际 \(n) 偏离 \(target) 超过 ±\(percent)%")
    }

    public var label: String {
        "within_percent(\(target), ±\(percent)%)"
    }
}

/// Marginal 范围：值落在 [lower, upper] 内为 pass，否则报 .marginal。
/// 不发 fail —— 硬限值由 `InRangeValidator` 保证；这里只产生警告状态。
public struct MarginalRangeValidator: MeasurementValidator {
    public let lower: Double
    public let upper: Double

    public init(lower: Double, upper: Double) {
        self.lower = lower
        self.upper = upper
    }

    public func validate(_ value: AnyCodableValue) -> MeasurementValidationResult {
        guard let n = value.asDouble else {
            // 非数字交给其他 validator 处理；这里不强加 fail
            return .pass
        }
        if n < lower {
            return .marginal("\(label): \(n) 接近下限 \(lower)")
        }
        if n > upper {
            return .marginal("\(label): \(n) 接近上限 \(upper)")
        }
        return .pass
    }

    public var label: String {
        "marginal_range[\(lower), \(upper)]"
    }
}

/// 非空：string trim 非空 / array 非空 / object 非空 / null 视为空
public struct NotEmptyMeasurementValidator: MeasurementValidator {
    public init() {}

    public func validate(_ value: AnyCodableValue) -> MeasurementValidationResult {
        switch value {
        case .null:
            return .fail("\(label): null")
        case let .string(s):
            if s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return .fail("\(label): 空字符串")
            }
            return .pass
        case let .array(a):
            return a.isEmpty ? .fail("\(label): 空数组") : .pass
        case let .object(o):
            return o.isEmpty ? .fail("\(label): 空对象") : .pass
        case .bool, .int, .double:
            return .pass
        }
    }

    public var label: String {
        "not_empty"
    }
}

/// 自定义闭包
public struct CustomMeasurementValidator: MeasurementValidator {
    public let label: String
    let block: @Sendable (AnyCodableValue) -> MeasurementValidationResult

    public init(
        label: String,
        block: @escaping @Sendable (AnyCodableValue) -> MeasurementValidationResult
    ) {
        self.label = label
        self.block = block
    }

    public func validate(_ value: AnyCodableValue) -> MeasurementValidationResult {
        block(value)
    }
}

/// 集合命中：value ∈ allowed
public struct OneOfValidator: MeasurementValidator {
    public let allowed: [AnyCodableValue]

    public init(allowed: [AnyCodableValue]) {
        self.allowed = allowed
    }

    public func validate(_ value: AnyCodableValue) -> MeasurementValidationResult {
        if allowed.contains(value) { return .pass }
        return .fail("\(label): 实际 \(value.displayString)")
    }

    public var label: String {
        "one_of[\(allowed.map(\.displayString).joined(separator: ", "))]"
    }
}

/// 长度相等：作用于 string / array / object
public struct LengthEqualsValidator: MeasurementValidator {
    public let expected: Int

    public init(expected: Int) {
        self.expected = expected
    }

    public func validate(_ value: AnyCodableValue) -> MeasurementValidationResult {
        let actual: Int? = switch value {
        case let .string(s): s.count
        case let .array(a): a.count
        case let .object(o): o.count
        case .null, .bool, .int, .double: nil
        }
        guard let actual else {
            return .fail("\(label): 值类型不支持长度（\(value.displayString)）")
        }
        if actual == expected { return .pass }
        return .fail("\(label): 实际长度 \(actual)")
    }

    public var label: String {
        "length==\(expected)"
    }
}

/// 集合相等（数组当集合比，忽略顺序与重复）
public struct SetEqualsValidator: MeasurementValidator {
    public let expected: [AnyCodableValue]

    public init(expected: [AnyCodableValue]) {
        self.expected = expected
    }

    public func validate(_ value: AnyCodableValue) -> MeasurementValidationResult {
        guard case let .array(arr) = value else {
            return .fail("\(label): 值非数组（\(value.displayString)）")
        }
        // AnyCodableValue 未 Hashable，用 O(n²) 包含判断；测量集合通常很小
        let allInActual = expected.allSatisfy { e in arr.contains(e) }
        let allInExpected = arr.allSatisfy { a in expected.contains(a) }
        if allInActual, allInExpected { return .pass }
        return .fail("\(label): 实际 [\(arr.map(\.displayString).joined(separator: ", "))]")
    }

    public var label: String {
        "set_equals[\(expected.map(\.displayString).joined(separator: ", "))]"
    }
}

import Foundation

/// 单点测量结果
///
/// 由 `ctx.measure(name:_:unit:)` 写入；harvest 阶段按 phase 上的
/// `MeasurementSpec` 跑 validator 后写回 `outcome` / `validatorMessages`。
/// 多维序列测量（IV 曲线、扫频等）改用 `SeriesMeasurement`。
public struct Measurement: Sendable, Codable {
    public let name: String
    /// 当前值（经 spec transform 处理后；未配 transform 时即原始 ctx.measure 入参）
    public var value: AnyCodableValue
    /// transform 前的原始值。仅当 spec 配了 `.transform { ... }` 时存在；
    /// 用于 BI / 审计回放原始 ADC 读数等场景。旧 JSON 不含此字段时解码为 nil。
    public var rawValue: AnyCodableValue?
    public var unit: String?
    public var timestamp: Date
    public var outcome: PhaseOutcomeType
    public var validatorMessages: [String]

    public init(
        name: String,
        value: AnyCodableValue,
        rawValue: AnyCodableValue? = nil,
        unit: String? = nil,
        timestamp: Date = Date(),
        outcome: PhaseOutcomeType = .pass,
        validatorMessages: [String] = []
    ) {
        self.name = name
        self.value = value
        self.rawValue = rawValue
        self.unit = unit
        self.timestamp = timestamp
        self.outcome = outcome
        self.validatorMessages = validatorMessages
    }

    /// 显式 Codable：兼容旧 JSON（无 rawValue 字段）
    private enum CodingKeys: String, CodingKey {
        case name, value, rawValue, unit, timestamp, outcome, validatorMessages
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        value = try c.decode(AnyCodableValue.self, forKey: .value)
        rawValue = try c.decodeIfPresent(AnyCodableValue.self, forKey: .rawValue)
        unit = try c.decodeIfPresent(String.self, forKey: .unit)
        timestamp = try c.decode(Date.self, forKey: .timestamp)
        outcome = try c.decode(PhaseOutcomeType.self, forKey: .outcome)
        validatorMessages = try c.decodeIfPresent([String].self, forKey: .validatorMessages) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(name, forKey: .name)
        try c.encode(value, forKey: .value)
        try c.encodeIfPresent(rawValue, forKey: .rawValue)
        try c.encodeIfPresent(unit, forKey: .unit)
        try c.encode(timestamp, forKey: .timestamp)
        try c.encode(outcome, forKey: .outcome)
        try c.encode(validatorMessages, forKey: .validatorMessages)
    }
}

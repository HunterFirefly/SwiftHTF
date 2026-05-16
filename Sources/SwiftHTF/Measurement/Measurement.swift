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
    /// 用于 BI / 审计回放原始 ADC 读数等场景。
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
}

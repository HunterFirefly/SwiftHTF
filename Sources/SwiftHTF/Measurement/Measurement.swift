import Foundation

/// 单点测量结果
///
/// 由 `ctx.measure(name:_:unit:)` 写入；harvest 阶段按 phase 上的
/// `MeasurementSpec` 跑 validator 后写回 `outcome` / `validatorMessages`。
/// 多维序列测量（IV 曲线、扫频等）改用 `SeriesMeasurement`。
public struct Measurement: Sendable, Codable {
    public let name: String
    public var value: AnyCodableValue
    public var unit: String?
    public var timestamp: Date
    public var outcome: PhaseOutcomeType
    public var validatorMessages: [String]

    public init(
        name: String,
        value: AnyCodableValue,
        unit: String? = nil,
        timestamp: Date = Date(),
        outcome: PhaseOutcomeType = .pass,
        validatorMessages: [String] = []
    ) {
        self.name = name
        self.value = value
        self.unit = unit
        self.timestamp = timestamp
        self.outcome = outcome
        self.validatorMessages = validatorMessages
    }
}

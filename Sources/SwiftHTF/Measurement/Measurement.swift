import Foundation

/// 测量结果
///
/// 替代 Phase 1 的 `MeasurementValue`。新增 `outcome` 与 `validatorMessages` 字段，
/// 让测量自带 pass/fail 状态与失败原因，可直接被 OutputCallback 序列化。
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

import Foundation

/// 阶段执行结果
public enum PhaseOutcomeType: String, Sendable, Codable {
    case pass = "PASS"
    case fail = "FAIL"
    case skip = "SKIP"
    case error = "ERROR"
}

/// 阶段记录
public struct PhaseRecord: Sendable, Codable, Identifiable {
    public let id: UUID
    public let name: String
    public let startTime: Date
    public var endTime: Date?
    public var outcome: PhaseOutcomeType
    public var value: String?
    public var measurements: [String: Measurement]
    public var attachments: [Attachment]
    public var errorMessage: String?

    public init(name: String) {
        self.id = UUID()
        self.name = name
        self.startTime = Date()
        self.endTime = nil
        self.outcome = .pass
        self.value = nil
        self.measurements = [:]
        self.attachments = []
        self.errorMessage = nil
    }

    /// 阶段持续时间
    public var duration: TimeInterval {
        guard let endTime else { return Date().timeIntervalSince(startTime) }
        return endTime.timeIntervalSince(startTime)
    }
}

import Foundation

/// 测试阶段定义
public struct PhaseDefinition: Identifiable, Sendable {
    public let id: UUID = UUID()
    public let name: String
    public let timeout: TimeInterval?
    public let retryCount: Int
    public let execute: @Sendable @MainActor (TestContext) async throws -> PhaseResult
    
    /// 初始化
    /// - Parameters:
    ///   - name: 阶段名称
    ///   - timeout: 超时时间（秒）
    ///   - retryCount: 重试次数
    ///   - execute: 执行闭包
    public init(
        name: String,
        timeout: TimeInterval? = nil,
        retryCount: Int = 0,
        execute: @escaping @Sendable @MainActor (TestContext) async throws -> PhaseResult
    ) {
        self.name = name
        self.timeout = timeout
        self.retryCount = retryCount
        self.execute = execute
    }
}

/// 测试阶段（带验证规则）
public struct Phase: Identifiable, Sendable {
    public let id: UUID = UUID()
    public let definition: PhaseDefinition
    public let validators: [Validator]
    public let lowerLimit: String?
    public let upperLimit: String?
    public let unit: String?
    
    /// 初始化
    /// - Parameters:
    ///   - definition: 阶段定义
    ///   - validators: 验证器列表
    ///   - lowerLimit: 下限
    ///   - upperLimit: 上限
    ///   - unit: 单位
    public init(
        definition: PhaseDefinition,
        validators: [Validator] = [],
        lowerLimit: String? = nil,
        upperLimit: String? = nil,
        unit: String? = nil
    ) {
        self.definition = definition
        self.validators = validators
        self.lowerLimit = lowerLimit
        self.upperLimit = upperLimit
        self.unit = unit
    }
    
    /// 便捷初始化
    public init(
        name: String,
        timeout: TimeInterval? = nil,
        retryCount: Int = 0,
        lowerLimit: String? = nil,
        upperLimit: String? = nil,
        unit: String? = nil,
        execute: @escaping @Sendable @MainActor (TestContext) async throws -> PhaseResult
    ) {
        self.definition = PhaseDefinition(
            name: name,
            timeout: timeout,
            retryCount: retryCount,
            execute: execute
        )
        self.validators = []
        self.lowerLimit = lowerLimit
        self.upperLimit = upperLimit
        self.unit = unit
    }
}

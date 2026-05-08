import Foundation

/// 测试上下文，传递给 Phase 函数
///
/// 持有当前测试运行所需的运行时数据：
/// - 序列号
/// - 测试值（字符串 K-V，向后兼容）
/// - 类型化测量（推荐 — 通过 `measure(...)`）
/// - 已解析的 Plug 实例
///
/// `measurements` 字典在 phase 完成时被收集到 `PhaseRecord.measurements`。
@MainActor
public final class TestContext {
    /// 当前测试的序列号
    public var serialNumber: String?

    /// 测试值存储（Phase 输出的字符串结果，与 `getValue/setValue` 配对，向后兼容）
    public private(set) var testValues: [String: String] = [:]

    /// 当前 phase 收集的类型化测量值（每次 phase 开始时由 PhaseExecutor 重置）
    public internal(set) var measurements: [String: Measurement] = [:]

    /// 已解析的 Plug 实例字典（按类型名索引）
    private let resolvedPlugs: [String: any PlugProtocol]

    init(serialNumber: String? = nil, resolvedPlugs: [String: any PlugProtocol]) {
        self.serialNumber = serialNumber
        self.resolvedPlugs = resolvedPlugs
    }

    // MARK: - 测试值（旧 API，仍可用）

    /// 设置测试值（用于参与限值校验的字符串结果）
    public func setValue(_ key: String, _ value: String) {
        testValues[key] = value
    }

    /// 获取测试值
    public func getValue(_ key: String) -> String? {
        testValues[key]
    }

    // MARK: - 类型化测量（推荐 API）

    /// 记录一个类型化测量值
    /// - Parameters:
    ///   - name: 测量名（在 phase 内唯一）
    ///   - value: 任意 `Encodable` 值（Bool/Int/Double/String/嵌套结构）
    ///   - unit: 单位（可选，例如 "V"、"mA"、"%"）
    public func measure<T: Encodable>(_ name: String, _ value: T, unit: String? = nil) {
        let coded = AnyCodableValue.from(value)
        measurements[name] = Measurement(
            name: name,
            value: coded,
            unit: unit
        )
    }

    /// 直接以 `AnyCodableValue` 形式写入（用于已经规范化的值）
    public func measure(_ name: String, codedValue: AnyCodableValue, unit: String? = nil) {
        measurements[name] = Measurement(
            name: name,
            value: codedValue,
            unit: unit
        )
    }

    // MARK: - Plug

    /// 获取已注册的 Plug 实例
    /// - Note: 必须在 TestExecutor 初始化后通过 `register(_:)` 或 `register(_:factory:)` 登记过
    public func getPlug<T: PlugProtocol>(_ type: T.Type) -> T {
        let key = String(describing: type)
        guard let plug = resolvedPlugs[key] as? T else {
            fatalError("Plug \(key) is not registered with the TestExecutor")
        }
        return plug
    }
}

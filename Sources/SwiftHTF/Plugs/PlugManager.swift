import Foundation

/// Plug 管理器
///
/// 注册 Plug 类型与可选的工厂闭包；测试运行前 `setupAll()` 解析所有实例并依次 setup，
/// 运行后 `tearDownAll()` 反向清理。
///
/// 实例构造在 `@MainActor` 上完成——这覆盖两种情况：
/// 1. `@MainActor` 隔离的 Plug（如 UI/硬件相关）：init 必须在 MainActor 上调用
/// 2. 非 isolated 的 Plug：在 MainActor 上调用其 init 也安全
public actor PlugManager {
    private var instances: [String: any PlugProtocol] = [:]
    private var factories: [String: @MainActor @Sendable () -> any PlugProtocol] = [:]

    public init() {}

    /// 注册 Plug 类型，使用类型自带的 `init()` 创建实例
    public func register<T: PlugProtocol>(_ type: T.Type) {
        let key = String(describing: type)
        factories[key] = { @MainActor in type.init() }
    }

    /// 注册 Plug 类型，使用工厂闭包创建实例（适合需要构造器参数的场景）
    public func register<T: PlugProtocol>(
        _ type: T.Type,
        factory: @escaping @MainActor @Sendable () -> T
    ) {
        let key = String(describing: type)
        factories[key] = { @MainActor in factory() }
    }

    /// 设置所有已注册的 Plug 并返回解析好的实例字典
    /// - Returns: 类型名 → 实例 的字典，供 TestContext 持有
    func setupAll() async throws -> [String: any PlugProtocol] {
        for (key, factory) in factories where instances[key] == nil {
            instances[key] = await factory()
        }
        for (_, plug) in instances {
            try await plug.setup()
        }
        return instances
    }

    /// 清理所有 Plug
    func tearDownAll() async {
        for (_, plug) in instances {
            await plug.tearDown()
        }
        instances.removeAll()
    }
}

import Foundation

/// Plug 协议（硬件插件）
///
/// 协议本身不限定 actor isolation——具体实现可以选择 `@MainActor`（如本项目的 UART）、
/// 自定义 actor、或非 isolated 类型。`setup()` / `tearDown()` 是 async，PlugManager
/// 调用时会自动跨 isolation 边界。
public protocol PlugProtocol: AnyObject, Sendable {
    /// 默认初始化（无参）。需要构造器参数时改用 `PlugManager.register(_:factory:)`。
    init()

    /// 测试开始前调用：建立硬件连接、设置初始状态等
    func setup() async throws

    /// 测试结束时调用：保证执行，断开连接、释放资源等
    func tearDown() async
}

/// Plug 默认实现
public extension PlugProtocol {
    func setup() async throws {}
    func tearDown() async {}
}

import Foundation

/// 操作员交互请求种类
public enum PromptKind: Sendable {
    case confirm(message: String)
    case text(message: String, placeholder: String?)
    case choice(message: String, options: [String])
}

/// 一次操作员交互请求
public struct PromptRequest: Sendable, Identifiable {
    public let id: UUID
    public let kind: PromptKind
    public let createdAt: Date

    public init(id: UUID = UUID(), kind: PromptKind, createdAt: Date = Date()) {
        self.id = id
        self.kind = kind
        self.createdAt = createdAt
    }
}

/// 操作员对一次请求的响应
public enum PromptResponse: Sendable {
    case confirm(Bool)
    case text(String)
    case choice(Int)
    /// 主动取消（phase Task cancel / plug.cancel(id:) / tearDown）
    case cancelled
    /// 超时未应答。底层 `request(kind:timeout:)` 可区分；高阶 API 映射成默认值（false / "" / -1）
    case timedOut
}

/// 操作员交互 Plug
///
/// 用法（phase 中）：
/// ```swift
/// let prompt = ctx.getPlug(PromptPlug.self)
/// guard await prompt.requestConfirm("放好治具？") else { return .stop }
/// let sn = await prompt.requestText("请扫码", placeholder: "SN")
/// ```
///
/// 用法（SwiftUI 中）：
/// ```swift
/// .task {
///     for await req in await prompt.events() {
///         current = req // 触发 sheet
///     }
/// }
/// ```
/// UI 响应后调用 `prompt.resolve(id: req.id, response: .confirm(true))`。
///
/// 隔离：`@MainActor`，便于 SwiftUI 视图直接持有并订阅；phase 闭包默认也是
/// `@MainActor`，调用 `await prompt.requestConfirm(...)` 不跨 actor 边界。
@MainActor
public final class PromptPlug: PlugProtocol {
    private var pendingRequests: [PromptRequest] = []
    private var continuations: [UUID: CheckedContinuation<PromptResponse, Never>] = [:]
    private var subscribers: [UUID: AsyncStream<PromptRequest>.Continuation] = [:]
    /// resolutions() 的订阅者集合。任何 resolve（用户应答 / cancel / timeout）都会 yield 该 req.id。
    /// 与 `subscribers` 平行；新订阅者**不**回放历史（过期信号无价值）。
    private var resolutionSubscribers: [UUID: AsyncStream<UUID>.Continuation] = [:]

    public nonisolated init() {}

    public nonisolated func setup() async throws {}

    public nonisolated func tearDown() async {
        await cancelAll()
    }

    private func cancelAll() {
        // 留存 id 列表以便通知 resolutions 订阅者（resume 前快照）
        let ids = continuations.keys.map { $0 }
        for cont in continuations.values {
            cont.resume(returning: .cancelled)
        }
        continuations.removeAll()
        pendingRequests.removeAll()
        for id in ids {
            for sub in resolutionSubscribers.values {
                sub.yield(id)
            }
        }
        for sub in subscribers.values {
            sub.finish()
        }
        subscribers.removeAll()
        for sub in resolutionSubscribers.values {
            sub.finish()
        }
        resolutionSubscribers.removeAll()
    }

    // MARK: - 订阅 / 解析（UI 侧）

    /// 订阅请求流。新订阅会立刻收到所有尚未应答的 pending 请求。
    public func events() -> AsyncStream<PromptRequest> {
        let id = UUID()
        var continuation: AsyncStream<PromptRequest>.Continuation!
        let stream = AsyncStream<PromptRequest> { c in
            continuation = c
        }
        subscribers[id] = continuation
        for req in pendingRequests {
            continuation.yield(req)
        }
        continuation.onTermination = { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.detach(id)
            }
        }
        return stream
    }

    private func detach(_ id: UUID) {
        subscribers.removeValue(forKey: id)
    }

    /// 订阅"request 已 resolve"信号流。任意原因 resolve（用户应答 / cancel / timeout）都会 yield 一次 req.id。
    ///
    /// 与 `events()` 不同：本流**不回放历史**——过期 resolution 信号对消费方无价值；
    /// 适合 UI 层在收到 resolution 后撤回正在显示的 sheet，避免僵尸 prompt。
    public func resolutions() -> AsyncStream<UUID> {
        let id = UUID()
        var continuation: AsyncStream<UUID>.Continuation!
        let stream = AsyncStream<UUID> { c in
            continuation = c
        }
        resolutionSubscribers[id] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.detachResolutions(id)
            }
        }
        return stream
    }

    private func detachResolutions(_ id: UUID) {
        resolutionSubscribers.removeValue(forKey: id)
    }

    /// 应答某次请求；类型与请求不匹配时由调用方 phase 内的高阶 API 处理。
    public func resolve(id: UUID, response: PromptResponse) {
        guard let cont = continuations.removeValue(forKey: id) else { return }
        pendingRequests.removeAll { $0.id == id }
        cont.resume(returning: response)
        // 通知 resolutions 订阅者（cancel / timeout / 用户回应统一从此处出口）
        for sub in resolutionSubscribers.values {
            sub.yield(id)
        }
    }

    /// 取消某次请求（phase 内 await 会收到 `.cancelled`）。
    public func cancel(id: UUID) {
        resolve(id: id, response: .cancelled)
    }

    /// 当前未应答的请求快照（用于诊断 / UI 重建）
    public var pending: [PromptRequest] {
        pendingRequests
    }

    // MARK: - 高阶 API（phase 侧）

    /// 请求确认（是 / 否）。被取消 / 超时 / 类型不匹配时返回 `false`。
    /// - Parameters:
    ///   - message: 提示文本，显示给操作员
    ///   - timeout: 超时秒数；nil 表示永久等待（默认）
    public func requestConfirm(_ message: String, timeout: TimeInterval? = nil) async -> Bool {
        let response = await request(kind: .confirm(message: message), timeout: timeout)
        if case let .confirm(b) = response { return b }
        return false
    }

    /// 请求文本输入。被取消 / 超时 / 类型不匹配时返回空字符串。
    public func requestText(
        _ message: String,
        placeholder: String? = nil,
        timeout: TimeInterval? = nil
    ) async -> String {
        let response = await request(
            kind: .text(message: message, placeholder: placeholder),
            timeout: timeout
        )
        if case let .text(s) = response { return s }
        return ""
    }

    /// 请求多选。被取消 / 超时 / 类型不匹配时返回 `-1`。
    public func requestChoice(
        _ message: String,
        options: [String],
        timeout: TimeInterval? = nil
    ) async -> Int {
        let response = await request(
            kind: .choice(message: message, options: options),
            timeout: timeout
        )
        if case let .choice(i) = response { return i }
        return -1
    }

    /// 底层请求接口：返回原始 `PromptResponse`，可区分 `.cancelled` 与 `.timedOut`。
    ///
    /// 超时实现：`withTaskGroup` 内 continuation task 与 sleep task 赛跑，先到先得。
    /// - 超时分支胜出 → 主动 `resolve(.timedOut)`，让 continuation task 退出并通知 resolutions 订阅者
    /// - phase Task 取消 → `withTaskCancellationHandler` 走 `cancel(id:)` → `.cancelled`
    public func request(kind: PromptKind, timeout: TimeInterval? = nil) async -> PromptResponse {
        let req = PromptRequest(kind: kind)
        pendingRequests.append(req)
        for sub in subscribers.values {
            sub.yield(req)
        }

        return await withTaskCancellationHandler {
            await withTaskGroup(of: PromptResponse.self) { group in
                // 用户应答路径：注册 continuation 等待 resolve
                group.addTask { @MainActor [weak self] in
                    guard let self else { return .cancelled }
                    return await withCheckedContinuation { (cont: CheckedContinuation<PromptResponse, Never>) in
                        self.continuations[req.id] = cont
                    }
                }
                // 超时路径：仅在 timeout 非 nil 时存在
                if let timeout {
                    group.addTask {
                        if timeout > 0 {
                            try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                        }
                        // 被外部 cancel（如 phase Task.cancel 触发 group child cancel）时不抢占 .timedOut，
                        // 让 race 由 continuation 路径胜出（onCancel 已通过 cancel(id:) → resolve(.cancelled)）。
                        if Task.isCancelled { return .cancelled }
                        return .timedOut
                    }
                }
                let first = await group.next() ?? .cancelled
                group.cancelAll()
                // 超时分支抢先：主动 resolve 让 continuation task 退出 + 通知订阅者
                if case .timedOut = first {
                    resolve(id: req.id, response: .timedOut)
                }
                return first
            }
        } onCancel: { [weak self] in
            Task { @MainActor [weak self] in
                self?.cancel(id: req.id)
            }
        }
    }
}

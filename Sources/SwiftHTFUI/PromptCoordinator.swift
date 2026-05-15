import Combine
import Foundation
import SwiftHTF

/// 把 `PromptPlug.events()` 转成 SwiftUI 友好的 `@Published` 状态。
///
/// 用法：
/// ```swift
/// @StateObject private var prompts = PromptCoordinator()
///
/// var body: some View {
///     ContentView()
///         .task { await prompts.attach(to: promptPlug) }
///         .sheet(item: $prompts.current) { req in
///             PromptSheetView(request: req) { resp in
///                 prompts.resolve(req.id, response: resp)
///             }
///         }
/// }
/// ```
@MainActor
public final class PromptCoordinator: ObservableObject {
    @Published public var current: PromptRequest?

    private weak var plug: PromptPlug?
    private var listener: Task<Void, Never>?
    private var resolutionListener: Task<Void, Never>?
    private var detached: Bool = true

    public init() {}

    /// 绑定到一个 PromptPlug 实例并开始消费请求 + resolution 通知。
    /// 同一时刻只展示一个请求；plug 端任意原因 resolve（用户应答 / cancel / timeout）后
    /// `current` 会被自动清空，避免僵尸 sheet。
    public func attach(to plug: PromptPlug) async {
        detach()
        self.plug = plug
        detached = false
        let requestStream = plug.events()
        let resolutionStream = plug.resolutions()
        listener = Task { @MainActor [weak self] in
            for await req in requestStream {
                guard let self else { return }
                if detached { continue }
                // 简单策略：若当前已有 prompt，覆盖之
                current = req
            }
        }
        resolutionListener = Task { @MainActor [weak self] in
            for await id in resolutionStream {
                guard let self else { return }
                if detached { continue }
                if current?.id == id { current = nil }
            }
        }
    }

    /// 停止订阅。
    public func detach() {
        detached = true
        listener?.cancel()
        listener = nil
        resolutionListener?.cancel()
        resolutionListener = nil
        current = nil
        plug = nil
    }

    /// 应答当前 prompt。
    public func resolve(_ id: UUID, response: PromptResponse) {
        plug?.resolve(id: id, response: response)
        if current?.id == id {
            current = nil
        }
    }

    /// 取消当前 prompt（phase 内会收到 .cancelled）。
    public func cancel(_ id: UUID) {
        plug?.cancel(id: id)
        if current?.id == id {
            current = nil
        }
    }

    deinit {
        listener?.cancel()
        resolutionListener?.cancel()
    }
}

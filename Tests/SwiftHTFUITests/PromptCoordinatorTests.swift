import SwiftHTF
@testable import SwiftHTFUI
import XCTest

@MainActor
final class PromptCoordinatorTests: XCTestCase {
    func testCurrentPopulatedWhenPlugRequests() async throws {
        let plug = PromptPlug()
        let coord = PromptCoordinator()
        await coord.attach(to: plug)

        // phase 端发起请求
        let answerTask = Task { @MainActor [plug] in
            await plug.requestConfirm("ready?")
        }

        try await waitUntil { coord.current != nil }
        XCTAssertNotNil(coord.current)
        if case let .confirm(msg) = coord.current?.kind {
            XCTAssertEqual(msg, "ready?")
        } else {
            XCTFail("expected .confirm")
        }

        // 应答
        let id = try XCTUnwrap(coord.current?.id)
        coord.resolve(id, response: .confirm(true))

        let answer = await answerTask.value
        XCTAssertTrue(answer)
        XCTAssertNil(coord.current, "resolve 后 current 应清空")

        coord.detach()
    }

    func testCancelRoutesToPlug() async throws {
        let plug = PromptPlug()
        let coord = PromptCoordinator()
        await coord.attach(to: plug)

        let answerTask = Task { @MainActor [plug] in
            await plug.requestText("scan", placeholder: nil)
        }

        try await waitUntil { coord.current != nil }
        let id = try XCTUnwrap(coord.current?.id)
        coord.cancel(id)

        let answer = await answerTask.value
        XCTAssertEqual(answer, "")
        XCTAssertNil(coord.current)
        coord.detach()
    }

    func testPlugTimeoutClearsCurrentSheet() async throws {
        // 修僵尸 sheet：plug 端超时 resolve 后，coord.current 应被 resolutions() 流自动清空
        let plug = PromptPlug()
        let coord = PromptCoordinator()
        await coord.attach(to: plug)

        async let _: PromptResponse = plug.request(kind: .confirm(message: "x"), timeout: 0.1)
        try await waitUntil { coord.current != nil }
        XCTAssertNotNil(coord.current)

        // 不应答，等超时触发
        try await waitUntil { coord.current == nil }
        XCTAssertNil(coord.current, "超时后 current 应被 resolutions 自动清空")

        coord.detach()
    }

    func testDetachStopsListening() async throws {
        let plug = PromptPlug()
        let coord = PromptCoordinator()
        await coord.attach(to: plug)
        coord.detach()

        // detach 后再发请求 — current 应保持 nil
        let answerTask = Task { @MainActor [plug] in
            await plug.requestConfirm("after detach")
        }

        try await Task.sleep(nanoseconds: 80_000_000)
        XCTAssertNil(coord.current)

        // 收尾：直接 cancel pending（避免 leak）
        await plug.tearDown()
        _ = await answerTask.value
    }

    private func waitUntil(timeout: TimeInterval = 2.0, _ predicate: @MainActor () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !predicate() {
            if Date() > deadline {
                XCTFail("timeout")
                return
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
    }
}

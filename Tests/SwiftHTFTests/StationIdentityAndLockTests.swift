@testable import SwiftHTF
import XCTest

/// `StationInfo.current()` + `StationLock` 互斥锁。
final class StationIdentityAndLockTests: XCTestCase {
    private var tempDir: URL!

    override func setUp() async throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("swifthtf-lock-\(UUID().uuidString)")
    }

    override func tearDown() async throws {
        if let dir = tempDir {
            try? FileManager.default.removeItem(at: dir)
        }
    }

    // MARK: - StationInfo.current() 填充字段

    func testCurrentFillsHostPIDAndBootTime() {
        let info = StationInfo.current(stationId: "FixtureA")
        XCTAssertEqual(info.stationId, "FixtureA")
        XCTAssertNotNil(info.hostName)
        XCTAssertEqual(info.processID, getpid())
        XCTAssertNotNil(info.bootTime)
        // boot time 应该在过去（开机时间，肯定早于当前时刻）
        if let bt = info.bootTime {
            XCTAssertLessThanOrEqual(bt, Date())
        }
    }

    // MARK: - StationInfo Codable round trip

    func testStationInfoRoundTripWithNewFields() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let info = StationInfo(
            stationId: "S",
            hostName: "host-1",
            processID: 1234,
            bootTime: now
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(info)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(StationInfo.self, from: data)
        XCTAssertEqual(decoded, info)
    }

    // MARK: - StationLock 基本 acquire / release

    func testAcquireCreatesLockFileAndReleaseRemovesIt() async throws {
        let info = StationInfo.current(stationId: "FixtureA")
        let lock = try await StationLock.acquire(
            name: "FixtureA",
            at: tempDir,
            identity: info
        )
        let path = await lock.path
        XCTAssertTrue(FileManager.default.fileExists(atPath: path.path))
        await lock.release()
        XCTAssertFalse(FileManager.default.fileExists(atPath: path.path))
        let held = await lock.isHeld
        XCTAssertFalse(held)
    }

    // MARK: - 双方竞争：第二次抛 .locked(by:)，含 identity

    func testSecondAcquireSeesHolder() async throws {
        let info1 = StationInfo.current(stationId: "FixtureA", location: "BenchA")
        let lock = try await StationLock.acquire(
            name: "FixtureA", at: tempDir, identity: info1
        )
        defer { Task { await lock.release() } }

        let info2 = StationInfo.current(stationId: "FixtureA-Other")
        do {
            _ = try await StationLock.acquire(
                name: "FixtureA", at: tempDir, identity: info2
            )
            XCTFail("expected StationLockError.locked")
        } catch let StationLockError.locked(by) {
            XCTAssertNotNil(by, "lock 文件应能解析回 identity")
            XCTAssertEqual(by?.stationId, "FixtureA")
            XCTAssertEqual(by?.processID, getpid())
            XCTAssertEqual(by?.location, "BenchA")
        }
    }

    // MARK: - release 后可重新 acquire

    func testReleaseAllowsReAcquire() async throws {
        let info = StationInfo.current(stationId: "FixtureB")
        let first = try await StationLock.acquire(
            name: "FixtureB", at: tempDir, identity: info
        )
        await first.release()
        // 同名再 acquire 应成功
        let second = try await StationLock.acquire(
            name: "FixtureB", at: tempDir, identity: info
        )
        await second.release()
    }

    // MARK: - 重复 release 幂等

    func testReleaseIsIdempotent() async throws {
        let info = StationInfo.current(stationId: "X")
        let lock = try await StationLock.acquire(
            name: "X", at: tempDir, identity: info
        )
        await lock.release()
        await lock.release() // 第二次不应崩
        await lock.release()
    }

    // MARK: - 损坏的 lock 文件被识别为 .locked(by: nil)

    func testCorruptedLockFileReportedAsUnknownHolder() async throws {
        try FileManager.default.createDirectory(
            at: tempDir, withIntermediateDirectories: true
        )
        let corrupted = tempDir.appendingPathComponent("Corrupt.lock")
        try Data("not json".utf8).write(to: corrupted)
        let info = StationInfo.current(stationId: "Corrupt")
        do {
            _ = try await StationLock.acquire(
                name: "Corrupt", at: tempDir, identity: info
            )
            XCTFail("expected locked error")
        } catch let StationLockError.locked(by) {
            XCTAssertNil(by, "无法解析的 lock 文件应回报 holder=nil")
        }
    }
}

import Foundation

/// 工站级互斥锁（lock file）。
///
/// 在指定目录创建 `<name>.lock` 文件，写入持锁者的 `StationInfo` JSON。
/// 互斥靠 POSIX `O_CREAT | O_EXCL`：文件已存在即冲突（原子失败）。
/// 适合"多进程共享同台机器但只有一个能跑某 station"的场景，例如
/// CI runner / CLI 工具 / 双端口 SwiftUI app 误启动保护。
///
/// 不做 stale detection——若持锁进程异常死亡留下残留 lock 文件，
/// 由运维 / 调用方手工清理。可读 lock 文件内容（`StationLockError.locked`
/// 携带 `StationInfo`）判断是否 stale。
///
/// ```swift
/// let url = URL(fileURLWithPath: "/var/run/swifthtf")
/// let info = StationInfo.current(stationId: "FixtureA")
/// let lock = try await StationLock.acquire(name: "FixtureA", at: url, identity: info)
/// defer { Task { await lock.release() } }
/// // ... 启动 TestExecutor 跑测试
/// ```
public actor StationLock {
    private let fileURL: URL
    /// 当前进程是否仍持有这把锁；release 后置 false，重复 release 安全
    private var held: Bool

    private init(fileURL: URL) {
        self.fileURL = fileURL
        held = true
    }

    /// 尝试获取 lock。
    ///
    /// 原子语义靠 `Data.write(.withoutOverwriting)` 底层的 `O_CREAT | O_EXCL`：
    /// lock 文件已存在 → 立刻冲突，**不**做 stale detection。
    ///
    /// - Parameters:
    ///   - name: lock 名（通常对应 stationId），会拼成 `<directory>/<name>.lock`
    ///   - directory: lock 文件父目录；不存在则按 `withIntermediateDirectories` 创建
    ///   - identity: 持锁者的 ``StationInfo``；以 JSON 写入 lock 文件供 readHolder 查看
    /// - Returns: 持锁的 `StationLock` actor；release 之前一直占用
    /// - Throws:
    ///   - ``StationLockError/locked(by:)`` 已有其他进程持锁；associated value 是从
    ///     lock 文件反序列化出的 StationInfo（解析失败时为 nil）
    ///   - ``StationLockError/ioFailure(_:)`` 创建目录 / encode / 写文件失败
    public static func acquire(
        name: String,
        at directory: URL,
        identity: StationInfo
    ) async throws -> StationLock {
        do {
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true
            )
        } catch {
            throw StationLockError.ioFailure("create directory failed: \(error.localizedDescription)")
        }
        let path = lockFileURL(name: name, in: directory)
        let data = try encodeIdentity(identity)
        // `Data.write(.withoutOverwriting)` 内部走 O_CREAT|O_EXCL，原子互斥；已存在抛 NSFileWriteFileExistsError。
        do {
            try data.write(to: path, options: [.withoutOverwriting])
        } catch let error as NSError where error.code == NSFileWriteFileExistsError {
            let holder = readHolder(at: path)
            throw StationLockError.locked(by: holder)
        } catch {
            throw StationLockError.ioFailure("write lock file failed: \(error.localizedDescription)")
        }
        return StationLock(fileURL: path)
    }

    /// 释放 lock。重复调安全。
    public func release() {
        guard held else { return }
        held = false
        try? FileManager.default.removeItem(at: fileURL)
    }

    /// 当前持锁状态。
    public var isHeld: Bool {
        held
    }

    /// lock 文件路径（测试可见）。
    public var path: URL {
        fileURL
    }

    // MARK: - 私有 helper

    private static func lockFileURL(name: String, in directory: URL) -> URL {
        directory.appendingPathComponent("\(name).lock")
    }

    /// 读已存在 lock 的持锁者 identity；解析失败返回 nil。
    private static func readHolder(at url: URL) -> StationInfo? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(StationInfo.self, from: data)
    }

    private static func encodeIdentity(_ identity: StationInfo) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            return try encoder.encode(identity)
        } catch {
            throw StationLockError.ioFailure("encode identity failed: \(error.localizedDescription)")
        }
    }
}

/// 工站锁错误。
public enum StationLockError: Error, LocalizedError {
    /// 锁已被其他进程持有。`by` 是从已存在 lock 文件读出的持锁者 identity；
    /// nil 表示 lock 文件存在但解析失败（损坏 / 权限不足）。
    case locked(by: StationInfo?)
    /// 文件 IO 错误（创建目录 / open / write / 编码）。
    case ioFailure(String)

    public var errorDescription: String? {
        switch self {
        case let .locked(by):
            if let h = by {
                "Station lock held by station=\(h.stationId) pid=\(h.processID.map(String.init) ?? "?") host=\(h.hostName ?? "?")"
            } else {
                "Station lock held by unknown process (lock file present but unreadable)"
            }
        case let .ioFailure(msg):
            "Station lock IO failure: \(msg)"
        }
    }
}

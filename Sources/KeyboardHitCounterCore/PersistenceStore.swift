import Foundation
import os

public struct DailyCounts: Codable, Equatable {
    public var version: Int = 1
    public var days: [String: [String: Int64]] = [:]

    public static let empty = DailyCounts()

    public init() {}
}

/// 持久化 I/O 层：读盘、累加、写盘。不含节流与 delta 计算（见 PersistenceWorker）。
public final class PersistenceStore {
    private let fileURL: URL
    private var lock = os_unfair_lock()
    private var counts: DailyCounts

    public init(fileURL: URL) {
        self.fileURL = fileURL
        self.counts = Self.load(from: fileURL)
    }

    public func accumulate(deltas: [String: Int64], dayKey: String) {
        os_unfair_lock_lock(&lock)
        for (bundleID, delta) in deltas where delta > 0 {
            counts.days[dayKey, default: [:]][bundleID, default: 0] += delta
        }
        os_unfair_lock_unlock(&lock)
    }

    public func snapshot() -> DailyCounts {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        return counts
    }

    public func save() throws {
        let data = try encodedCounts()

        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: fileURL, options: .atomic)
    }

    private func encodedCounts() throws -> Data {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        return try JSONEncoder().encode(counts)
    }

    private static func load(from url: URL) -> DailyCounts {
        guard let data = try? Data(contentsOf: url) else { return .empty }
        return (try? JSONDecoder().decode(DailyCounts.self, from: data)) ?? .empty
    }
}
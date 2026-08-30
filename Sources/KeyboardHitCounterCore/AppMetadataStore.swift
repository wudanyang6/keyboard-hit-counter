import Foundation
import os

/// 应用显示名/图标缓存。`iconData` 存 PNG `Data`（线程安全），`NSImage` 由 UI 主线程按需解码。
public struct AppMetadata: Codable, Equatable {
    public let displayName: String
    public let iconData: Data?

    public init(displayName: String, iconData: Data?) {
        self.displayName = displayName
        self.iconData = iconData
    }
}

/// 应用显示名/图标的内存缓存，可选带落盘（`metadata.json`）。
/// 落盘后重启可恢复显示名/图标，避免聚合层因无 metadata 而回退成 bundleID。
public final class AppMetadataStore {
    private let fileURL: URL?
    private var lock = os_unfair_lock()
    private var storage: [String: AppMetadata] = [:]
    private var dirty = false
    private var generation = 0

    /// - Parameter fileURL: 传 nil 表示纯内存缓存（不落盘）；否则 init 时从该文件恢复，`save()` 落盘。
    public init(fileURL: URL? = nil) {
        self.fileURL = fileURL
        if let fileURL {
            for (id, metadata) in Self.load(from: fileURL) {
                storage[id] = metadata
            }
        }
    }

    public func record(_ metadata: AppMetadata, forBundleID id: String) {
        os_unfair_lock_lock(&lock)
        storage[id] = metadata
        dirty = true
        generation += 1
        os_unfair_lock_unlock(&lock)
    }

    public func metadata(forBundleID id: String) -> AppMetadata? {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        return storage[id]
    }

    public func snapshot() -> [String: AppMetadata] {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        return storage
    }

    /// 有未落盘改动且配置了 fileURL 时原子写盘；无改动或无 fileURL 时为空操作。
    public func save() throws {
        guard let fileURL else { return }

        var generation = 0
        var snapshot: [String: AppMetadata] = [:]
        os_unfair_lock_lock(&lock)
        let shouldSave = dirty
        if shouldSave {
            snapshot = storage
            generation = self.generation
        }
        os_unfair_lock_unlock(&lock)
        guard shouldSave else { return }

        let data = try JSONEncoder().encode(snapshot)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: fileURL, options: .atomic)

        // 写盘期间若又有新的 record 进来（generation 变化），保留 dirty，下轮再落盘。
        os_unfair_lock_lock(&lock)
        if self.generation == generation {
            dirty = false
        }
        os_unfair_lock_unlock(&lock)
    }

    private static func load(from url: URL) -> [String: AppMetadata] {
        guard let data = try? Data(contentsOf: url) else { return [:] }
        return (try? JSONDecoder().decode([String: AppMetadata].self, from: data)) ?? [:]
    }
}

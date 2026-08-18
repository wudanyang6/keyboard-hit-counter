import Foundation
import os

/// 应用显示名/图标缓存。`iconData` 存 PNG `Data`（线程安全），`NSImage` 由 UI 主线程按需解码。
public struct AppMetadata {
    public let displayName: String
    public let iconData: Data?

    public init(displayName: String, iconData: Data?) {
        self.displayName = displayName
        self.iconData = iconData
    }
}

public final class AppMetadataStore {
    private var lock = os_unfair_lock()
    private var storage: [String: AppMetadata] = [:]

    public init() {}

    public func record(_ metadata: AppMetadata, forBundleID id: String) {
        os_unfair_lock_lock(&lock)
        storage[id] = metadata
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
}
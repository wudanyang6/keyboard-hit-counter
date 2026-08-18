import AppKit

/// 追踪最前台应用：订阅 NSWorkspace 通知，解析 bundleID → 分配 slot → 原子写入当前 slot，
/// 并把新出现应用的显示名/图标写入 AppMetadataStore。每秒兜底刷新防止漏通知。
public final class FrontmostAppTracker {
    private let registry: AppSlotRegistry
    private let counters: CounterStore
    private let metadataStore: AppMetadataStore
    private var observer: NSObjectProtocol?
    private var timer: Timer?

    public init(registry: AppSlotRegistry,
                counters: CounterStore,
                metadataStore: AppMetadataStore) {
        self.registry = registry
        self.counters = counters
        self.metadataStore = metadataStore
    }

    public func start() {
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: nil
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
                return
            }
            self?.apply(app)
        }

        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let app = NSWorkspace.shared.frontmostApplication else { return }
            self?.apply(app)
        }
    }

    public func stop() {
        if let observer {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            self.observer = nil
        }
        timer?.invalidate()
        timer = nil
    }

    private func apply(_ app: NSRunningApplication) {
        guard let bundleID = app.bundleIdentifier, bundleID != Self.ownBundleID else {
            counters.setCurrentSlot(0)
            return
        }

        let slot = registry.slot(forBundleID: bundleID)
        counters.setCurrentSlot(slot)

        if metadataStore.metadata(forBundleID: bundleID) == nil {
            let metadata = AppMetadata(
                displayName: app.localizedName ?? bundleID,
                iconData: app.icon?.khcPNGData()
            )
            metadataStore.record(metadata, forBundleID: bundleID)
        }
    }

    private static let ownBundleID = Bundle.main.bundleIdentifier
}
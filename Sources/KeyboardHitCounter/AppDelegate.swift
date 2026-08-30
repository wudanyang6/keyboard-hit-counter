import AppKit
import ApplicationServices
import KeyboardHitCounterCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let counters = CounterStore()!
    private let registry = AppSlotRegistry()
    private lazy var metadataStore = AppMetadataStore(fileURL: Self.metadataFileURL)
    private lazy var persistenceStore = PersistenceStore(fileURL: Self.countsFileURL)
    private lazy var persistenceWorker = PersistenceWorker(
        counters: counters, registry: registry, store: persistenceStore
    )
    private lazy var tracker = FrontmostAppTracker(
        registry: registry, counters: counters, metadataStore: metadataStore
    )
    private let viewModel = StatusViewModel()
    private let statsViewModel = StatsViewModel()
    private let uiQueue = DispatchQueue(label: "khc.ui", qos: .userInitiated)
    private var aggregatorTimer: DispatchSourceTimer?
    private var permissionTimer: Timer?
    private var tap: KeyEventTap?
    private var menuBarController: MenuBarController?
    private lazy var statsWindowController = StatsWindowController(viewModel: statsViewModel)

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenuBar()
        startTap()
        startWorkers()
    }

    func applicationWillTerminate(_ notification: Notification) {
        persistenceWorker.flushNow()
        try? metadataStore.save()
        tap?.stop()
        tracker.stop()
    }

    private func setupMenuBar() {
        menuBarController = MenuBarController(
            viewModel: viewModel,
            onOpenStats: { [weak self] in self?.statsWindowController.show() },
            onOpenSettings: { [weak self] in self?.openAccessibilitySettings() }
        )
    }

    private func openAccessibilitySettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    private func startTap() {
        let counters = self.counters
        tap = KeyEventTap {
            counters.incrementCurrentSlot()
        }
        switch tap?.start() {
        case .success:
            viewModel.permissionState = .granted
        case .failure(.notTrusted), .failure(.failedToCreate), .none:
            viewModel.permissionState = .denied
        }
    }

    private func startWorkers() {
        tracker.start()
        persistenceWorker.start()

        let timer = DispatchSource.makeTimerSource(queue: uiQueue)
        timer.schedule(deadline: .now(), repeating: 1.0)
        timer.setEventHandler { [weak self] in self?.refreshUI() }
        timer.resume()
        aggregatorTimer = timer

        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.recoverPermissionIfGranted()
        }
    }

    private func recoverPermissionIfGranted() {
        guard viewModel.permissionState == .denied, AXIsProcessTrusted() else { return }
        startTap()
    }

    private func refreshUI() {
        let counts = persistenceStore.snapshot()
        let sessionDelta = persistenceWorker.sessionDeltaByBundleID()
        let metadata = metadataStore.snapshot()

        let rows = Aggregator().produceRows(
            counts: counts,
            sessionDeltaByBundleID: sessionDelta,
            metadataByBundleID: metadata,
            dayKey: PersistenceWorker.dayKey()
        )
        let statsSnapshot = StatsAggregator().produceSnapshot(
            counts: counts,
            sessionDeltaByBundleID: sessionDelta,
            metadataByBundleID: metadata
        )

        DispatchQueue.main.async { [weak self] in
            self?.viewModel.rows = rows
            self?.statsViewModel.snapshot = statsSnapshot
        }

        // 元数据（显示名/图标）有新内容时落盘，供下次启动恢复显示，避免回退成 bundleID。
        try? metadataStore.save()
    }

    private static var appSupportDirectoryURL: URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("KeyboardHitCounter", isDirectory: true)
    }

    private static var countsFileURL: URL {
        appSupportDirectoryURL.appendingPathComponent("counts.json")
    }

    private static var metadataFileURL: URL {
        appSupportDirectoryURL.appendingPathComponent("metadata.json")
    }
}
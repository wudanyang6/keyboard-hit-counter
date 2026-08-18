import AppKit
import ApplicationServices
import KeyboardHitCounterCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let counters = CounterStore()!
    private let registry = AppSlotRegistry()
    private let metadataStore = AppMetadataStore()
    private lazy var persistenceStore = PersistenceStore(fileURL: Self.countsFileURL)
    private lazy var persistenceWorker = PersistenceWorker(
        counters: counters, registry: registry, store: persistenceStore
    )
    private lazy var tracker = FrontmostAppTracker(
        registry: registry, counters: counters, metadataStore: metadataStore
    )
    private let viewModel = StatusViewModel()
    private let uiQueue = DispatchQueue(label: "khc.ui", qos: .userInitiated)
    private var aggregatorTimer: DispatchSourceTimer?
    private var permissionTimer: Timer?
    private var tap: KeyEventTap?
    private var menuBarController: MenuBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenuBar()
        startTap()
        startWorkers()
    }

    func applicationWillTerminate(_ notification: Notification) {
        persistenceWorker.flushNow()
        tap?.stop()
        tracker.stop()
    }

    private func setupMenuBar() {
        menuBarController = MenuBarController(viewModel: viewModel)
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

        DispatchQueue.main.async { [weak self] in
            self?.viewModel.rows = rows
        }
    }

    private static var countsFileURL: URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base
            .appendingPathComponent("KeyboardHitCounter", isDirectory: true)
            .appendingPathComponent("counts.json")
    }
}
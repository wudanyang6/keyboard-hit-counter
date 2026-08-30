import AppKit
import SwiftUI

/// 管理独立的统计窗口（今日/本周/总计），单例式复用，避免重复开窗。
public final class StatsWindowController: NSWindowController {
    public init(viewModel: StatsViewModel) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 480),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "按键统计"
        window.center()
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(rootView: StatsView(viewModel: viewModel))

        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func show() {
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
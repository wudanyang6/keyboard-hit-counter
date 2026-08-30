import AppKit
import SwiftUI
import ServiceManagement

public final class MenuBarController: NSObject {
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private let viewModel: StatusViewModel
    private let onOpenStats: () -> Void

    public init(
        viewModel: StatusViewModel,
        onOpenStats: @escaping () -> Void,
        onOpenSettings: @escaping () -> Void
    ) {
        self.viewModel = viewModel
        self.onOpenStats = onOpenStats
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        if let button = statusItem.button {
            button.image = NSImage(
                systemSymbolName: "keyboard",
                accessibilityDescription: "Keyboard Hit Counter"
            )
            button.action = #selector(handleClick(_:))
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: StatusView(viewModel: viewModel, onOpenSettings: onOpenSettings)
        )
    }

    @objc private func handleClick(_ sender: Any?) {
        guard NSApp.currentEvent?.type == .rightMouseUp else {
            togglePopover(sender)
            return
        }
        showContextMenu()
    }

    private func togglePopover(_ sender: Any?) {
        if popover.isShown {
            popover.performClose(sender)
        } else if let button = statusItem.button {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    private func showContextMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: "统计…", action: #selector(openStats), keyEquivalent: "")
            .target = self
        menu.addItem(.separator())
        menu.addItem(launchAtLoginItem())
        menu.addItem(.separator())
        menu.addItem(withTitle: "退出", action: #selector(quit), keyEquivalent: "")
            .target = self

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    /// 构造「开机自启动」菜单项，勾选状态反映当前登录项状态（每次打开菜单时重建）。
    private func launchAtLoginItem() -> NSMenuItem {
        let item = NSMenuItem(
            title: "开机自启动",
            action: #selector(toggleLaunchAtLogin),
            keyEquivalent: ""
        )
        item.target = self
        item.state = launchAtLoginEnabled ? .on : .off
        return item
    }

    private var launchAtLoginEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if launchAtLoginEnabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSLog("KeyboardHitCounter: 切换开机自启动失败: \(error)")
        }
    }

    @objc private func openStats() {
        onOpenStats()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func openAccessibilitySettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        ) else { return }
        NSWorkspace.shared.open(url)
    }
}
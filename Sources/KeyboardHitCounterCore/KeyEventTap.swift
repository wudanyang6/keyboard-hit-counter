import Foundation
import CoreFoundation
import CoreGraphics
import ApplicationServices

/// 全局键盘监听：listenOnly 事件 tap，挂专用高优先级线程。
/// 回调只调用 handler（即 CounterStore.incrementCurrentSlot），无锁、无分配。
public final class KeyEventTap {
    public enum TapError: Error {
        case notTrusted
        case failedToCreate
    }

    private let handler: () -> Void
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var runLoop: CFRunLoop?

    public init(handler: @escaping () -> Void) {
        self.handler = handler
    }

    public func start() -> Result<Void, TapError> {
        guard AXIsProcessTrusted() else {
            return .failure(.notTrusted)
        }

        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: Self.keyDownCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return .failure(.failedToCreate)
        }
        eventTap = tap

        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            return .failure(.failedToCreate)
        }
        runLoopSource = source

        let thread = Thread { [weak self] in
            guard let self, let source = self.runLoopSource else { return }
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            self.runLoop = CFRunLoopGetCurrent()
            CFRunLoopRun()
        }
        thread.qualityOfService = .userInteractive
        thread.name = "khc.event-tap"
        thread.start()

        return .success(())
    }

    public func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let runLoop {
            CFRunLoopStop(runLoop)
        }
        eventTap = nil
        runLoopSource = nil
        runLoop = nil
    }

    /// 非捕获 C 回调：经 userInfo 取回 self 并调用 handler。listenOnly 下返回值被系统忽略。
    private static let keyDownCallback: CGEventTapCallBack = { _, _, _, userInfo in
        guard let userInfo else { return nil }
        let tap = Unmanaged<KeyEventTap>.fromOpaque(userInfo).takeUnretainedValue()
        tap.handler()
        return nil
    }
}
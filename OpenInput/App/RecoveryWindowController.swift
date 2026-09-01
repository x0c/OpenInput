import AppKit
import SwiftUI

extension Notification.Name {
    /// 隐藏图标、再次打开或菜单「打开主窗口」时，出示恢复主窗口。
    static let openInputShowRecoveryWindow = Notification.Name("OpenInput.showRecoveryWindow")
}

/// 轻量恢复主窗口：带标题栏、点外面不关。禁止用输入小窗顶替。
@MainActor
final class RecoveryWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?

    func show() {
        if window == nil {
            let hosting = NSHostingController(rootView: RecoveryWindowView())
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 380, height: 400),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = String(localized: "recovery.windowTitle")
            window.contentViewController = hosting
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.identifier = NSUserInterfaceItemIdentifier("recovery")
            window.setContentSize(NSSize(width: 380, height: 400))
            window.center()
            self.window = window
        }

        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
    }
}

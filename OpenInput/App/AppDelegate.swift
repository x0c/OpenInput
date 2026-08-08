import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// 只有用户主动点击「退出」才放行，防止系统在 macOS 26 下
    /// 因菜单栏可见性变化等场景顺手终止菜单栏应用。
    private var allowTermination = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 常驻菜单栏应用，绝不切回 .regular（那会出现 Dock 图标）。
        NSApp.setActivationPolicy(.accessory)

        HotkeyService.shared.start {
            MainActor.assumeIsolated {
                InputPanelController.shared.toggle()
            }
        }

        // 先初始化偏好（触发旧键迁移），再读取登录启动偏好。
        _ = PreferencesStore.shared
        let preferred = UserDefaults.standard.bool(forKey: PreferencesKeys.launchAtLogin)
        LaunchAtLoginService.refreshIfNeeded(preferenceEnabled: preferred)

        AutoShowMonitor.shared.start()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        allowTermination ? .terminateNow : .terminateCancel
    }

    /// 用户主动退出：放行后正常终止。
    func requestTermination() {
        allowTermination = true
        NSApplication.shared.terminate(nil)
    }
}

import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Always stay a menu-bar app. Never flip to .regular (that creates Dock icons).
        NSApp.setActivationPolicy(.accessory)

        HotkeyService.shared.start {
            MainActor.assumeIsolated {
                InputPanelController.shared.toggle()
            }
        }

        let preferred = UserDefaults.standard.bool(forKey: "launchAtLogin")
        LaunchAtLoginService.refreshIfNeeded(preferenceEnabled: preferred)

        AutoShowMonitor.shared.start()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

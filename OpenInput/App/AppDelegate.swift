import AppKit
import MacKitCore
import MacKitLifecycle
import Sparkle
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// 供菜单与恢复窗口调用；SwiftUI 生命周期下对 `NSApp.delegate` 转型常会失败。
    private(set) static weak var shared: AppDelegate?

    /// 必须强持有更新控制器，否则自动检查会在启动后失效。
    private let updaterController = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )
    private let terminationGuard = TerminationGuard()
    private let recoveryWindowController = RecoveryWindowController()
    private var recoveryWindowObserver: NSObjectProtocol?

    override init() {
        super.init()
        AppDelegate.shared = self
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self
        // 常驻菜单栏应用，绝不切回 .regular（那会出现 Dock 图标）。
        NSApp.setActivationPolicy(.accessory)

        terminationGuard.isUpdateSessionInProgress = { [weak self] in
            self?.updaterController.updater.sessionInProgress ?? false
        }

        recoveryWindowObserver = NotificationCenter.default.addObserver(
            forName: .openInputShowRecoveryWindow,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.showRecoveryWindow()
            }
        }

        HotkeyService.shared.start {
            MainActor.assumeIsolated {
                InputPanelController.shared.toggle()
            }
        }

        // 先初始化偏好（触发旧键迁移），再刷新已有 LaunchAgent 路径。
        _ = PreferencesStore.shared
        let preferred = UserDefaults.standard.bool(forKey: PreferencesKeys.launchAtLogin)
        LaunchAtLoginService.refreshIfNeeded(preferenceEnabled: preferred)

        AutoShowMonitor.shared.start()
        TextRefinementService.shared.refreshAvailability()

        let isLoginLaunch = LoginLaunchDetector.isLaunchedAsLoginItem
        if MenuBarReopenPolicy.shouldShowRecoveryWindow(
            iconVisible: PreferencesStore.shared.menuBarIconVisible,
            isLoginLaunch: isLoginLaunch
        ) {
            showRecoveryWindow()
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        TextRefinementService.shared.refreshAvailability()
        PreferencesStore.shared.syncLaunchAtLoginFromSystem()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        terminationGuard.shouldTerminate() ? .terminateNow : .terminateCancel
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if MenuBarReopenPolicy.presentation(
            iconVisible: PreferencesStore.shared.menuBarIconVisible,
            isReopenOrLaunch: true
        ) == .showRecoveryWindow {
            showRecoveryWindow()
        }
        return true
    }

    func showRecoveryWindow() {
        recoveryWindowController.show()
    }

    /// 用户主动退出：放行后正常终止。
    func requestTermination() {
        terminationGuard.requestTermination()
    }

    /// 用户主动检查更新时由菜单调用，下载与安装交给系统更新流程。
    func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }
}

import SwiftUI

@main
struct OpenInputApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var preferences = PreferencesStore.shared
    private let refinement = TextRefinementService.shared

    var body: some Scene {
        MenuBarExtra(
            "OpenInput",
            systemImage: "text.cursor",
            isInserted: menuBarIconInserted
        ) {
            MenuBarContentView(refinement: refinement, preferences: preferences)
        }

        Settings {
            SettingsView()
        }

        #if DEBUG
        if #available(macOS 15, *) {
            Window("Settings inspection", id: "settings-inspection") {
                SettingsInspectionLauncher()
            }
            .defaultLaunchBehavior(CommandLine.arguments.contains("-OpenInputInspectSettings") ? .presented : .suppressed)
        }
        #endif
    }

    /// 键不存在时 PreferencesStore 已按显示处理；系统摘掉图标会把绑定写成 false。
    private var menuBarIconInserted: Binding<Bool> {
        Binding(
            get: { preferences.menuBarIconVisible },
            set: { preferences.menuBarIconVisible = $0 }
        )
    }
}

private struct MenuBarContentView: View {
    let refinement: TextRefinementService
    @Bindable var preferences: PreferencesStore

    var body: some View {
        Button("menu.show.panel") {
            InputPanelController.shared.show()
        }

        if refinement.canRevertLastCleanup {
            Button("menu.revertLastCleanup") {
                InputPanelController.shared.revertLastCleanup()
            }
        }

        Divider()

        Button("menu.openMainWindow") {
            AppDelegate.shared?.showRecoveryWindow()
        }

        Toggle("menu.launchAtLogin", isOn: Binding(
            get: { preferences.launchAtLogin },
            set: { preferences.setLaunchAtLogin($0) }
        ))

        if LaunchAtLoginService.currentStatus() == .needsApproval {
            Text("settings.general.launch.needsApproval")
            Button("menu.openLoginItems") {
                LaunchAtLoginService.openSystemSettings()
            }
        }

        Button("menu.hideMenuBarIcon") {
            preferences.menuBarIconVisible = false
        }

        Divider()

        SettingsLink { Text("menu.settings") }

        Button("menu.checkForUpdates") {
            AppDelegate.shared?.checkForUpdates()
        }

        Divider()

        Button("menu.quit") {
            AppDelegate.shared?.requestTermination()
        }
    }
}

#if DEBUG
private struct SettingsInspectionLauncher: View {
    @Environment(\.openSettings) private var openSettings
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        Text(verbatim: "Settings inspection").frame(width: 280, height: 100)
            .task {
                if CommandLine.arguments.contains("-OpenInputInspectDark") {
                    NSApp.appearance = NSAppearance(named: .darkAqua)
                } else {
                    NSApp.appearance = NSAppearance(named: .aqua)
                }
                openSettings()
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
                let windows = NSApp.windows.map { "\($0.title): visible=\($0.isVisible), frame=\($0.frame)" }.joined(separator: "\n")
                let directory = URL.homeDirectory.appending(path: ".config/openinput/development")
                do {
                    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                    try windows.write(to: directory.appending(path: "settings-inspection.txt"), atomically: true, encoding: .utf8)
                } catch { print("Settings inspection evidence failed: \(error)") }
                dismissWindow(id: "settings-inspection")
            }
    }
}
#endif

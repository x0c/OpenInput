import SwiftUI

/// 隐藏菜单栏图标后的恢复面：显示图标、开机自启、检查更新。不是输入小窗。
struct RecoveryWindowView: View {
    @State private var preferences = PreferencesStore.shared

    var body: some View {
        @Bindable var preferences = preferences

        Form {
            Section {
                LabeledContent("recovery.status") {
                    Text("recovery.status.running")
                }

                if !preferences.menuBarIconVisible {
                    Text("recovery.iconHiddenHint")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Toggle("menu.showMenuBarIcon", isOn: $preferences.menuBarIconVisible)

                Toggle("menu.launchAtLogin", isOn: Binding(
                    get: { preferences.launchAtLogin },
                    set: { preferences.setLaunchAtLogin($0) }
                ))

                if let message = preferences.launchAtLoginMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if LaunchAtLoginService.currentStatus() == .needsApproval {
                    Button("menu.openLoginItems") {
                        LaunchAtLoginService.openSystemSettings()
                    }
                }
            }

            Section {
                Button("menu.checkForUpdates") {
                    AppDelegate.shared?.checkForUpdates()
                }

                SettingsLink {
                    Text("menu.settings")
                }

                Button("menu.quit") {
                    AppDelegate.shared?.requestTermination()
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 380)
        .onAppear {
            preferences.syncLaunchAtLoginFromSystem()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            preferences.syncLaunchAtLoginFromSystem()
        }
    }
}

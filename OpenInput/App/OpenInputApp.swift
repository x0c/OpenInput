import SwiftUI

@main
struct OpenInputApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("OpenInput", systemImage: "text.cursor") {
            Button("显示输入小窗") {
                InputPanelController.shared.show()
            }

            Divider()

            SettingsLink {
                Text("设置…")
            }

            Divider()

            Button("退出 OpenInput") {
                NSApplication.shared.terminate(nil)
            }
        }

        Settings {
            SettingsView()
        }
    }
}

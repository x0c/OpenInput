import SwiftUI

@main
struct OpenInputApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("OpenInput", systemImage: "text.cursor") {
            Button("menu.show.panel") {
                InputPanelController.shared.show()
            }

            Divider()

            SettingsLink {
                Text("menu.settings")
            }

            Button("menu.checkForUpdates") {
                (NSApp.delegate as? AppDelegate)?.checkForUpdates()
            }

            Divider()

            Button("menu.quit") {
                (NSApp.delegate as? AppDelegate)?.requestTermination()
            }
        }

        Settings {
            SettingsView()
        }
    }
}

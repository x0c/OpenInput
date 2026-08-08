import SwiftUI
import AppKit

struct AutoShowSettingsView: View {
    @State private var memory = AppMemoryStore.shared
    @State private var accessibilityTrusted = AccessibilityPermission.isTrusted

    var body: some View {
        @Bindable var memory = memory

        VStack(spacing: 0) {
            Form {
                Section {
                    Toggle("settings.autoshow.enable", isOn: $memory.autoShowMasterEnabled)
                    Text("settings.autoshow.description")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("settings.autoshow.permission") {
                    HStack {
                        Image(systemName: accessibilityTrusted ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(accessibilityTrusted ? .green : .orange)
                        Text(accessibilityTrusted
                            ? "settings.autoshow.permission.granted"
                            : "settings.autoshow.permission.denied")
                        Spacer()
                        Button("settings.accessibility.open_settings") {
                            AccessibilityPermission.openSystemSettings()
                            accessibilityTrusted = AccessibilityPermission.isTrusted
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .padding([.horizontal, .top])

            HStack {
                Text("settings.autoshow.remembered")
                    .font(.headline)
                Spacer()
                Button("settings.autoshow.clear") {
                    memory.clear()
                }
                .disabled(memory.apps.isEmpty)
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)

            if memory.apps.isEmpty {
                ContentUnavailableView(
                    "settings.autoshow.empty.title",
                    systemImage: "app.badge.checkmark",
                    description: Text("settings.autoshow.empty.description")
                )
            } else {
                List {
                    ForEach(memory.apps) { app in
                        HStack(spacing: 10) {
                            Image(nsImage: appIcon(for: app.bundleIdentifier))
                                .resizable()
                                .frame(width: 28, height: 28)
                                .cornerRadius(6)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(app.appName)
                                Text(app.bundleIdentifier)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Toggle("settings.autoshow.toggle", isOn: Binding(
                                get: { app.autoShow },
                                set: { memory.setAutoShow(bundleIdentifier: app.bundleIdentifier, enabled: $0) }
                            ))
                            .labelsHidden()
                            .help(app.autoShow ? "settings.autoshow.on" : "settings.autoshow.off")
                        }
                        .contextMenu {
                            Button("settings.autoshow.remove", role: .destructive) {
                                memory.remove(bundleIdentifier: app.bundleIdentifier)
                            }
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
        .onAppear {
            accessibilityTrusted = AccessibilityPermission.isTrusted
            if accessibilityTrusted {
                AutoShowMonitor.shared.start()
            }
        }
        // 用户从系统设置返回后自动重检授权状态。
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            accessibilityTrusted = AccessibilityPermission.isTrusted
        }
    }

    private func appIcon(for bundleId: String) -> NSImage {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        return NSImage(systemSymbolName: "app", accessibilityDescription: nil)
            ?? NSImage(size: NSSize(width: 28, height: 28))
    }
}

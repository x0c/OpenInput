import SwiftUI
import AppKit

struct AutoShowSettingsView: View {
    @ObservedObject private var memory = AppMemoryStore.shared
    @State private var accessibilityTrusted = AccessibilityPermission.isTrusted

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    Toggle("启用应用记忆自动打开", isOn: $memory.autoShowMasterEnabled)
                    Text("在某个 App 里用 OpenInput 成功插入过文本后，下次在该 App 的输入框聚焦时会自动打开小窗；若你主动关闭（esc / ✕），则不再自动打开。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("辅助功能") {
                    HStack {
                        Image(systemName: accessibilityTrusted ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(accessibilityTrusted ? .green : .orange)
                        Text(accessibilityTrusted ? "已授权（自动打开需要此权限）" : "未授权 — 无法检测输入框")
                        Spacer()
                        Button("打开系统设置…") {
                            AccessibilityPermission.openSystemSettings()
                            accessibilityTrusted = AccessibilityPermission.isTrusted
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .padding([.horizontal, .top])

            HStack {
                Text("已记忆的应用")
                    .font(.headline)
                Spacer()
                Button("清空") {
                    memory.clear()
                }
                .disabled(memory.apps.isEmpty)
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)

            if memory.apps.isEmpty {
                ContentUnavailableView(
                    "暂无记忆",
                    systemImage: "app.badge.checkmark",
                    description: Text("在任意 App 中用小窗插入一次文本后，会出现在这里")
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
                            Toggle("自动打开", isOn: Binding(
                                get: { app.autoShow },
                                set: { memory.setAutoShow(bundleIdentifier: app.bundleIdentifier, enabled: $0) }
                            ))
                            .labelsHidden()
                            .help(app.autoShow ? "自动打开中" : "已关闭自动打开")
                        }
                        .contextMenu {
                            Button("移除记忆", role: .destructive) {
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
    }

    private func appIcon(for bundleId: String) -> NSImage {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        return NSImage(systemSymbolName: "app", accessibilityDescription: nil)
            ?? NSImage(size: NSSize(width: 28, height: 28))
    }
}

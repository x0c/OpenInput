import SwiftUI
import KeyboardShortcuts

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("通用", systemImage: "gearshape") }
            ShortcutsSettingsView()
                .tabItem { Label("快捷键", systemImage: "keyboard") }
            AutoShowSettingsView()
                .tabItem { Label("应用记忆", systemImage: "app.badge.checkmark") }
            HistorySettingsView()
                .tabItem { Label("历史", systemImage: "clock") }
            AppearanceSettingsView()
                .tabItem { Label("外观", systemImage: "paintpalette") }
            AboutSettingsView()
                .tabItem { Label("关于", systemImage: "info.circle") }
        }
        .frame(width: 520, height: 400)
    }
}

struct GeneralSettingsView: View {
    @ObservedObject private var preferences = PreferencesStore.shared
    @State private var accessibilityTrusted = AccessibilityPermission.isTrusted

    var body: some View {
        Form {
            Section {
                Toggle("登录时启动", isOn: Binding(
                    get: { preferences.launchAtLogin },
                    set: { preferences.setLaunchAtLogin($0) }
                ))
                if let message = preferences.launchAtLoginMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                Picker("默认窗口大小", selection: $preferences.defaultWindowSize) {
                    ForEach(DefaultWindowSize.allCases) { size in
                        Text(size.displayName).tag(size)
                    }
                }
                .onChange(of: preferences.defaultWindowSize) { _, _ in
                    preferences.resetWindowSizeToDefault()
                    InputPanelController.shared.updateBorder()
                }

                Picker("插入方式", selection: $preferences.insertionMethod) {
                    ForEach(InsertionMethod.allCases) { method in
                        Text(method.displayName).tag(method)
                    }
                }
                .disabled(true)
                Text("当前仅支持粘贴；模拟键入将在后续版本提供。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle("自动在中英文之间添加空格", isOn: $preferences.autoAddSpaces)
                    .disabled(true)
                Text("智能优化将在后续版本提供。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("辅助功能权限") {
                HStack {
                    Image(systemName: accessibilityTrusted ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(accessibilityTrusted ? .green : .orange)
                    Text(accessibilityTrusted ? "已授权" : "未授权 — 无法自动粘贴到其他应用")
                    Spacer()
                    Button(accessibilityTrusted ? "刷新" : "打开系统设置…") {
                        AccessibilityPermission.openSystemSettings()
                        accessibilityTrusted = AccessibilityPermission.isTrusted
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear {
            accessibilityTrusted = AccessibilityPermission.isTrusted
            preferences.syncLaunchAtLoginFromSystem()
        }
    }
}

struct ShortcutsSettingsView: View {
    var body: some View {
        Form {
            Section {
                KeyboardShortcuts.Recorder("显示 / 隐藏输入小窗", name: .togglePanel)
            }
            Section("小窗内快捷键") {
                LabeledContent("插入并关闭", value: "↩ Return")
                LabeledContent("插入换行", value: "⇧↩ Shift+Return")
                LabeledContent("关闭 / 退出历史", value: "esc")
                LabeledContent("翻阅历史", value: "↑ / ↓")
                LabeledContent("删除当前历史", value: "⌘⌫")
                LabeledContent("插入 Tab", value: "Tab")
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

struct AppearanceSettingsView: View {
    @ObservedObject private var preferences = PreferencesStore.shared

    var body: some View {
        Form {
            Section("边框颜色") {
                Picker("颜色", selection: $preferences.borderColor) {
                    ForEach(BorderColorOption.allCases) { color in
                        HStack {
                            Circle()
                                .fill(Color(nsColor: color.nsColor))
                                .frame(width: 12, height: 12)
                            Text(color.displayName)
                        }
                        .tag(color)
                    }
                }
                .pickerStyle(.radioGroup)
                .onChange(of: preferences.borderColor) { _, _ in
                    InputPanelController.shared.updateBorder()
                }
            }

            Section("透明度") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("小窗不透明度")
                        Spacer()
                        Text("\(Int((preferences.panelOpacity * 100).rounded()))%")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Slider(value: $preferences.panelOpacity, in: 0.35...1.0, step: 0.05)
                        .onChange(of: preferences.panelOpacity) { _, _ in
                            InputPanelController.shared.updateBorder()
                        }
                    Text("最低 35%，避免小窗几乎看不见。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

struct AboutSettingsView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "text.cursor")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("智能输入小窗")
                .font(.title2.weight(.semibold))
            Text("OpenInput")
                .foregroundStyle(.secondary)
            Text("版本 \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("在不便编辑的输入框中，用悬浮小窗完成复杂文本后再一键插入。")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

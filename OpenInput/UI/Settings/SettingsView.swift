import AppKit
import SwiftUI
import KeyboardShortcuts

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("settings.general", systemImage: "gearshape") }
            ShortcutsSettingsView()
                .tabItem { Label("settings.shortcuts", systemImage: "keyboard") }
            AutoShowSettingsView()
                .tabItem { Label("settings.appMemory", systemImage: "app.badge.checkmark") }
            HistorySettingsView()
                .tabItem { Label("settings.history", systemImage: "clock") }
            AppearanceSettingsView()
                .tabItem { Label("settings.appearance", systemImage: "paintpalette") }
            AboutSettingsView()
                .tabItem { Label("settings.about", systemImage: "info.circle") }
        }
        .frame(width: 520, height: 400)
    }
}

struct GeneralSettingsView: View {
    private enum FocusTarget: Hashable {
        case accessibilitySettings
    }

    @State private var preferences = PreferencesStore.shared
    @State private var accessibilityTrusted = AccessibilityPermission.isTrusted
    @FocusState private var focusedControl: FocusTarget?

    var body: some View {
        @Bindable var preferences = preferences

        Form {
            Section {
                Toggle("settings.general.launchAtLogin", isOn: Binding(
                    get: { preferences.launchAtLogin },
                    set: { preferences.setLaunchAtLogin($0) }
                ))
                if let message = preferences.launchAtLoginMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.orange)
                    if LaunchAtLoginService.currentStatus() == .needsApproval {
                        Button("settings.accessibility.open_settings") {
                            guard let settingsURL = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") else {
                                return
                            }
                            NSWorkspace.shared.open(settingsURL)
                        }
                    }
                }

                Picker("settings.general.windowSize", selection: $preferences.defaultWindowSize) {
                    ForEach(DefaultWindowSize.allCases) { size in
                        Text(size.displayName).tag(size)
                    }
                }
                .onChange(of: preferences.defaultWindowSize) { _, _ in
                    preferences.resetWindowSizeToDefault()
                    InputPanelController.shared.updateBorder()
                }

                Picker("settings.general.insertion", selection: $preferences.insertionMethod) {
                    ForEach(InsertionMethod.allCases) { method in
                        Text(method.displayName).tag(method)
                    }
                }
                .disabled(true)
                Text("settings.general.insertion.note")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle("settings.general.autoSpaces", isOn: $preferences.autoAddSpaces)
                    .disabled(true)
                Text("settings.general.autoSpaces.note")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("settings.general.accessibility") {
                HStack {
                    Image(systemName: accessibilityTrusted ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(accessibilityTrusted ? .green : .orange)
                    Text(accessibilityTrusted
                        ? "settings.general.accessibility.granted"
                        : "settings.general.accessibility.denied")
                    Spacer()
                    Button(accessibilityTrusted ? "settings.general.refresh" : "settings.accessibility.open_settings") {
                        AccessibilityPermission.openSystemSettings()
                        accessibilityTrusted = AccessibilityPermission.isTrusted
                    }
                    .focusEffectDisabled()
                    .focused($focusedControl, equals: .accessibilitySettings)
                    .overlay {
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .strokeBorder(focusedControl == .accessibilitySettings ? Color.accentColor.opacity(0.78) : .clear, lineWidth: 1.5)
                    }
                    .accessibilityHint(Text("settings.accessibility.open.accessibility.hint"))
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear {
            accessibilityTrusted = AccessibilityPermission.isTrusted
            preferences.syncLaunchAtLoginFromSystem()
        }
        // 用户从系统设置返回后自动重检授权状态。
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            accessibilityTrusted = AccessibilityPermission.isTrusted
        }
    }
}

struct ShortcutsSettingsView: View {
    @FocusState private var recorderFocused: Bool

    var body: some View {
        Form {
            Section {
                KeyboardShortcuts.Recorder(
                    String(localized: "settings.shortcuts.showHide"),
                    name: .togglePanel
                )
                .padding(4)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(recorderFocused ? Color.accentColor.opacity(0.12) : .clear)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(recorderFocused ? Color.accentColor.opacity(0.78) : .clear, lineWidth: 1.5)
                }
                .focusEffectDisabled()
                .focused($recorderFocused)
                .accessibilityHint(Text("settings.shortcuts.recorder.accessibility.hint"))
            }
            Section("settings.shortcuts.inner") {
                LabeledContent("settings.shortcuts.insert", value: "↩ Return")
                LabeledContent("settings.shortcuts.newline", value: "⇧↩ Shift+Return")
                LabeledContent("settings.shortcuts.close", value: "esc")
                LabeledContent("settings.shortcuts.browse", value: "↑ / ↓")
                LabeledContent("settings.shortcuts.deleteHistory", value: "⌘⌫")
                LabeledContent("settings.shortcuts.tab", value: "Tab")
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

struct AppearanceSettingsView: View {
    @State private var preferences = PreferencesStore.shared

    var body: some View {
        @Bindable var preferences = preferences

        Form {
            Section("settings.appearance.border") {
                Picker("settings.appearance.color", selection: $preferences.borderColor) {
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

            Section("settings.appearance.opacity") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("settings.appearance.opacity.value")
                        Spacer()
                        Text("\(Int((preferences.panelOpacity * 100).rounded()))%")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Slider(value: $preferences.panelOpacity, in: 0.35...1.0, step: 0.05)
                        .onChange(of: preferences.panelOpacity) { _, _ in
                            InputPanelController.shared.updateBorder()
                        }
                    Text("settings.appearance.opacity.note")
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
    /// 跟随语言变化的显示名（InfoPlist.strings 提供 zh-Hans / en 两版）。
    private var appDisplayName: String {
        let localized = Bundle.main.localizedInfoDictionary?["CFBundleDisplayName"] as? String
        return localized ?? (Bundle.main.infoDictionary?["CFBundleDisplayName"] as? String ?? "OpenInput")
    }

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "text.cursor")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text(verbatim: appDisplayName)
                .font(.title2.weight(.semibold))
            Text(verbatim: "OpenInput")
                .foregroundStyle(.secondary)
            Text("settings.about.version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("settings.about.description")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

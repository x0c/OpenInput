import AppKit
import SwiftUI
import KeyboardShortcuts

struct SettingsView: View {
    @AppStorage(PreferencesKeys.settingsPane) private var pane = PreferencesKeys.settingsPaneDefault

    var body: some View {
        tabs
            .frame(width: 480)
            .fixedSize(horizontal: false, vertical: true)
            .focusEffectDisabled()
            .background(SettingsWindowObserver())
            .onExitCommand { SettingsWindowController.shared.close() }
    }

    @ViewBuilder
    private var tabs: some View {
        if #available(macOS 15, *) {
            TabView(selection: $pane) {
                Tab("settings.general", systemImage: "gearshape", value: SettingsPane.general) { GeneralSettingsView() }
                Tab("settings.voice", systemImage: "mic", value: SettingsPane.voice) { VoiceSettingsView() }
                Tab("settings.appMemory", systemImage: "app.badge.checkmark", value: SettingsPane.apps) { AutoShowSettingsView() }
                Tab("settings.history", systemImage: "clock", value: SettingsPane.history) { HistorySettingsView() }
            }
        } else {
            TabView(selection: $pane) {
                GeneralSettingsView().tabItem { Label("settings.general", systemImage: "gearshape") }.tag(SettingsPane.general)
                VoiceSettingsView().tabItem { Label("settings.voice", systemImage: "mic") }.tag(SettingsPane.voice)
                AutoShowSettingsView().tabItem { Label("settings.appMemory", systemImage: "app.badge.checkmark") }.tag(SettingsPane.apps)
                HistorySettingsView().tabItem { Label("settings.history", systemImage: "clock") }.tag(SettingsPane.history)
            }
        }
    }
}

struct GeneralSettingsView: View {
    @State private var preferences = PreferencesStore.shared
    @State private var accessibilityTrusted = AccessibilityPermission.isTrusted

    var body: some View {
        @Bindable var preferences = preferences
        Form {
            Section {
                KeyboardShortcuts.Recorder(String(localized: "settings.shortcuts.showHide"), name: .togglePanel)
                    .help(Text("settings.shortcuts.key_help"))
                Picker("settings.general.windowSize", selection: $preferences.defaultWindowSize) {
                    ForEach(DefaultWindowSize.allCases) { Text($0.displayName).tag($0) }
                }
                .onChange(of: preferences.defaultWindowSize) { _, _ in
                    preferences.resetWindowSizeToDefault()
                    InputPanelController.shared.updateBorder()
                }
                Picker("settings.appearance.color", selection: $preferences.borderColor) {
                    ForEach(BorderColorOption.allCases) { Text($0.displayName).tag($0) }
                }
                .onChange(of: preferences.borderColor) { _, _ in InputPanelController.shared.updateBorder() }
                LabeledContent("settings.appearance.opacity") {
                    HStack(spacing: 8) {
                        Text(preferences.panelOpacity, format: .percent.precision(.fractionLength(0)))
                            .foregroundStyle(.secondary).monospacedDigit().frame(width: 38, alignment: .trailing)
                        Slider(value: $preferences.panelOpacity, in: 0.35...1)
                            .labelsHidden().frame(width: 140)
                            .accessibilityLabel(Text("settings.appearance.opacity"))
                            .onChange(of: preferences.panelOpacity) { _, _ in InputPanelController.shared.updateBorder() }
                    }
                }
            }
            Section {
                LabeledContent {
                    if accessibilityTrusted {
                        Text("settings.general.accessibility.granted").foregroundStyle(.secondary)
                    } else {
                        Button("settings.accessibility.open_settings") { AccessibilityPermission.openSystemSettings() }
                    }
                } label: {
                    Text("settings.general.accessibility")
                }
            }
            Section {
                Toggle("menu.showMenuBarIcon", isOn: $preferences.menuBarIconVisible)
                Toggle("settings.general.launchAtLogin", isOn: Binding(
                    get: { preferences.launchAtLogin },
                    set: { preferences.setLaunchAtLogin($0) }
                ))
                if let message = preferences.launchAtLoginMessage {
                    if LaunchAtLoginService.currentStatus() == .needsApproval {
                        LabeledContent {
                            Button("menu.openLoginItems") { LaunchAtLoginService.openSystemSettings() }
                        } label: {
                            Label { Text(message).foregroundStyle(.secondary) } icon: {
                                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                            }
                        }
                    } else { Text(message).font(.caption).foregroundStyle(.orange) }
                }
            }
            Section { SettingsAboutRow() }
        }
        .settingsFormStyle(fallbackHeight: 540)
        .onAppear(perform: refresh)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in refresh() }
    }

    private func refresh() {
        accessibilityTrusted = AccessibilityPermission.isTrusted
        preferences.syncLaunchAtLoginFromSystem()
    }
}

private struct SettingsAboutRow: View {
    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 32, height: 32).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: "OpenInput").fontWeight(.medium)
                Text(verbatim: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")
                    .font(.subheadline).foregroundStyle(.secondary)
            }.accessibilityElement(children: .combine)
            Spacer(minLength: 8)
            Button("menu.checkForUpdates") { AppDelegate.shared?.checkForUpdates() }
            Button("settings.quit.short") { AppDelegate.shared?.requestTermination() }
        }
    }
}

extension View {
    func settingsFormStyle(fallbackHeight: CGFloat) -> some View {
        formStyle(.grouped).toggleStyle(.switch).scrollDisabled(true)
            .modifier(SettingsFormHeight(fallbackHeight: fallbackHeight))
    }
}

private struct SettingsFormHeight: ViewModifier {
    let fallbackHeight: CGFloat
    @State private var contentHeight: CGFloat?

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 15, *) {
            content.onScrollGeometryChange(for: CGFloat.self) { ceil($0.contentSize.height) } action: { _, height in
                if height > 0 { contentHeight = height }
            }.frame(height: contentHeight ?? fallbackHeight)
        } else { content.frame(height: fallbackHeight) }
    }
}

import AppKit
import SwiftUI

struct VoiceSettingsView: View {
    private enum FocusTarget: Hashable {
        case microphoneSettings
        case addReplacement
    }

    @State private var preferences = PreferencesStore.shared
    @State private var dictation = SpeechDictationService.shared
    @State private var refinement = TextRefinementService.shared
    @State private var microphoneStatus = MicrophonePermission.status
    @State private var locales: [Locale] = []
    @State private var newFrom = ""
    @State private var newTo = ""
    @FocusState private var focusedControl: FocusTarget?

    var body: some View {
        @Bindable var preferences = preferences

        Form {
            Section {
                Toggle("settings.voice.autoStart", isOn: $preferences.voiceAutoStartOnShow)
                    .disabled(!dictation.isSupportedByOS)
                Text("settings.voice.autoStart.note")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !dictation.isSupportedByOS {
                    Text("panel.voice.unavailable.os")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            Section("settings.voice.mic") {
                HStack {
                    Image(systemName: microphoneStatus == .authorized ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(microphoneStatus == .authorized ? .green : .orange)
                    Text(microphoneStatusText)
                    Spacer()
                    Button(microphoneStatus == .authorized
                           ? "settings.general.refresh"
                           : "settings.accessibility.open_settings") {
                        if microphoneStatus == .notDetermined {
                            Task {
                                _ = await MicrophonePermission.request()
                                microphoneStatus = MicrophonePermission.status
                            }
                        } else if microphoneStatus != .authorized {
                            MicrophonePermission.openSystemSettings()
                        }
                        microphoneStatus = MicrophonePermission.status
                    }
                    .focusEffectDisabled()
                    .focused($focusedControl, equals: .microphoneSettings)
                    .overlay {
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .strokeBorder(focusedControl == .microphoneSettings ? Color.accentColor.opacity(0.78) : .clear, lineWidth: 1.5)
                    }
                    .accessibilityHint(Text("settings.voice.mic.open.accessibility.hint"))
                }
            }

            Section("settings.voice.language") {
                Picker("settings.voice.language", selection: $preferences.voiceLocaleIdentifier) {
                    Text("settings.voice.language.system").tag("")
                    ForEach(locales, id: \.identifier) { locale in
                        Text(localeDisplayName(locale)).tag(locale.identifier(.bcp47))
                    }
                }
                .disabled(!dictation.isSupportedByOS)
            }

            Section("settings.voice.refine") {
                Toggle("settings.voice.refine.enable", isOn: $preferences.voiceAutoRefine)
                Text("settings.voice.refine.note")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let reason = refinement.unavailableReason {
                    Text(reason)
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else if preferences.voiceAutoRefine {
                    Text("settings.voice.refine.ready")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if refinement.isBreakerTripped {
                    Button("settings.voice.refine.resetBreaker") {
                        refinement.resetBreaker()
                        preferences.voiceAutoRefine = true
                    }
                }
            }

            Section("settings.voice.replacements") {
                Text("settings.voice.replacements.note")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(preferences.voiceReplacements) { item in
                    HStack {
                        Text(item.from)
                        Image(systemName: "arrow.right")
                            .foregroundStyle(.secondary)
                        Text(item.to)
                        Spacer()
                        Button {
                            preferences.voiceReplacements.removeAll { $0.id == item.id }
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text("common.delete"))
                    }
                }
                HStack {
                    TextField("settings.voice.replacements.from", text: $newFrom)
                        .textFieldStyle(.plain)
                        .focusEffectDisabled()
                    Image(systemName: "arrow.right")
                        .foregroundStyle(.secondary)
                    TextField("settings.voice.replacements.to", text: $newTo)
                        .textFieldStyle(.plain)
                        .focusEffectDisabled()
                    Button("settings.voice.replacements.add") {
                        addReplacement()
                    }
                    .disabled(newFrom.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .focusEffectDisabled()
                    .focused($focusedControl, equals: .addReplacement)
                    .overlay {
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .strokeBorder(focusedControl == .addReplacement ? Color.accentColor.opacity(0.78) : .clear, lineWidth: 1.5)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear {
            microphoneStatus = MicrophonePermission.status
            refinement.refreshAvailability()
            Task {
                if #available(macOS 26.0, *) {
                    locales = await SpeechDictationService.shared.supportedLocales()
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            microphoneStatus = MicrophonePermission.status
            refinement.refreshAvailability()
        }
    }

    private var microphoneStatusText: LocalizedStringKey {
        switch microphoneStatus {
        case .authorized:
            return "settings.voice.mic.granted"
        case .denied, .restricted:
            return "settings.voice.mic.denied"
        case .notDetermined:
            return "settings.voice.mic.undetermined"
        @unknown default:
            return "settings.voice.mic.denied"
        }
    }

    private func localeDisplayName(_ locale: Locale) -> String {
        Locale.current.localizedString(forIdentifier: locale.identifier) ?? locale.identifier(.bcp47)
    }

    private func addReplacement() {
        let from = newFrom.trimmingCharacters(in: .whitespacesAndNewlines)
        let to = newTo.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !from.isEmpty else { return }
        preferences.voiceReplacements.append(VoiceReplacement(from: from, to: to))
        newFrom = ""
        newTo = ""
    }
}

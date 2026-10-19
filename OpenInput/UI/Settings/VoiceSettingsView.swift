import AVFoundation
import AppKit
import SwiftUI

struct VoiceSettingsView: View {
    @State private var preferences = PreferencesStore.shared
    @State private var dictation = SpeechDictationService.shared
    @State private var refinement = TextRefinementService.shared
    @State private var microphoneStatus = MicrophonePermission.status
    @State private var locales: [Locale] = []
    @State private var newFrom = ""
    @State private var newTo = ""

    var body: some View {
        @Bindable var preferences = preferences

        Form {
            Section {
                Toggle("settings.voice.auto_start_short", isOn: $preferences.voiceAutoStartOnShow)
                    .disabled(!dictation.isSupportedByOS)
                    .help(Text("settings.voice.autoStart.note"))
                if !dictation.isSupportedByOS {
                    Text("panel.voice.unavailable.os").font(.caption).foregroundStyle(.orange)
                }
                Picker("settings.voice.language", selection: $preferences.voiceLocaleIdentifier) {
                    Text("settings.voice.language.system").tag("")
                    ForEach(locales, id: \.identifier) { locale in
                        Text(localeDisplayName(locale)).tag(locale.identifier(.bcp47))
                    }
                }.disabled(!dictation.isSupportedByOS)
                LabeledContent {
                    if microphoneStatus == .authorized {
                        Text(microphoneStatusText).foregroundStyle(.secondary)
                    } else {
                        Button(microphoneStatus == .notDetermined ? "settings.voice.mic.allow" : "settings.accessibility.open_settings") {
                            if microphoneStatus == .notDetermined {
                                Task {
                                    _ = await MicrophonePermission.request()
                                    microphoneStatus = MicrophonePermission.status
                                }
                            } else { MicrophonePermission.openSystemSettings() }
                            microphoneStatus = MicrophonePermission.status
                        }
                    }
                } label: { Text("settings.voice.mic") }
            }
            Section {
                Toggle("settings.voice.cleanup_short", isOn: $preferences.voiceAutoRefine)
                    .help(Text("settings.voice.refine.note"))
                if let reason = refinement.unavailableReason {
                    Text(reason).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                if refinement.isBreakerTripped {
                    LabeledContent("settings.voice.refine") {
                        Button("settings.voice.refine.resetBreaker") {
                            refinement.resetBreaker()
                            preferences.voiceAutoRefine = true
                        }
                    }
                }
            }
            Section("settings.voice.replacements") {
                if !preferences.voiceReplacements.isEmpty {
                    List {
                        ForEach(preferences.voiceReplacements) { item in
                            HStack {
                                Text(item.from)
                                Image(systemName: "arrow.right").foregroundStyle(.secondary).accessibilityHidden(true)
                                Text(item.to)
                                Spacer()
                                Button(role: .destructive) {
                                    preferences.voiceReplacements.removeAll { $0.id == item.id }
                                } label: { Image(systemName: "minus.circle") }
                                    .buttonStyle(.borderless)
                                    .accessibilityLabel(Text("common.delete"))
                            }
                        }
                    }
                    .frame(height: min(CGFloat(preferences.voiceReplacements.count) * 34 + 16, 170))
                    .scrollDisabled(false)
                }
                HStack {
                    TextField("settings.voice.replacements.from", text: $newFrom).textFieldStyle(.roundedBorder).labelsHidden()
                    Image(systemName: "arrow.right").foregroundStyle(.secondary).accessibilityHidden(true)
                    TextField("settings.voice.replacements.to", text: $newTo).textFieldStyle(.roundedBorder).labelsHidden()
                    Button("settings.voice.replacements.add") { addReplacement() }
                        .disabled(newFrom.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }.help(Text("settings.voice.replacements.note"))
            }
        }
        .settingsFormStyle(fallbackHeight: 590)
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

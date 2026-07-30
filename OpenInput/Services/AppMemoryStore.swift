import Foundation
import AppKit
import Combine

struct RememberedApp: Identifiable, Codable, Equatable, Hashable {
    var id: String { bundleIdentifier }
    let bundleIdentifier: String
    var appName: String
    var autoShow: Bool
    var updatedAt: Date
}

/// Remembers which apps should auto-open the input panel.
/// - Successful insert → enable auto-show for that app
/// - Active close (esc / ✕ / hotkey hide) → disable auto-show for that app
@MainActor
final class AppMemoryStore: ObservableObject {
    static let shared = AppMemoryStore()

    @Published private(set) var apps: [RememberedApp] = []

    @Published var autoShowMasterEnabled: Bool {
        didSet { defaults.set(autoShowMasterEnabled, forKey: Keys.master) }
    }

    private let defaults = UserDefaults.standard
    private let fileURL: URL

    private enum Keys {
        static let master = "autoShowMasterEnabled"
    }

    private init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = support.appendingPathComponent("OpenInput", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("app-memory.json")

        if defaults.object(forKey: Keys.master) == nil {
            autoShowMasterEnabled = true
        } else {
            autoShowMasterEnabled = defaults.bool(forKey: Keys.master)
        }
        load()
    }

    func shouldAutoShow(bundleIdentifier: String?) -> Bool {
        guard autoShowMasterEnabled, let bundleIdentifier else { return false }
        return apps.first(where: { $0.bundleIdentifier == bundleIdentifier })?.autoShow == true
    }

    /// Called after user successfully used OpenInput to insert text into an app.
    func rememberUsed(bundleIdentifier: String?, appName: String?) {
        guard let bundleIdentifier, !bundleIdentifier.isEmpty else { return }
        upsert(
            bundleIdentifier: bundleIdentifier,
            appName: appName ?? bundleIdentifier,
            autoShow: true
        )
    }

    /// Called when user actively dismisses the panel for a captured app.
    func rememberDismissed(bundleIdentifier: String?, appName: String?) {
        guard let bundleIdentifier, !bundleIdentifier.isEmpty else { return }
        upsert(
            bundleIdentifier: bundleIdentifier,
            appName: appName ?? bundleIdentifier,
            autoShow: false
        )
    }

    func setAutoShow(bundleIdentifier: String, enabled: Bool) {
        guard let index = apps.firstIndex(where: { $0.bundleIdentifier == bundleIdentifier }) else { return }
        apps[index].autoShow = enabled
        apps[index].updatedAt = Date()
        save()
    }

    func remove(bundleIdentifier: String) {
        apps.removeAll { $0.bundleIdentifier == bundleIdentifier }
        save()
    }

    func clear() {
        apps.removeAll()
        save()
    }

    private func upsert(bundleIdentifier: String, appName: String, autoShow: Bool) {
        if let index = apps.firstIndex(where: { $0.bundleIdentifier == bundleIdentifier }) {
            apps[index].appName = appName
            apps[index].autoShow = autoShow
            apps[index].updatedAt = Date()
        } else {
            apps.insert(
                RememberedApp(
                    bundleIdentifier: bundleIdentifier,
                    appName: appName,
                    autoShow: autoShow,
                    updatedAt: Date()
                ),
                at: 0
            )
        }
        apps.sort { $0.updatedAt > $1.updatedAt }
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([RememberedApp].self, from: data) else { return }
        apps = decoded.sorted { $0.updatedAt > $1.updatedAt }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(apps) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}

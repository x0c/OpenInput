import Foundation
import Observation
import os

struct RememberedApp: Identifiable, Codable, Equatable, Hashable {
    var id: String { bundleIdentifier }
    let bundleIdentifier: String
    var appName: String
    var autoShow: Bool
    var updatedAt: Date
}

/// 按应用记忆自动打开行为。
/// - 成功插入文本 → 开启该应用的自动打开
/// - 主动关闭（esc / ✕ / 热键隐藏）→ 关闭该应用的自动打开
@MainActor
@Observable
final class AppMemoryStore {
    static let shared = AppMemoryStore()

    private(set) var apps: [RememberedApp] = []

    var autoShowMasterEnabled: Bool {
        didSet { defaults.set(autoShowMasterEnabled, forKey: AppMemoryKeys.autoShowMaster) }
    }

    private let defaults = UserDefaults.standard
    private let fileURL: URL
    private let logger = Logger(subsystem: "com.x0c.openinput", category: "AppMemoryStore")

    /// 偏好键与默认值成对集中声明。
    private enum AppMemoryKeys {
        static let autoShowMaster = "appMemory.autoShowMaster"
        static let autoShowMasterDefault = true

        static let legacyAutoShowMaster = "autoShowMasterEnabled"
    }

    private init() {
        // 旧键名迁移：读到旧值写入新键并删除旧键。
        if defaults.object(forKey: AppMemoryKeys.autoShowMaster) == nil,
           let legacy = defaults.object(forKey: AppMemoryKeys.legacyAutoShowMaster) {
            defaults.set(legacy, forKey: AppMemoryKeys.autoShowMaster)
            defaults.removeObject(forKey: AppMemoryKeys.legacyAutoShowMaster)
        }

        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = support.appendingPathComponent("OpenInput", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("app-memory.json")

        if defaults.object(forKey: AppMemoryKeys.autoShowMaster) == nil {
            autoShowMasterEnabled = AppMemoryKeys.autoShowMasterDefault
        } else {
            autoShowMasterEnabled = defaults.bool(forKey: AppMemoryKeys.autoShowMaster)
        }
        load()
    }

    func shouldAutoShow(bundleIdentifier: String?) -> Bool {
        guard autoShowMasterEnabled, let bundleIdentifier else { return false }
        return apps.first(where: { $0.bundleIdentifier == bundleIdentifier })?.autoShow == true
    }

    /// 用户成功用 OpenInput 向某个应用插入文本后调用。
    func rememberUsed(bundleIdentifier: String?, appName: String?) {
        guard let bundleIdentifier, !bundleIdentifier.isEmpty else { return }
        upsert(
            bundleIdentifier: bundleIdentifier,
            appName: appName ?? bundleIdentifier,
            autoShow: true
        )
    }

    /// 用户主动关闭小窗后调用。
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
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            apps = try JSONDecoder().decode([RememberedApp].self, from: data).sorted { $0.updatedAt > $1.updatedAt }
        } catch {
            // 文件损坏时不崩溃、不清空原文件，回退到空记忆。
            logger.error("读取应用记忆失败，回退为空列表：\(error.localizedDescription)")
        }
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(apps)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            logger.error("保存应用记忆失败：\(error.localizedDescription)")
        }
    }
}

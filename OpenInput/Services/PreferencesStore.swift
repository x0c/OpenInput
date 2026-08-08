import Foundation
import AppKit
import Observation
import ServiceManagement

/// 偏好键与默认值成对集中声明；统一「域.名」点分命名，禁止在使用处散落字面量键。
enum PreferencesKeys {
    static let borderColor = "panel.borderColor"
    static let panelOpacity = "panel.opacity"
    static let defaultWindowSize = "panel.defaultSize"
    static let insertionMethod = "insertion.method"
    static let autoAddSpaces = "insertion.autoSpaces"
    static let launchAtLogin = "general.launchAtLogin"
    static let windowFrame = "panel.windowFrame"

    static let borderColorDefault = BorderColorOption.blue
    static let panelOpacityDefault = 1.0
    static let defaultWindowSizeDefault = DefaultWindowSize.regular
    static let insertionMethodDefault = InsertionMethod.paste
    static let autoAddSpacesDefault = false
    static let launchAtLoginDefault = false
}

/// 全局偏好设置：所有设置项的唯一真相来源，视图与业务层只跟它打交道。
@MainActor
@Observable
final class PreferencesStore {
    static let shared = PreferencesStore()

    var borderColor: BorderColorOption {
        didSet { defaults.set(borderColor.rawValue, forKey: PreferencesKeys.borderColor) }
    }

    /// 面板不透明度，收敛到 0.35...1.0
    var panelOpacity: Double {
        didSet {
            let clamped = Self.clampOpacity(panelOpacity)
            if clamped != panelOpacity {
                panelOpacity = clamped
                return
            }
            defaults.set(clamped, forKey: PreferencesKeys.panelOpacity)
        }
    }

    var defaultWindowSize: DefaultWindowSize {
        didSet { defaults.set(defaultWindowSize.rawValue, forKey: PreferencesKeys.defaultWindowSize) }
    }

    var insertionMethod: InsertionMethod {
        didSet { defaults.set(insertionMethod.rawValue, forKey: PreferencesKeys.insertionMethod) }
    }

    var autoAddSpaces: Bool {
        didSet { defaults.set(autoAddSpaces, forKey: PreferencesKeys.autoAddSpaces) }
    }

    var launchAtLogin: Bool = PreferencesKeys.launchAtLoginDefault
    var launchAtLoginMessage: String?

    var windowFrame: CGRect {
        didSet { saveFrame(windowFrame) }
    }

    private let defaults = UserDefaults.standard
    private var isSyncingLaunchAtLogin = false

    /// 旧版键名（无域前缀），启动时一次性迁移到新键。
    private static let legacyKeys: [(old: String, new: String)] = [
        ("borderColor", PreferencesKeys.borderColor),
        ("panelOpacity", PreferencesKeys.panelOpacity),
        ("defaultWindowSize", PreferencesKeys.defaultWindowSize),
        ("insertionMethod", PreferencesKeys.insertionMethod),
        ("autoAddSpaces", PreferencesKeys.autoAddSpaces),
        ("launchAtLogin", PreferencesKeys.launchAtLogin),
        ("windowFrame", PreferencesKeys.windowFrame)
    ]

    static func clampOpacity(_ value: Double) -> Double {
        min(max(value, 0.35), 1.0)
    }

    private init() {
        Self.migrateLegacyKeys()

        let borderRaw = defaults.string(forKey: PreferencesKeys.borderColor)
            ?? PreferencesKeys.borderColorDefault.rawValue
        borderColor = BorderColorOption(rawValue: borderRaw) ?? PreferencesKeys.borderColorDefault

        if defaults.object(forKey: PreferencesKeys.panelOpacity) != nil {
            panelOpacity = Self.clampOpacity(defaults.double(forKey: PreferencesKeys.panelOpacity))
        } else {
            panelOpacity = PreferencesKeys.panelOpacityDefault
        }

        let sizeRaw = defaults.string(forKey: PreferencesKeys.defaultWindowSize)
            ?? PreferencesKeys.defaultWindowSizeDefault.rawValue
        defaultWindowSize = DefaultWindowSize(rawValue: sizeRaw) ?? PreferencesKeys.defaultWindowSizeDefault

        let insertRaw = defaults.string(forKey: PreferencesKeys.insertionMethod)
            ?? PreferencesKeys.insertionMethodDefault.rawValue
        insertionMethod = InsertionMethod(rawValue: insertRaw) ?? PreferencesKeys.insertionMethodDefault

        autoAddSpaces = defaults.object(forKey: PreferencesKeys.autoAddSpaces) as? Bool
            ?? PreferencesKeys.autoAddSpacesDefault

        if let data = defaults.data(forKey: PreferencesKeys.windowFrame),
           let rect = try? JSONDecoder().decode(CodableRect.self, from: data) {
            windowFrame = rect.cgRect
        } else {
            let size = (DefaultWindowSize(rawValue: sizeRaw) ?? PreferencesKeys.defaultWindowSizeDefault).size
            windowFrame = CGRect(x: 0, y: 0, width: size.width, height: size.height)
        }

        let preferred = defaults.bool(forKey: PreferencesKeys.launchAtLogin)
        launchAtLogin = preferred || LaunchAtLoginService.currentStatus().isEffectivelyOn
        LaunchAtLoginService.refreshIfNeeded(preferenceEnabled: preferred)
        syncLaunchAtLoginFromSystem()
    }

    /// 旧版键名 → 新键迁移：读到旧值写入新键后删除旧键。
    private static func migrateLegacyKeys() {
        let defaults = UserDefaults.standard
        for (old, new) in legacyKeys {
            guard defaults.object(forKey: new) == nil,
                  let value = defaults.object(forKey: old) else { continue }
            defaults.set(value, forKey: new)
            defaults.removeObject(forKey: old)
        }
    }

    func resetWindowSizeToDefault() {
        var frame = windowFrame
        frame.size = defaultWindowSize.size
        windowFrame = frame
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        guard !isSyncingLaunchAtLogin else { return }
        defaults.set(enabled, forKey: PreferencesKeys.launchAtLogin)

        switch LaunchAtLoginService.setEnabled(enabled) {
        case .success(let status):
            applyLaunchStatus(status, preferred: enabled)
        case .failure(let error):
            isSyncingLaunchAtLogin = true
            launchAtLogin = false
            isSyncingLaunchAtLogin = false
            launchAtLoginMessage = String(localized: "settings.general.launch.setFailed \(error.localizedDescription)")
            defaults.set(false, forKey: PreferencesKeys.launchAtLogin)
        }
    }

    func syncLaunchAtLoginFromSystem() {
        let status = LaunchAtLoginService.currentStatus()
        applyLaunchStatus(status, preferred: defaults.bool(forKey: PreferencesKeys.launchAtLogin))
    }

    private func applyLaunchStatus(_ status: LaunchAtLoginService.Status, preferred: Bool) {
        isSyncingLaunchAtLogin = true
        defer { isSyncingLaunchAtLogin = false }

        switch status {
        case .on:
            launchAtLogin = true
            launchAtLoginMessage = nil
            defaults.set(true, forKey: PreferencesKeys.launchAtLogin)
        case .needsApproval:
            launchAtLogin = preferred
            launchAtLoginMessage = String(localized: "settings.general.launch.needsApproval")
        case .off:
            launchAtLogin = false
            launchAtLoginMessage = preferred
                ? String(localized: "settings.general.launch.failed")
                : nil
            if !preferred {
                defaults.set(false, forKey: PreferencesKeys.launchAtLogin)
            }
        }
    }

    private func saveFrame(_ rect: CGRect) {
        let codable = CodableRect(cgRect: rect)
        if let data = try? JSONEncoder().encode(codable) {
            defaults.set(data, forKey: PreferencesKeys.windowFrame)
        }
    }
}

private struct CodableRect: Codable {
    var x: CGFloat
    var y: CGFloat
    var width: CGFloat
    var height: CGFloat

    init(cgRect: CGRect) {
        x = cgRect.origin.x
        y = cgRect.origin.y
        width = cgRect.size.width
        height = cgRect.size.height
    }

    var cgRect: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }
}

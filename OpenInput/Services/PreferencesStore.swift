import Foundation
import AppKit
import Observation

/// 偏好键与默认值成对集中声明；统一「域.名」点分命名，禁止在使用处散落字面量键。
enum PreferencesKeys {
    static let borderColor = "panel.borderColor"
    static let panelOpacity = "panel.opacity"
    static let defaultWindowSize = "panel.defaultSize"
    static let insertionMethod = "insertion.method"
    static let autoAddSpaces = "insertion.autoSpaces"
    static let launchAtLogin = "general.launchAtLogin"
    static let menuBarIconVisible = "menuBar.iconVisible"
    static let windowFrame = "panel.windowFrame"
    static let voiceAutoStartOnShow = "voice.autoStartOnShow"
    static let voiceLocale = "voice.locale"
    static let voiceAutoRefine = "voice.autoRefine"
    static let voiceReplacements = "voice.replacements"

    static let borderColorDefault = BorderColorOption.blue
    static let panelOpacityDefault = 1.0
    static let defaultWindowSizeDefault = DefaultWindowSize.regular
    static let insertionMethodDefault = InsertionMethod.paste
    static let autoAddSpacesDefault = false
    static let launchAtLoginDefault = false
    static let menuBarIconVisibleDefault = true
    static let voiceAutoStartOnShowDefault = false
    static let voiceLocaleDefault = ""
    static let voiceAutoRefineDefault = true
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

    /// 菜单栏图标是否显示。键不存在时保持默认显示，写入后才持久化。
    var menuBarIconVisible: Bool {
        didSet {
            defaults.set(menuBarIconVisible, forKey: PreferencesKeys.menuBarIconVisible)
            if !menuBarIconVisible {
                NotificationCenter.default.post(name: .openInputShowRecoveryWindow, object: nil)
            }
        }
    }

    var windowFrame: CGRect {
        didSet { saveFrame(windowFrame) }
    }

    /// 打开小窗时自动开始听写。
    var voiceAutoStartOnShow: Bool {
        didSet { defaults.set(voiceAutoStartOnShow, forKey: PreferencesKeys.voiceAutoStartOnShow) }
    }

    /// 空字符串表示跟随系统语言。
    var voiceLocaleIdentifier: String {
        didSet { defaults.set(voiceLocaleIdentifier, forKey: PreferencesKeys.voiceLocale) }
    }

    var voiceAutoRefine: Bool {
        didSet { defaults.set(voiceAutoRefine, forKey: PreferencesKeys.voiceAutoRefine) }
    }

    var voiceReplacements: [VoiceReplacement] {
        didSet { saveReplacements(voiceReplacements) }
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

        if defaults.object(forKey: PreferencesKeys.menuBarIconVisible) == nil {
            menuBarIconVisible = PreferencesKeys.menuBarIconVisibleDefault
        } else {
            menuBarIconVisible = defaults.bool(forKey: PreferencesKeys.menuBarIconVisible)
        }

        if let data = defaults.data(forKey: PreferencesKeys.windowFrame),
           let rect = try? JSONDecoder().decode(CodableRect.self, from: data) {
            windowFrame = rect.cgRect
        } else {
            let size = (DefaultWindowSize(rawValue: sizeRaw) ?? PreferencesKeys.defaultWindowSizeDefault).size
            windowFrame = CGRect(x: 0, y: 0, width: size.width, height: size.height)
        }

        if defaults.object(forKey: PreferencesKeys.voiceAutoStartOnShow) != nil {
            voiceAutoStartOnShow = defaults.bool(forKey: PreferencesKeys.voiceAutoStartOnShow)
        } else {
            voiceAutoStartOnShow = PreferencesKeys.voiceAutoStartOnShowDefault
        }
        voiceLocaleIdentifier = defaults.string(forKey: PreferencesKeys.voiceLocale)
            ?? PreferencesKeys.voiceLocaleDefault
        if defaults.object(forKey: PreferencesKeys.voiceAutoRefine) != nil {
            voiceAutoRefine = defaults.bool(forKey: PreferencesKeys.voiceAutoRefine)
        } else {
            voiceAutoRefine = PreferencesKeys.voiceAutoRefineDefault
        }
        if let data = defaults.data(forKey: PreferencesKeys.voiceReplacements),
           let items = try? JSONDecoder().decode([VoiceReplacement].self, from: data) {
            voiceReplacements = items
        } else {
            voiceReplacements = []
        }

        let preferred = defaults.bool(forKey: PreferencesKeys.launchAtLogin)
        LaunchAtLoginService.refreshIfNeeded(preferenceEnabled: preferred)
        // 开关只跟系统真实会拉起的状态走；待批准不能先显示成开。
        launchAtLogin = LaunchAtLoginService.currentStatus().isEffectivelyEnabled
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
        if LaunchAtLoginService.currentStatus() == .needsApproval, enabled {
            LaunchAtLoginService.openSystemSettings()
            syncLaunchAtLoginFromSystem()
            return
        }
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
            // 待批准不是已开启：开关必须关着，只展示引导文案。
            launchAtLogin = false
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

    private func saveReplacements(_ items: [VoiceReplacement]) {
        if let data = try? JSONEncoder().encode(items) {
            defaults.set(data, forKey: PreferencesKeys.voiceReplacements)
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

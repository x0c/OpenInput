import Foundation
import AppKit
import Combine
import ServiceManagement

@MainActor
final class PreferencesStore: ObservableObject {
    static let shared = PreferencesStore()

    @Published var borderColor: BorderColorOption {
        didSet { defaults.set(borderColor.rawValue, forKey: Keys.borderColor) }
    }

    /// Panel opacity, clamped to 0.35...1.0
    @Published var panelOpacity: Double {
        didSet {
            let clamped = Self.clampOpacity(panelOpacity)
            if clamped != panelOpacity {
                panelOpacity = clamped
                return
            }
            defaults.set(clamped, forKey: Keys.panelOpacity)
        }
    }

    @Published var defaultWindowSize: DefaultWindowSize {
        didSet { defaults.set(defaultWindowSize.rawValue, forKey: Keys.defaultWindowSize) }
    }

    @Published var insertionMethod: InsertionMethod {
        didSet { defaults.set(insertionMethod.rawValue, forKey: Keys.insertionMethod) }
    }

    @Published var autoAddSpaces: Bool {
        didSet { defaults.set(autoAddSpaces, forKey: Keys.autoAddSpaces) }
    }

    @Published var launchAtLogin: Bool = false
    @Published var launchAtLoginMessage: String?

    @Published var windowFrame: CGRect {
        didSet { saveFrame(windowFrame) }
    }

    private let defaults = UserDefaults.standard
    private var isSyncingLaunchAtLogin = false

    private enum Keys {
        static let borderColor = "borderColor"
        static let panelOpacity = "panelOpacity"
        static let defaultWindowSize = "defaultWindowSize"
        static let insertionMethod = "insertionMethod"
        static let autoAddSpaces = "autoAddSpaces"
        static let launchAtLogin = "launchAtLogin"
        static let windowFrame = "windowFrame"
    }

    static func clampOpacity(_ value: Double) -> Double {
        min(max(value, 0.35), 1.0)
    }

    private init() {
        let borderRaw = defaults.string(forKey: Keys.borderColor) ?? BorderColorOption.blue.rawValue
        borderColor = BorderColorOption(rawValue: borderRaw) ?? .blue

        if defaults.object(forKey: Keys.panelOpacity) != nil {
            panelOpacity = Self.clampOpacity(defaults.double(forKey: Keys.panelOpacity))
        } else {
            panelOpacity = 1.0
        }

        let sizeRaw = defaults.string(forKey: Keys.defaultWindowSize) ?? DefaultWindowSize.regular.rawValue
        defaultWindowSize = DefaultWindowSize(rawValue: sizeRaw) ?? .regular

        let insertRaw = defaults.string(forKey: Keys.insertionMethod) ?? InsertionMethod.paste.rawValue
        insertionMethod = InsertionMethod(rawValue: insertRaw) ?? .paste

        autoAddSpaces = defaults.object(forKey: Keys.autoAddSpaces) as? Bool ?? false

        if let data = defaults.data(forKey: Keys.windowFrame),
           let rect = try? JSONDecoder().decode(CodableRect.self, from: data) {
            windowFrame = rect.cgRect
        } else {
            let size = (DefaultWindowSize(rawValue: sizeRaw) ?? .regular).size
            windowFrame = CGRect(x: 0, y: 0, width: size.width, height: size.height)
        }

        let preferred = defaults.bool(forKey: Keys.launchAtLogin)
        launchAtLogin = preferred || LaunchAtLoginService.currentStatus().isEffectivelyOn
        LaunchAtLoginService.refreshIfNeeded(preferenceEnabled: preferred)
        syncLaunchAtLoginFromSystem()
    }

    func resetWindowSizeToDefault() {
        var frame = windowFrame
        frame.size = defaultWindowSize.size
        windowFrame = frame
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        guard !isSyncingLaunchAtLogin else { return }
        defaults.set(enabled, forKey: Keys.launchAtLogin)

        switch LaunchAtLoginService.setEnabled(enabled) {
        case .success(let status):
            applyLaunchStatus(status, preferred: enabled)
        case .failure(let error):
            isSyncingLaunchAtLogin = true
            launchAtLogin = false
            isSyncingLaunchAtLogin = false
            launchAtLoginMessage = "设置失败：\(error.localizedDescription)"
            defaults.set(false, forKey: Keys.launchAtLogin)
        }
    }

    func syncLaunchAtLoginFromSystem() {
        let status = LaunchAtLoginService.currentStatus()
        applyLaunchStatus(status, preferred: defaults.bool(forKey: Keys.launchAtLogin))
    }

    private func applyLaunchStatus(_ status: LaunchAtLoginService.Status, preferred: Bool) {
        isSyncingLaunchAtLogin = true
        defer { isSyncingLaunchAtLogin = false }

        switch status {
        case .on:
            launchAtLogin = true
            launchAtLoginMessage = nil
            defaults.set(true, forKey: Keys.launchAtLogin)
        case .needsApproval:
            launchAtLogin = preferred
            launchAtLoginMessage = "已请求登录项，请在「系统设置 → 通用 → 登录项」中允许 OpenInput。"
        case .off:
            launchAtLogin = false
            launchAtLoginMessage = preferred
                ? "未能开启登录启动，可重试或检查系统登录项权限。"
                : nil
            if !preferred {
                defaults.set(false, forKey: Keys.launchAtLogin)
            }
        }
    }

    private func saveFrame(_ rect: CGRect) {
        let codable = CodableRect(cgRect: rect)
        if let data = try? JSONEncoder().encode(codable) {
            defaults.set(data, forKey: Keys.windowFrame)
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

import Foundation
import AppKit

struct HistoryItem: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    var text: String
    var createdAt: Date

    init(id: UUID = UUID(), text: String, createdAt: Date = Date()) {
        self.id = id
        self.text = text
        self.createdAt = createdAt
    }

    var preview: String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count <= 80 {
            return trimmed.isEmpty ? String(localized: "history.item.empty") : trimmed
        }
        return String(trimmed.prefix(80)) + "…"
    }

    /// 相对时间跟随系统语言，不写死中文。
    var relativeTime: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.unitsStyle = .short
        return formatter.localizedString(for: createdAt, relativeTo: Date())
    }
}

enum BorderColorOption: String, CaseIterable, Identifiable, Codable {
    case purple
    case blue
    case cyan
    case orange
    case red
    case pink
    case gray
    case black

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .purple: return String(localized: "settings.color.purple")
        case .blue: return String(localized: "settings.color.blue")
        case .cyan: return String(localized: "settings.color.cyan")
        case .orange: return String(localized: "settings.color.orange")
        case .red: return String(localized: "settings.color.red")
        case .pink: return String(localized: "settings.color.pink")
        case .gray: return String(localized: "settings.color.gray")
        case .black: return String(localized: "settings.color.black")
        }
    }

    var nsColor: NSColor {
        switch self {
        case .purple: return NSColor(calibratedRed: 0.58, green: 0.35, blue: 0.95, alpha: 1)
        case .blue: return NSColor(calibratedRed: 0.20, green: 0.48, blue: 0.96, alpha: 1)
        case .cyan: return NSColor(calibratedRed: 0.20, green: 0.78, blue: 0.86, alpha: 1)
        case .orange: return NSColor(calibratedRed: 0.98, green: 0.55, blue: 0.20, alpha: 1)
        case .red: return NSColor(calibratedRed: 0.92, green: 0.28, blue: 0.28, alpha: 1)
        case .pink: return NSColor(calibratedRed: 0.92, green: 0.35, blue: 0.65, alpha: 1)
        case .gray: return NSColor(calibratedRed: 0.55, green: 0.55, blue: 0.58, alpha: 1)
        case .black: return NSColor(calibratedWhite: 0.15, alpha: 1)
        }
    }
}

enum DefaultWindowSize: String, CaseIterable, Identifiable, Codable {
    case compact
    case regular
    case large

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .compact: return String(localized: "settings.size.compact")
        case .regular: return String(localized: "settings.size.regular")
        case .large: return String(localized: "settings.size.large")
        }
    }

    var size: CGSize {
        switch self {
        case .compact: return CGSize(width: 360, height: 140)
        case .regular: return CGSize(width: 400, height: 180)
        case .large: return CGSize(width: 520, height: 240)
        }
    }
}

enum InsertionMethod: String, CaseIterable, Identifiable, Codable {
    case paste
    case typing

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .paste: return String(localized: "settings.insertion.paste")
        case .typing: return String(localized: "settings.insertion.typing")
        }
    }
}

struct CapturedFocus: Equatable {
    let processIdentifier: pid_t
    let bundleIdentifier: String?
    let appName: String?
    /// 光标或聚焦输入框在 AppKit 屏幕坐标系中的矩形。
    let anchorRect: CGRect?
}

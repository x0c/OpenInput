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
            return trimmed.isEmpty ? "(空)" : trimmed
        }
        return String(trimmed.prefix(80)) + "…"
    }

    var relativeTime: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
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
        case .purple: return "紫色"
        case .blue: return "蓝色"
        case .cyan: return "青色"
        case .orange: return "橙色"
        case .red: return "红色"
        case .pink: return "粉色"
        case .gray: return "灰色"
        case .black: return "黑色"
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
        case .compact: return "紧凑 360 × 140"
        case .regular: return "标准 400 × 180"
        case .large: return "较大 520 × 240"
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
        case .paste: return "粘贴"
        case .typing: return "模拟键入（二期）"
        }
    }
}

struct CapturedFocus: Equatable {
    let processIdentifier: pid_t
    let bundleIdentifier: String?
    let appName: String?
    /// Caret or focused-field rect in AppKit screen coordinates.
    let anchorRect: CGRect?
}

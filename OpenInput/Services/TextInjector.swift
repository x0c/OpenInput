import AppKit
import Carbon.HIToolbox

/// 通过「激活目标应用 + ⌘V」把文本注入回原输入框。
@MainActor
final class TextInjector {
    static let shared = TextInjector()

    private init() {}

    enum InjectError: LocalizedError {
        case noTarget
        case accessibilityDenied
        case emptyText
        case pasteEventFailed

        var errorDescription: String? {
            switch self {
            case .noTarget: return String(localized: "error.inject.noTarget")
            case .accessibilityDenied: return String(localized: "error.inject.permission")
            case .emptyText: return String(localized: "error.inject.empty")
            case .pasteEventFailed: return String(localized: "error.inject.pasteFailed")
            }
        }
    }

    func inject(_ text: String, into target: NSRunningApplication?) async throws {
        guard !text.isEmpty else { throw InjectError.emptyText }
        guard let target else { throw InjectError.noTarget }
        guard AccessibilityPermission.isTrusted else { throw InjectError.accessibilityDenied }

        let pasteboard = NSPasteboard.general
        let previousString = pasteboard.string(forType: .string)

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        // 无论成功、取消还是中途抛错，都先恢复用户原先的剪贴板；失败兜底再由调用方写入。
        defer {
            pasteboard.clearContents()
            if let previousString {
                pasteboard.setString(previousString, forType: .string)
            }
        }

        // 等待目标应用激活、输入框就绪后再发 ⌘V（macOS 14 起系统自行处理前台切换）。
        _ = target.activate()
        try await Task.sleep(for: .milliseconds(120))
        try postCommandV()
        try await Task.sleep(for: .milliseconds(200))
    }

    private func postCommandV() throws {
        let source = CGEventSource(stateID: .hidSystemState)
        let keyV = CGKeyCode(kVK_ANSI_V)

        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyV, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyV, keyDown: false) else {
            throw InjectError.pasteEventFailed
        }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }
}

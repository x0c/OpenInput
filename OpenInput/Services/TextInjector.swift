import AppKit
import Carbon.HIToolbox

@MainActor
final class TextInjector {
    static let shared = TextInjector()

    private init() {}

    enum InjectError: LocalizedError {
        case noTarget
        case accessibilityDenied
        case emptyText

        var errorDescription: String? {
            switch self {
            case .noTarget: return "未找到原先的输入应用"
            case .accessibilityDenied: return "需要辅助功能权限才能自动粘贴"
            case .emptyText: return "没有可插入的文本"
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

        _ = target.activate(options: [.activateIgnoringOtherApps])

        try await Task.sleep(nanoseconds: 120_000_000)
        postCommandV()
        try await Task.sleep(nanoseconds: 200_000_000)

        pasteboard.clearContents()
        if let previousString {
            pasteboard.setString(previousString, forType: .string)
        }
    }

    private func postCommandV() {
        let source = CGEventSource(stateID: .hidSystemState)
        let keyV = CGKeyCode(kVK_ANSI_V)

        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyV, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyV, keyDown: false) else {
            return
        }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }
}

import AppKit
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let togglePanel = Self("togglePanel", default: .init(.i, modifiers: [.option, .command]))
}

/// Hotkey callbacks arrive from Carbon on the main run-loop thread, but not under
/// Swift's MainActor executor. Avoid `Task { @MainActor }` here — it crashes on
/// recent Swift/macOS (SIGSEGV in swift_task_isMainExecutor).
final class HotkeyService: @unchecked Sendable {
    static let shared = HotkeyService()

    private var onToggle: (() -> Void)?
    private let lock = NSLock()

    private init() {}

    func start(onToggle: @escaping () -> Void) {
        lock.lock()
        self.onToggle = onToggle
        lock.unlock()

        KeyboardShortcuts.onKeyUp(for: .togglePanel) {
            DispatchQueue.main.async {
                HotkeyService.shared.fireToggle()
            }
        }
    }

    private func fireToggle() {
        lock.lock()
        let action = onToggle
        lock.unlock()
        action?()
    }
}

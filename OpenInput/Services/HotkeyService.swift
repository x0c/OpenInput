import Foundation
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let togglePanel = Self("togglePanel", default: .init(.i, modifiers: [.option, .command]))
}

/// 热键回调由 Carbon 在主 run-loop 线程派发，但不一定处于 Swift 的 MainActor
/// executor 之下，所以这里不直接用 `Task { @MainActor }`——在较新的
/// Swift/macOS 上会以 SIGSEGV 崩溃（swift_task_isMainExecutor），统一走
/// DispatchQueue.main 再进入业务层。
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

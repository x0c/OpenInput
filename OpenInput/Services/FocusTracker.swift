import AppKit
import ApplicationServices

/// 记录焦点捕获：目标应用 + 输入锚点。
@MainActor
final class FocusTracker {
    static let shared = FocusTracker()

    private(set) var captured: CapturedFocus?

    private init() {}

    /// 捕获当前焦点应用与输入锚点。优先取系统级 AX 聚焦元素
    ///（Chrome 地址栏时序最稳），再回退到字段矩形 / 鼠标位置。
    func captureFrontmost() {
        guard let app = resolveTargetApplication() else { return }
        let anchor = resolveAnchorRect(pid: app.processIdentifier)
        captured = CapturedFocus(
            processIdentifier: app.processIdentifier,
            bundleIdentifier: app.bundleIdentifier,
            appName: app.localizedName,
            anchorRect: anchor
        )
    }

    func resolveTargetApplication() -> NSRunningApplication? {
        if let axApp = focusedApplicationFromAccessibility(),
           axApp.bundleIdentifier != Bundle.main.bundleIdentifier {
            return axApp
        }
        if let front = NSWorkspace.shared.frontmostApplication,
           front.bundleIdentifier != Bundle.main.bundleIdentifier {
            return front
        }
        if let previous = resolveApplication(),
           previous.bundleIdentifier != Bundle.main.bundleIdentifier {
            return previous
        }
        return nil
    }

    func resolveApplication() -> NSRunningApplication? {
        guard let captured else { return nil }
        if let bundleId = captured.bundleIdentifier,
           let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first {
            return app
        }
        return NSRunningApplication(processIdentifier: captured.processIdentifier)
    }

    /// 当前系统焦点输入框里的文字，读不到则返回 nil。
    func focusedFieldValue() -> String? {
        guard AccessibilityPermission.isTrusted else { return nil }
        let systemWide = AXUIElementCreateSystemWide()
        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focusedRef
        ) == .success, let focusedRef else { return nil }
        return AXAttributeAccess.string(focusedRef as! AXUIElement, kAXValueAttribute as String)
    }

    func clear() {
        captured = nil
    }

    private func focusedApplicationFromAccessibility() -> NSRunningApplication? {
        guard AccessibilityPermission.isTrusted else { return nil }
        let systemWide = AXUIElementCreateSystemWide()
        var appRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedApplicationAttribute as CFString,
            &appRef
        ) == .success, let appRef else { return nil }
        var pid: pid_t = 0
        guard AXUIElementGetPid(appRef as! AXUIElement, &pid) == .success else { return nil }
        return NSRunningApplication(processIdentifier: pid)
    }

    // MARK: - 锚点坐标（AX 左上原点 → AppKit 左下原点）

    private func resolveAnchorRect(pid: pid_t) -> CGRect? {
        guard AccessibilityPermission.isTrusted else {
            return mouseFallbackCocoa()
        }

        // 1) 系统级聚焦元素（Chrome 地址栏时序最好）。
        let systemWide = AXUIElementCreateSystemWide()
        var focusedRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focusedRef
        ) == .success, let focusedRef, let rect = anchorFromElement(focusedRef as! AXUIElement) {
            return rect
        }

        // 2) 目标应用自己的聚焦元素。
        let appElement = AXUIElementCreateApplication(pid)
        focusedRef = nil
        if AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedRef
        ) == .success, let focusedRef, let rect = anchorFromElement(focusedRef as! AXUIElement) {
            return rect
        }

        return mouseFallbackCocoa()
    }

    /// 判定树：光标边界 → 元素矩形（向上追溯父级）→ nil。
    private func anchorFromElement(_ start: AXUIElement) -> CGRect? {
        var element = start
        for _ in 0..<8 {
            if let caret = caretBoundsCocoa(for: element) {
                return pinchWide(caret)
            }
            if let frame = elementBoundsCocoa(for: element), frame.width > 2, frame.height > 2 {
                let role = AXAttributeAccess.string(element, kAXRoleAttribute as String) ?? ""
                let textRoles = [
                    kAXTextFieldRole as String,
                    kAXTextAreaRole as String,
                    kAXComboBoxRole as String,
                    "AXSearchField"
                ]
                if textRoles.contains(role) || frame.height < 64 {
                    return pinchWide(frame)
                }
            }
            guard let parent = AXAttributeAccess.parent(element) else { break }
            element = parent
        }
        return nil
    }

    /// 超宽输入框（如 Chrome 地址栏）把锚点收敛到鼠标附近的小矩形。
    private func pinchWide(_ rect: CGRect) -> CGRect {
        let mouse = NSEvent.mouseLocation
        guard rect.width > 280 else { return rect }
        let x = min(max(mouse.x - 16, rect.minX), max(rect.maxX - 48, rect.minX))
        return CGRect(x: x, y: rect.minY, width: 48, height: max(rect.height, 18))
    }

    private func caretBoundsCocoa(for element: AXUIElement) -> CGRect? {
        var rangeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            &rangeRef
        ) == .success, let rangeRef else { return nil }

        var boundsRef: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXBoundsForRangeParameterizedAttribute as CFString,
            rangeRef,
            &boundsRef
        ) == .success,
              let boundsRef,
              CFGetTypeID(boundsRef) == AXValueGetTypeID() else { return nil }

        var axRect = CGRect.zero
        guard AXValueGetValue(boundsRef as! AXValue, .cgRect, &axRect) else { return nil }
        if axRect.width < 1 { axRect.size.width = 2 }
        if axRect.height < 1 { axRect.size.height = 16 }
        return axToCocoa(axRect)
    }

    private func elementBoundsCocoa(for element: AXUIElement) -> CGRect? {
        guard let origin = AXAttributeAccess.cgPoint(element, kAXPositionAttribute as String),
              let size = AXAttributeAccess.cgSize(element, kAXSizeAttribute as String),
              size.width > 0, size.height > 0 else { return nil }
        return axToCocoa(CGRect(origin: origin, size: size))
    }

    private func mouseFallbackCocoa() -> CGRect {
        let mouse = NSEvent.mouseLocation
        return CGRect(x: mouse.x, y: mouse.y - 8, width: 2, height: 16)
    }

    /// 辅助功能坐标是左上原点，AppKit 是左下原点。
    private func axToCocoa(_ axRect: CGRect) -> CGRect {
        let maxY = NSScreen.screens.map(\.frame.maxY).max() ?? 0
        return CGRect(
            x: axRect.origin.x,
            y: maxY - axRect.origin.y - axRect.height,
            width: axRect.width,
            height: axRect.height
        )
    }
}

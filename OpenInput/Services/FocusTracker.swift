import AppKit
import ApplicationServices

@MainActor
final class FocusTracker {
    static let shared = FocusTracker()

    private(set) var captured: CapturedFocus?

    private init() {}

    /// Capture focused app + input anchor. Uses system-wide AX focused element first
    /// (IndieSeek / Paste Switch approach), then falls back to field frame / mouse.
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

    // MARK: - Anchor (AX top-left → AppKit bottom-left)

    private func resolveAnchorRect(pid: pid_t) -> CGRect? {
        guard AccessibilityPermission.isTrusted else {
            return mouseFallbackCocoa()
        }

        // 1) System-wide focused element (best for Chrome omnibox timing).
        let systemWide = AXUIElementCreateSystemWide()
        var focusedRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focusedRef
        ) == .success, let focusedRef {
            if let rect = anchorFromElement(focusedRef as! AXUIElement) {
                return rect
            }
        }

        // 2) Focused element of the target app.
        let appElement = AXUIElementCreateApplication(pid)
        focusedRef = nil
        if AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedRef
        ) == .success, let focusedRef {
            if let rect = anchorFromElement(focusedRef as! AXUIElement) {
                return rect
            }
        }

        return mouseFallbackCocoa()
    }

    /// Decision tree: caret bounds → element frame (walk parents) → nil.
    private func anchorFromElement(_ start: AXUIElement) -> CGRect? {
        var element = start
        for _ in 0..<8 {
            if let caret = caretBoundsCocoa(for: element) {
                return pinchWide(caret)
            }
            if let frame = elementBoundsCocoa(for: element), frame.width > 2, frame.height > 2 {
                let role = stringValue(element, kAXRoleAttribute as String) ?? ""
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
            guard let parent = parentOf(element) else { break }
            element = parent
        }
        return nil
    }

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
        var posRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posRef) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let posRef, let sizeRef,
              CFGetTypeID(posRef) == AXValueGetTypeID(),
              CFGetTypeID(sizeRef) == AXValueGetTypeID() else { return nil }

        var origin = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(posRef as! AXValue, .cgPoint, &origin),
              AXValueGetValue(sizeRef as! AXValue, .cgSize, &size),
              size.width > 0, size.height > 0 else { return nil }
        return axToCocoa(CGRect(origin: origin, size: size))
    }

    private func parentOf(_ element: AXUIElement) -> AXUIElement? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXParentAttribute as CFString, &ref) == .success,
              let ref else { return nil }
        return (ref as! AXUIElement)
    }

    private func stringValue(_ element: AXUIElement, _ name: String) -> String? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &ref) == .success,
              let ref else { return nil }
        return ref as? String
    }

    private func mouseFallbackCocoa() -> CGRect {
        let mouse = NSEvent.mouseLocation
        return CGRect(x: mouse.x, y: mouse.y - 8, width: 2, height: 16)
    }

    /// Accessibility uses top-left global coords; AppKit uses bottom-left.
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

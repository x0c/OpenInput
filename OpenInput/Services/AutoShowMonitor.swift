import AppKit
import ApplicationServices

/// Watches frontmost app / focused field and auto-shows OpenInput for remembered apps.
@MainActor
final class AutoShowMonitor {
    static let shared = AutoShowMonitor()

    private var appObserver: NSObjectProtocol?
    private var axObserver: AXObserver?
    private var observedPID: pid_t?
    private var debounceWork: DispatchWorkItem?
    private var pollTimer: Timer?
    private var clickMonitor: Any?
    private var suppressUntil: Date = .distantPast
    /// Avoid re-opening for the same focus burst; cleared when focus leaves a text field.
    private var lastTriggeredFocusSignature: String?
    private var wasInTextField = false
    private var pendingUserClick = false
    private var lastAutoShowAt: Date = .distantPast

    private init() {}

    func start() {
        stop()

        appObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            let pid = app?.processIdentifier
            let bundleId = app?.bundleIdentifier
            Task { @MainActor in
                guard let self, let pid else { return }
                if bundleId == Bundle.main.bundleIdentifier { return }
                if let app {
                    self.attach(to: app)
                } else if let running = NSRunningApplication(processIdentifier: pid) {
                    self.attach(to: running)
                }
                self.scheduleEvaluate(delay: 0.2)
            }
        }

        // Chrome often doesn't emit reliable AX blur/focus; clicks help detect re-focus.
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in
                self?.pendingUserClick = true
                self?.scheduleEvaluate(delay: 0.2)
            }
        }

        // Chrome and many apps are unreliable with AX focus notifications alone.
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.45, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.evaluate()
            }
        }
        if let pollTimer {
            RunLoop.main.add(pollTimer, forMode: .common)
        }

        attachToFrontmost()
        scheduleEvaluate(delay: 0.3)
    }

    func stop() {
        if let appObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(appObserver)
            self.appObserver = nil
        }
        if let clickMonitor {
            NSEvent.removeMonitor(clickMonitor)
            self.clickMonitor = nil
        }
        detachAXObserver()
        debounceWork?.cancel()
        debounceWork = nil
        pollTimer?.invalidate()
        pollTimer = nil
    }

    func suppressBriefly(seconds: TimeInterval = 2.0) {
        suppressUntil = Date().addingTimeInterval(seconds)
        lastTriggeredFocusSignature = nil
    }

    private func attachToFrontmost() {
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.bundleIdentifier != Bundle.main.bundleIdentifier else {
            detachAXObserver()
            return
        }
        attach(to: app)
    }

    private func attach(to app: NSRunningApplication) {
        let pid = app.processIdentifier
        if observedPID == pid, axObserver != nil { return }
        detachAXObserver()
        observedPID = pid

        guard AccessibilityPermission.isTrusted else { return }

        var observer: AXObserver?
        let callback: AXObserverCallback = { _, _, _, refcon in
            guard let refcon else { return }
            let monitor = Unmanaged<AutoShowMonitor>.fromOpaque(refcon).takeUnretainedValue()
            DispatchQueue.main.async {
                monitor.scheduleEvaluate(delay: 0.15)
            }
        }

        guard AXObserverCreate(pid, callback, &observer) == .success,
              let observer else {
            return
        }

        axObserver = observer
        let appElement = AXUIElementCreateApplication(pid)
        let refcon = Unmanaged.passUnretained(self).toOpaque()

        let notifications = [
            kAXFocusedUIElementChangedNotification as String,
            kAXFocusedWindowChangedNotification as String,
            kAXSelectedTextChangedNotification as String
        ]
        for name in notifications {
            AXObserverAddNotification(observer, appElement, name as CFString, refcon)
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
    }

    private func detachAXObserver() {
        if let axObserver, let pid = observedPID {
            let appElement = AXUIElementCreateApplication(pid)
            for name in [
                kAXFocusedUIElementChangedNotification as String,
                kAXFocusedWindowChangedNotification as String,
                kAXSelectedTextChangedNotification as String
            ] {
                AXObserverRemoveNotification(axObserver, appElement, name as CFString)
            }
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(axObserver), .defaultMode)
        }
        axObserver = nil
        observedPID = nil
    }

    private func scheduleEvaluate(delay: TimeInterval) {
        debounceWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                self?.evaluate()
            }
        }
        debounceWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func evaluate() {
        guard AppMemoryStore.shared.autoShowMasterEnabled else { return }
        guard AccessibilityPermission.isTrusted else { return }
        guard !InputPanelController.shared.isVisible else { return }
        guard Date() >= suppressUntil else { return }

        guard let app = FocusTracker.shared.resolveTargetApplication()
                ?? NSWorkspace.shared.frontmostApplication,
              let bundleId = app.bundleIdentifier,
              bundleId != Bundle.main.bundleIdentifier else {
            wasInTextField = false
            return
        }

        // Keep AX observer attached to the real front app.
        if observedPID != app.processIdentifier {
            attach(to: app)
        }

        guard AppMemoryStore.shared.shouldAutoShow(bundleIdentifier: bundleId) else {
            wasInTextField = false
            lastTriggeredFocusSignature = nil
            return
        }

        let focusInfo = focusedTextFieldInfo(pid: app.processIdentifier)
        let inTextField = focusInfo != nil
        let clicked = pendingUserClick
        pendingUserClick = false

        let shouldTrigger: Bool
        if inTextField, let signature = focusInfo {
            if !wasInTextField {
                // Entered a text field from non-field.
                shouldTrigger = true
            } else if lastTriggeredFocusSignature != signature {
                // Different field.
                shouldTrigger = true
            } else if clicked, Date().timeIntervalSince(lastAutoShowAt) > 1.0 {
                // Same field re-clicked (Chrome often skips AX blur).
                shouldTrigger = true
            } else {
                shouldTrigger = false
            }
            if shouldTrigger {
                lastTriggeredFocusSignature = signature
            }
        } else {
            shouldTrigger = false
            lastTriggeredFocusSignature = nil
        }

        wasInTextField = inTextField
        guard shouldTrigger else { return }

        lastAutoShowAt = Date()
        InputPanelController.shared.show(reason: .autoShow)
    }

    /// Returns a stable signature for the focused text-like element, or nil if not text input.
    private func focusedTextFieldInfo(pid: pid_t) -> String? {
        let appElement = AXUIElementCreateApplication(pid)
        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedRef
        ) == .success, let focusedRef else {
            return nil
        }

        var element = focusedRef as! AXUIElement
        // Walk up a few ancestors — Chrome omnibox focus may land on an inner node.
        for _ in 0..<6 {
            if isTextLike(element) {
                let role = stringAttribute(element, kAXRoleAttribute as String) ?? "?"
                let desc = stringAttribute(element, kAXDescriptionAttribute as String) ?? ""
                let title = stringAttribute(element, kAXTitleAttribute as String) ?? ""
                var pos = ""
                if let bounds = elementOrigin(element) {
                    pos = "\(Int(bounds.x)),\(Int(bounds.y))"
                }
                return "\(pid)|\(role)|\(desc)|\(title)|\(pos)"
            }
            guard let parent = parentElement(element) else { break }
            element = parent
        }
        return nil
    }

    private func isTextLike(_ element: AXUIElement) -> Bool {
        let role = stringAttribute(element, kAXRoleAttribute as String) ?? ""
        let subrole = stringAttribute(element, kAXSubroleAttribute as String) ?? ""
        let desc = (stringAttribute(element, kAXDescriptionAttribute as String) ?? "").lowercased()
        let title = (stringAttribute(element, kAXTitleAttribute as String) ?? "").lowercased()

        let textRoles: Set<String> = [
            kAXTextFieldRole as String,
            kAXTextAreaRole as String,
            kAXComboBoxRole as String,
            "AXSearchField",
            "AXURLField",
            "AXTextField"
        ]
        if textRoles.contains(role) { return true }
        if subrole == "AXSearchField" || subrole == "AXURL" { return true }

        // Chrome omnibox / address bar heuristics.
        let omniboxHints = ["address", "omnibox", "url", "搜索", "地址", "location"]
        if omniboxHints.contains(where: { desc.contains($0) || title.contains($0) }) {
            return true
        }

        if boolAttribute(element, "AXEditable") == true { return true }

        // Has a selectable text range → almost certainly an editor/field.
        var rangeRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            &rangeRef
        ) == .success, rangeRef != nil {
            return true
        }

        // String AXValue + focused often means a field (Chrome omnibox).
        if stringAttribute(element, kAXValueAttribute as String) != nil,
           textRoles.contains(role) || role == "AXGroup" || role.isEmpty {
            // Only treat AXGroup as text-like when it also has insertion-related attrs.
            if role != "AXGroup" { return true }
            if numberAttribute(element, kAXNumberOfCharactersAttribute as String) != nil {
                return true
            }
        }

        if numberAttribute(element, kAXNumberOfCharactersAttribute as String) != nil {
            return true
        }

        return false
    }

    private func parentElement(_ element: AXUIElement) -> AXUIElement? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXParentAttribute as CFString, &ref) == .success,
              let ref else { return nil }
        return (ref as! AXUIElement)
    }

    private func elementOrigin(_ element: AXUIElement) -> CGPoint? {
        var posRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posRef) == .success,
              let posRef, CFGetTypeID(posRef) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero
        guard AXValueGetValue(posRef as! AXValue, .cgPoint, &point) else { return nil }
        return point
    }

    private func stringAttribute(_ element: AXUIElement, _ name: String) -> String? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &ref) == .success,
              let ref else { return nil }
        return ref as? String
    }

    private func boolAttribute(_ element: AXUIElement, _ name: String) -> Bool? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &ref) == .success,
              let ref else { return nil }
        return (ref as? Bool) ?? (ref as? NSNumber)?.boolValue
    }

    private func numberAttribute(_ element: AXUIElement, _ name: String) -> NSNumber? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &ref) == .success,
              let ref else { return nil }
        return ref as? NSNumber
    }
}

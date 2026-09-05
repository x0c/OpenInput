import AppKit
import SwiftUI

@MainActor
final class InputPanelController: NSObject, NSWindowDelegate {
    static let shared = InputPanelController()

    private static let shadowPadding: CGFloat = 24

    private var panel: KeyablePanel?
    private var hostingView: NSHostingView<InputPanelRootView>?
    private let viewModel = InputPanelViewModel()
    private var borderView: BorderOverlayView?
    private weak var shadowHost: NSView?

    private var appSwitchObserver: NSObjectProtocol?
    private var clickOutsideMonitor: Any?
    private var suppressAutoHideUntil: Date = .distantPast
    private var isSubmitting = false
    private var lastInjectTarget: NSRunningApplication?

    private override init() {
        super.init()
    }

    var isVisible: Bool {
        panel?.isVisible == true
    }

    enum ShowReason {
        case manual
        case autoShow
    }

    func toggle() {
        if let panel, panel.isVisible {
            dismissActively()
        } else {
            show(reason: .manual)
        }
    }

    func show(reason: ShowReason = .manual) {
        if isVisible { return }

        FocusTracker.shared.captureFrontmost()
        ensurePanel()
        guard let panel else { return }

        applySize(panel)
        placeNearInput(panel)
        updateBorder()

        suppressAutoHideUntil = Date().addingTimeInterval(reason == .autoShow ? 0.6 : 0.35)

        panel.level = .floating
        panel.orderFrontRegardless()
        panel.makeKey()
        viewModel.focusEditor(force: true)
        installAutoHideMonitors()
        updateFocusVisual()
        startDictationIfNeeded()

        if reason == .autoShow {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                guard let self, let panel = self.panel, self.isVisible else { return }
                panel.orderFrontRegardless()
                panel.makeKey()
                self.viewModel.focusEditor(force: true)
                self.updateFocusVisual()
            }
        }
    }

    func hide(clearText: Bool) {
        SpeechDictationService.shared.stop()
        removeAutoHideMonitors()
        if clearText {
            viewModel.resetDraft()
        }
        panel?.orderOut(nil)
        if NSApp.activationPolicy() != .accessory {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    /// esc / ✕ / 热键关闭——同时关闭该应用的自动打开。
    func dismissActively() {
        let focus = FocusTracker.shared.captured
        AppMemoryStore.shared.rememberDismissed(
            bundleIdentifier: focus?.bundleIdentifier,
            appName: focus?.appName
        )
        AutoShowMonitor.shared.suppressBriefly()
        hide(clearText: false)
    }

    /// 切换应用 / 点击小窗外——关闭但不改动应用记忆。
    func dismissPassively() {
        guard isVisible else { return }
        AutoShowMonitor.shared.suppressBriefly(seconds: 1.2)
        hide(clearText: false)
    }

    func submitAndHide() {
        guard !isSubmitting else { return }
        isSubmitting = true
        Task { @MainActor in
            defer { isSubmitting = false }
            await SpeechDictationService.shared.stopAndCommit()
            viewModel.applyDictation(
                committed: SpeechDictationService.shared.committedText,
                volatile: ""
            )

            let raw = viewModel.currentText
            guard !raw.isEmpty else {
                dismissActively()
                return
            }

            let refined = await TextRefinementService.shared.refine(raw)
            viewModel.setText(refined.refined)

            let target = FocusTracker.shared.resolveApplication()
                ?? FocusTracker.shared.resolveTargetApplication()
            let focus = FocusTracker.shared.captured

            suppressAutoHideUntil = Date().addingTimeInterval(3.0)
            AutoShowMonitor.shared.suppressBriefly(seconds: 2.5)
            hide(clearText: true)

            do {
                try await TextInjector.shared.inject(refined.refined, into: target)
                // 仅成功粘贴后才记「用过」——失败路径不得打开该应用的自动弹出。
                AppMemoryStore.shared.rememberUsed(
                    bundleIdentifier: focus?.bundleIdentifier ?? target?.bundleIdentifier,
                    appName: focus?.appName ?? target?.localizedName
                )
                HistoryStore.shared.add(refined.refined)
                if refined.didChange {
                    lastInjectTarget = target
                    TextRefinementService.shared.rememberCleanupRevert(
                        original: refined.original,
                        pasted: refined.refined
                    )
                } else {
                    lastInjectTarget = nil
                    TextRefinementService.shared.clearCleanupRevert()
                }
            } catch {
                presentInjectFailure(error, text: refined.refined)
            }
        }
    }

    // MARK: - 用户离开时自动隐藏

    private func installAutoHideMonitors() {
        removeAutoHideMonitors()

        appSwitchObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            let bundleId = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?
                .bundleIdentifier
            Task { @MainActor in
                self?.handleAppActivated(bundleId: bundleId)
            }
        }

        clickOutsideMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] event in
            let screenPoint = NSEvent.mouseLocation
            Task { @MainActor in
                self?.handleOutsideClick(at: screenPoint)
            }
            _ = event
        }
    }

    private func removeAutoHideMonitors() {
        if let appSwitchObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(appSwitchObserver)
            self.appSwitchObserver = nil
        }
        if let clickOutsideMonitor {
            NSEvent.removeMonitor(clickOutsideMonitor)
            self.clickOutsideMonitor = nil
        }
    }

    private func handleAppActivated(bundleId: String?) {
        guard isVisible else { return }
        guard Date() >= suppressAutoHideUntil else { return }
        guard SpeechDictationService.shared.status != .preparing else { return }
        guard let bundleId, bundleId != Bundle.main.bundleIdentifier else { return }
        dismissPassively()
    }

    private func handleOutsideClick(at screenPoint: NSPoint) {
        guard isVisible, let panel else { return }
        guard Date() >= suppressAutoHideUntil else { return }
        guard SpeechDictationService.shared.status != .preparing else { return }
        if !panel.frame.contains(screenPoint) {
            dismissPassively()
        }
    }

    func updateBorder() {
        let color = PreferencesStore.shared.borderColor.nsColor
        borderView?.borderColor = color
        borderView?.needsDisplay = true
        panel?.alphaValue = PreferencesStore.shared.panelOpacity

        guard let host = shadowHost else { return }
        host.layer?.shadowColor = color.cgColor
        host.layer?.shadowOpacity = Float(0.55 * PreferencesStore.shared.panelOpacity)
        host.layer?.shadowRadius = 14
        host.layer?.shadowOffset = CGSize(width: 0, height: -2)
        host.layer?.masksToBounds = false
    }

    /// 编辑器获得键盘焦点时的自有焦点态：边框外圈光晕。
    private func updateFocusVisual() {
        borderView?.isFocused = panel?.isKeyWindow == true
        borderView?.needsDisplay = true
    }

    private func ensurePanel() {
        // .nonactivatingPanel 必须在 init 时设定；旧面板缺了它就必须重建。
        if let panel, panel.styleMask.contains(.nonactivatingPanel) {
            return
        }
        panel?.orderOut(nil)
        panel = nil
        hostingView = nil
        borderView = nil
        shadowHost = nil

        let pad = Self.shadowPadding
        let cardSize = rememberedCardSize()
        let rect = NSRect(
            origin: .zero,
            size: CGSize(width: cardSize.width + pad * 2, height: cardSize.height + pad * 2)
        )

        let panel = KeyablePanel(
            contentRect: rect,
            styleMask: [.borderless, .nonactivatingPanel, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.isReleasedWhenClosed = false
        panel.delegate = self
        panel.minSize = NSSize(width: 280 + pad * 2, height: 120 + pad * 2)
        panel.worksWhenModal = true
        panel.animationBehavior = .utilityWindow
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false

        let rootView = NSView(frame: rect)
        rootView.wantsLayer = true
        rootView.layer?.backgroundColor = NSColor.clear.cgColor

        let host = NSView(frame: .zero)
        host.translatesAutoresizingMaskIntoConstraints = false
        host.wantsLayer = true
        host.layer?.masksToBounds = false

        let card = NSView(frame: .zero)
        card.translatesAutoresizingMaskIntoConstraints = false
        card.wantsLayer = true
        card.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        card.layer?.cornerRadius = 10
        card.layer?.masksToBounds = true

        let hosting = NSHostingView(rootView: InputPanelRootView(viewModel: viewModel))
        hosting.translatesAutoresizingMaskIntoConstraints = false

        let border = BorderOverlayView(frame: .zero)
        border.translatesAutoresizingMaskIntoConstraints = false
        border.borderColor = PreferencesStore.shared.borderColor.nsColor

        rootView.addSubview(host)
        host.addSubview(card)
        card.addSubview(hosting)
        card.addSubview(border)

        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: rootView.leadingAnchor, constant: pad),
            host.trailingAnchor.constraint(equalTo: rootView.trailingAnchor, constant: -pad),
            host.topAnchor.constraint(equalTo: rootView.topAnchor, constant: pad),
            host.bottomAnchor.constraint(equalTo: rootView.bottomAnchor, constant: -pad),
            card.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            card.trailingAnchor.constraint(equalTo: host.trailingAnchor),
            card.topAnchor.constraint(equalTo: host.topAnchor),
            card.bottomAnchor.constraint(equalTo: host.bottomAnchor),
            hosting.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: card.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: card.bottomAnchor),
            border.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            border.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            border.topAnchor.constraint(equalTo: card.topAnchor),
            border.bottomAnchor.constraint(equalTo: card.bottomAnchor)
        ])

        panel.contentView = rootView
        self.panel = panel
        self.hostingView = hosting
        self.borderView = border
        self.shadowHost = host

        viewModel.onSubmit = { [weak self] in self?.submitAndHide() }
        viewModel.onCancel = { [weak self] in self?.dismissActively() }
        viewModel.onBorderNeedsUpdate = { [weak self] in self?.updateBorder() }
        viewModel.onToggleDictation = { [weak self] in self?.toggleDictation() }

        updateBorder()
        updateShadowPath()
    }

    private func rememberedCardSize() -> CGSize {
        var size = PreferencesStore.shared.windowFrame.size
        if size.width < 100 || size.height < 80 {
            size = PreferencesStore.shared.defaultWindowSize.size
        }
        return size
    }

    private func applySize(_ panel: NSPanel) {
        let card = rememberedCardSize()
        let pad = Self.shadowPadding
        panel.setContentSize(CGSize(width: card.width + pad * 2, height: card.height + pad * 2))
        updateShadowPath()
    }

    /// 锚定在输入框旁（AX 光标 → 字段矩形 → 鼠标）。绝不复用上次的窗口原点。
    private func placeNearInput(_ panel: NSPanel) {
        let pad = Self.shadowPadding
        let cardSize = CGSize(
            width: panel.frame.width - pad * 2,
            height: panel.frame.height - pad * 2
        )
        let gap: CGFloat = 10
        let mouse = NSEvent.mouseLocation

        let rawAnchor = FocusTracker.shared.captured?.anchorRect
            ?? CGRect(x: mouse.x, y: mouse.y - 8, width: 2, height: 16)

        // 超宽字段（Chrome 地址栏）：锚点收敛到鼠标附近的字段内部。
        var anchor = rawAnchor
        if rawAnchor.width > 280 {
            let x = min(max(mouse.x - 16, rawAnchor.minX), max(rawAnchor.maxX - 48, rawAnchor.minX))
            anchor = CGRect(x: x, y: rawAnchor.minY, width: 48, height: max(rawAnchor.height, 18))
        }

        var origin = CGPoint(
            x: anchor.midX - min(cardSize.width * 0.25, 80),
            y: anchor.minY - gap - cardSize.height
        )

        let screen = NSScreen.screens.first { $0.frame.intersects(anchor) }
            ?? NSScreen.screens.first { $0.frame.contains(mouse) }
            ?? NSScreen.main
            ?? NSScreen.screens.first

        if let visible = screen?.visibleFrame {
            if origin.y < visible.minY + pad {
                origin.y = anchor.maxY + gap
            }
            origin.x = min(max(origin.x, visible.minX + pad), visible.maxX - cardSize.width - pad)
            origin.y = min(max(origin.y, visible.minY + pad), visible.maxY - cardSize.height - pad)
        }

        panel.setFrame(
            NSRect(
                origin: CGPoint(x: origin.x - pad, y: origin.y - pad),
                size: CGSize(width: cardSize.width + pad * 2, height: cardSize.height + pad * 2)
            ),
            display: true
        )
    }

    private func updateShadowPath() {
        guard let host = shadowHost else { return }
        host.layoutSubtreeIfNeeded()
        host.layer?.shadowPath = CGPath(
            roundedRect: host.bounds,
            cornerWidth: 10,
            cornerHeight: 10,
            transform: nil
        )
    }

    private func presentInjectFailure(_ error: Error, text: String) {
        HistoryStore.shared.add(text)
        let alert = NSAlert()
        alert.messageText = String(localized: "panel.inject.failed.title")
        alert.informativeText = error.localizedDescription
            + "\n" + String(localized: "panel.inject.failed.clipboard")
        alert.alertStyle = .warning
        if case TextInjector.InjectError.accessibilityDenied = error {
            alert.addButton(withTitle: String(localized: "panel.permission.open_settings"))
            alert.addButton(withTitle: String(localized: "alert.ok"))
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            if alert.runModal() == .alertFirstButtonReturn {
                AccessibilityPermission.openSystemSettings()
            }
        } else {
            alert.addButton(withTitle: String(localized: "alert.ok"))
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            alert.runModal()
        }
    }

    func windowDidResignKey(_ notification: Notification) {
        updateFocusVisual()
        // 点击其他应用的窗口时，resignKey 往往先于 didActivate 触发。
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self, self.isVisible else { return }
            guard Date() >= self.suppressAutoHideUntil else { return }
            guard SpeechDictationService.shared.status != .preparing else { return }
            guard let panel = self.panel, !panel.isKeyWindow else { return }
            // 失去 key 且当前前台不是本应用进程 → 关闭。
            let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
            if front != Bundle.main.bundleIdentifier {
                self.dismissPassively()
            }
        }
    }

    func windowDidBecomeKey(_ notification: Notification) {
        updateFocusVisual()
    }

    func windowDidResize(_ notification: Notification) {
        updateShadowPath()
        persistCardFrame()
    }

    func windowDidMove(_ notification: Notification) {
        persistCardFrame()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        dismissActively()
        return false
    }

    private func persistCardFrame() {
        guard let panel, panel.isVisible else { return }
        let pad = Self.shadowPadding
        PreferencesStore.shared.windowFrame = CGRect(
            x: panel.frame.origin.x + pad,
            y: panel.frame.origin.y + pad,
            width: panel.frame.width - pad * 2,
            height: panel.frame.height - pad * 2
        )
    }

    private func startDictationIfNeeded() {
        guard PreferencesStore.shared.voiceAutoStartOnShow else { return }
        startDictation()
    }

    func toggleDictation() {
        if SpeechDictationService.shared.isListening {
            SpeechDictationService.shared.stop()
            viewModel.applyDictation(
                committed: SpeechDictationService.shared.committedText,
                volatile: ""
            )
            PreferencesStore.shared.voiceAutoStartOnShow = false
            return
        }
        PreferencesStore.shared.voiceAutoStartOnShow = true
        startDictation()
    }

    private func startDictation() {
        suppressAutoHideUntil = Date().addingTimeInterval(30)
        TextRefinementService.shared.prewarm()
        Task { @MainActor in
            viewModel.beginDictationSession()
            await SpeechDictationService.shared.start()
            if isVisible {
                suppressAutoHideUntil = Date().addingTimeInterval(0.8)
            }
        }
    }

    var canRevertLastCleanup: Bool {
        TextRefinementService.shared.canRevertLastCleanup
    }

    func revertLastCleanup() {
        guard let pair = TextRefinementService.shared.consumeCleanupRevert() else { return }
        let target = lastInjectTarget
        Task { @MainActor in
            if let current = FocusTracker.shared.focusedFieldValue(),
               current != pair.pasted,
               !current.contains(pair.pasted) {
                presentRevertUnavailable()
                return
            }
            do {
                try await TextInjector.shared.inject(pair.original, into: target)
            } catch {
                presentInjectFailure(error, text: pair.original)
            }
        }
    }

    private func presentRevertUnavailable() {
        let alert = NSAlert()
        alert.messageText = String(localized: "panel.voice.revert.unavailable.title")
        alert.informativeText = String(localized: "panel.voice.revert.unavailable.body")
        alert.alertStyle = .informational
        alert.addButton(withTitle: String(localized: "alert.ok"))
        alert.runModal()
        TextRefinementService.shared.clearCleanupRevert()
    }
}

/// Maccy / SaneClip 模式：不激活应用但仍能成为 key 以接收输入的浮动面板。
private final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// 自绘边框；编辑器持有键盘焦点时叠加一层光晕作为自有焦点态。
private final class BorderOverlayView: NSView {
    var borderColor: NSColor = .systemBlue
    var isFocused: Bool = false
    var lineWidth: CGFloat = 2

    override var isOpaque: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        let inset = lineWidth / 2
        let path = NSBezierPath(
            roundedRect: bounds.insetBy(dx: inset, dy: inset),
            xRadius: 10 - inset,
            yRadius: 10 - inset
        )
        path.lineWidth = lineWidth
        borderColor.setStroke()
        path.stroke()

        if isFocused {
            let glowInset = inset - 2
            let glow = NSBezierPath(
                roundedRect: bounds.insetBy(dx: glowInset, dy: glowInset),
                xRadius: 11 - glowInset,
                yRadius: 11 - glowInset
            )
            glow.lineWidth = 1.5
            borderColor.withAlphaComponent(0.35).setStroke()
            glow.stroke()
        }
    }
}

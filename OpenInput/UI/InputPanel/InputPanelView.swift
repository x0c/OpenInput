import AppKit
import SwiftUI

/// 小窗输入面板的视图模型：编辑文本、历史浏览状态与回调。
@MainActor
@Observable
final class InputPanelViewModel {
    var text: String = ""
    var historyIndex: Int? = nil
    var showHistoryPopover: Bool = false
    var historyQuery: String = ""

    var onSubmit: (() -> Void)?
    var onCancel: (() -> Void)?
    var onBorderNeedsUpdate: (() -> Void)?
    var onToggleDictation: (() -> Void)?

    private var draftBeforeHistory: String = ""
    private weak var textView: NSTextView?
    private var dictationPrefix = ""
    private var acceptedCommitted = ""
    private var applyingDictation = false

    var currentText: String { text }

    var characterCount: Int { text.count }

    var filteredHistory: [HistoryItem] {
        HistoryStore.shared.filtered(query: historyQuery)
    }

    func bind(textView: NSTextView) {
        self.textView = textView
    }

    var hasEditorFocus: Bool {
        guard let textView else { return false }
        return textView.window?.firstResponder === textView
            || textView.window?.firstResponder === textView.enclosingScrollView
    }

    func editorScreenPoint() -> NSPoint? {
        guard let textView, let window = textView.window else { return nil }
        let local = NSPoint(x: textView.bounds.midX, y: textView.bounds.midY)
        let inWindow = textView.convert(local, to: nil)
        return window.convertPoint(toScreen: inWindow)
    }

    func focusEditor(force: Bool = false) {
        guard let textView else { return }
        let apply = {
            guard let window = textView.window else { return }
            window.makeKey()
            window.makeFirstResponder(textView)
            textView.setSelectedRange(NSRange(location: textView.string.utf16.count, length: 0))
        }
        if force {
            apply()
        }
        DispatchQueue.main.async { apply() }
    }

    func resetDraft() {
        text = ""
        historyIndex = nil
        draftBeforeHistory = ""
        historyQuery = ""
        showHistoryPopover = false
        dictationPrefix = ""
        acceptedCommitted = ""
        textView?.string = ""
    }

    func beginDictationSession() {
        dictationPrefix = text
        acceptedCommitted = ""
    }

    func applyDictation(committed: String, volatile: String) {
        if let textView, textView.hasMarkedText() { return }
        let newPart: String
        if committed.hasPrefix(acceptedCommitted) {
            newPart = String(committed.dropFirst(acceptedCommitted.count))
        } else {
            acceptedCommitted = ""
            newPart = committed
        }
        let body = dictationPrefix + newPart
        applyingDictation = true
        text = body
        guard let textView else {
            applyingDictation = false
            return
        }
        let font = textView.font ?? NSFont.systemFont(ofSize: 14)
        let result = NSMutableAttributedString(string: body, attributes: [
            .font: font,
            .foregroundColor: NSColor.textColor
        ])
        if !volatile.isEmpty {
            result.append(NSAttributedString(string: volatile, attributes: [
                .font: font,
                .foregroundColor: NSColor.secondaryLabelColor
            ]))
        }
        textView.undoManager?.disableUndoRegistration()
        textView.textStorage?.setAttributedString(result)
        textView.setSelectedRange(NSRange(location: result.length, length: 0))
        textView.undoManager?.enableUndoRegistration()
        applyingDictation = false
    }

    var isApplyingDictation: Bool { applyingDictation }

    func handleUserEditDuringDictation() {
        guard SpeechDictationService.shared.isListening, !applyingDictation else { return }
        dictationPrefix = text
        acceptedCommitted = SpeechDictationService.shared.committedText
    }

    func setText(_ value: String) {
        text = value
        textView?.string = value
        if let textView {
            textView.setSelectedRange(NSRange(location: value.utf16.count, length: 0))
        }
    }

    func openHistory() {
        guard !HistoryStore.shared.items.isEmpty else { return }
        showHistoryPopover = true
        if historyIndex == nil {
            draftBeforeHistory = text
            selectHistory(at: 0)
        }
    }

    func closeHistoryPopover() {
        showHistoryPopover = false
        historyQuery = ""
    }

    func selectHistory(at index: Int) {
        let items = filteredHistory
        guard items.indices.contains(index) else { return }
        historyIndex = index
        setText(items[index].text)
    }

    func selectHistoryItem(_ item: HistoryItem) {
        if let idx = filteredHistory.firstIndex(of: item) {
            historyIndex = idx
        }
        setText(item.text)
        showHistoryPopover = false
        historyQuery = ""
        focusEditor()
    }

    /// 草稿为空或已在浏览历史：↑ 向前翻，顺带打开列表。
    func handleHistoryUp() -> Bool {
        let items = filteredHistory
        guard !items.isEmpty else { return false }

        showHistoryPopover = true

        if historyIndex == nil {
            if !text.isEmpty && draftBeforeHistory.isEmpty {
                draftBeforeHistory = text
            } else if text.isEmpty {
                draftBeforeHistory = ""
            }
            selectHistory(at: 0)
            return true
        }

        if let index = historyIndex {
            let next = min(index + 1, items.count - 1)
            selectHistory(at: next)
            return true
        }
        return false
    }

    func handleHistoryDown() -> Bool {
        guard showHistoryPopover || historyIndex != nil else { return false }
        guard let index = historyIndex else { return false }

        if index == 0 {
            historyIndex = nil
            setText(draftBeforeHistory)
            if draftBeforeHistory.isEmpty {
                closeHistoryPopover()
            }
            return true
        }

        selectHistory(at: index - 1)
        return true
    }

    func deleteCurrentHistoryItem() -> Bool {
        let items = filteredHistory
        guard let index = historyIndex, items.indices.contains(index) else { return false }
        let id = items[index].id
        HistoryStore.shared.delete(id)

        let remaining = filteredHistory
        if remaining.isEmpty {
            historyIndex = nil
            setText(draftBeforeHistory)
            closeHistoryPopover()
            return true
        }
        selectHistory(at: min(index, remaining.count - 1))
        return true
    }

    func submit() {
        onSubmit?()
    }

    func cancel() {
        if showHistoryPopover {
            closeHistoryPopover()
            historyIndex = nil
            setText(draftBeforeHistory)
            return
        }
        onCancel?()
    }
}

struct InputPanelRootView: View {
    private enum ActionFocus: Hashable {
        case history
        case voice
        case close
    }

    let viewModel: InputPanelViewModel
    private let preferences = PreferencesStore.shared
    private let history = HistoryStore.shared
    private let dictation = SpeechDictationService.shared
    @FocusState private var focusedAction: ActionFocus?

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 0) {
                if viewModel.showHistoryPopover {
                    HistoryPopoverView(viewModel: viewModel)
                        .frame(maxHeight: 140)
                        .padding(.horizontal, 8)
                        .padding(.top, 8)
                }

                InputTextViewRepresentable(viewModel: viewModel)
                    .padding(.horizontal, 10)
                    .padding(.top, viewModel.showHistoryPopover ? 4 : 10)
                    .padding(.trailing, 18) // 留出悬浮 ✕ 按钮的空间
                    .padding(.bottom, 4)

                HStack(spacing: 10) {
                    Text("panel.characterCount \(viewModel.characterCount)")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if viewModel.historyIndex != nil {
                        Text("panel.historyIndicator \((viewModel.historyIndex ?? 0) + 1) \(max(viewModel.filteredHistory.count, 1))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if let message = dictation.statusMessage, dictation.status != .listening {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .lineLimit(1)
                    } else if dictation.isListening {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(Color.red.opacity(0.35 + Double(dictation.inputLevel) * 0.65))
                                .frame(width: 7, height: 7)
                            Text(listeningCaption(for: dictation.status))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Button {
                        viewModel.onToggleDictation?()
                    } label: {
                        Image(systemName: dictation.isListening ? "mic.fill" : "mic")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(dictation.isListening ? Color.red : Color.secondary)
                    .help(dictation.isSupportedByOS ? "panel.voice.toggle" : "panel.voice.unavailable.os")
                    .padding(4)
                    .background(
                        Circle().fill(focusedAction == .voice ? Color.accentColor.opacity(0.16) : .clear)
                    )
                    .overlay {
                        Circle()
                            .strokeBorder(focusedAction == .voice ? Color.accentColor.opacity(0.78) : .clear, lineWidth: 1.5)
                    }
                    .focusEffectDisabled()
                    .focused($focusedAction, equals: .voice)
                    .accessibilityLabel(Text("panel.voice.toggle.accessibility.label"))
                    .accessibilityHint(Text("panel.voice.toggle.accessibility.hint"))
                    .disabled(!dictation.isSupportedByOS && !dictation.isListening)

                    Button {
                        if viewModel.showHistoryPopover {
                            viewModel.closeHistoryPopover()
                        } else {
                            viewModel.openHistory()
                        }
                    } label: {
                        Image(systemName: "clock")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("panel.history.shortcut")
                    .padding(4)
                    .background(
                        Circle().fill(focusedAction == .history ? Color.accentColor.opacity(0.16) : .clear)
                    )
                    .overlay {
                        Circle()
                            .strokeBorder(focusedAction == .history ? Color.accentColor.opacity(0.78) : .clear, lineWidth: 1.5)
                    }
                    .focusEffectDisabled()
                    .focused($focusedAction, equals: .history)
                    .accessibilityLabel(Text("panel.history.accessibility.label"))
                    .accessibilityHint(Text("panel.history.accessibility.hint"))
                    .disabled(history.items.isEmpty)

                    Text("panel.hint.insert")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("panel.hint.newline")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("panel.hint.close")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            }

            Button {
                viewModel.onCancel?()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.secondary, Color(nsColor: .controlBackgroundColor).opacity(0.92))
                    .font(.system(size: 16))
                    .shadow(color: .black.opacity(0.12), radius: 1, y: 0.5)
            }
            .buttonStyle(.plain)
            .help("panel.close")
            .padding(6)
            .background(
                Circle().fill(focusedAction == .close ? Color.accentColor.opacity(0.16) : .clear)
            )
            .overlay {
                Circle()
                    .strokeBorder(focusedAction == .close ? Color.accentColor.opacity(0.78) : .clear, lineWidth: 1.5)
            }
            .focusEffectDisabled()
            .focused($focusedAction, equals: .close)
            .accessibilityLabel(Text("panel.close"))
            .accessibilityHint(Text("panel.close.accessibility.hint"))
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onChange(of: preferences.borderColor) { _, _ in
            viewModel.onBorderNeedsUpdate?()
        }
        .onChange(of: dictation.committedText) { _, _ in
            applyDictationIfNeeded()
        }
        .onChange(of: dictation.volatilePreview) { _, _ in
            applyDictationIfNeeded()
        }
    }

    private func applyDictationIfNeeded() {
        guard dictation.isListening || !dictation.volatilePreview.isEmpty else { return }
        viewModel.applyDictation(committed: dictation.committedText, volatile: dictation.volatilePreview)
    }

    private func listeningCaption(for status: SpeechDictationService.Status) -> LocalizedStringKey {
        switch status {
        case .installingAssets:
            "panel.voice.installing"
        case .preparing:
            "panel.voice.preparing"
        default:
            "panel.voice.listening"
        }
    }
}

struct HistoryPopoverView: View {
    @Bindable var viewModel: InputPanelViewModel
    @FocusState private var searchFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                TextField("common.search.history", text: $viewModel.historyQuery)
                    .textFieldStyle(.plain)
                    .font(.caption)
                    .focused($searchFocused)
                    .focusEffectDisabled()
                    .accessibilityLabel(Text("common.search.history"))
                    .accessibilityHint(Text("panel.history.search.accessibility.hint"))
                if !viewModel.historyQuery.isEmpty {
                    Button {
                        viewModel.historyQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("panel.history.clearSearch.accessibility.label"))
                    .accessibilityHint(Text("panel.history.clearSearch.accessibility.hint"))
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
            // 自有焦点态：键盘导航聚焦时描边提示，替代系统蓝色焦点框。
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(
                        searchFocused ? Color.accentColor.opacity(0.65) : .clear,
                        lineWidth: 1.5
                    )
            )

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(viewModel.filteredHistory.enumerated()), id: \.element.id) { index, item in
                            HistoryRow(
                                item: item,
                                isSelected: viewModel.historyIndex == index
                            ) {
                                viewModel.selectHistoryItem(item)
                            }
                            .id(item.id)
                        }
                    }
                }
                .onChange(of: viewModel.historyIndex) { _, newValue in
                    guard let newValue,
                          viewModel.filteredHistory.indices.contains(newValue) else { return }
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.12)) {
                        proxy.scrollTo(viewModel.filteredHistory[newValue].id, anchor: .center)
                    }
                }
            }
        }
        .padding(6)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.55), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct HistoryRow: View {
    let item: HistoryItem
    let isSelected: Bool
    let onSelect: () -> Void
    @FocusState private var isFocused: Bool

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.preview)
                        .font(.caption)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text(item.relativeTime)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(isSelected ? Color.accentColor.opacity(0.22) : Color.clear)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 5)
                    .strokeBorder(isFocused ? Color.accentColor.opacity(0.78) : .clear, lineWidth: 1.5)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .focused($isFocused)
        .accessibilityLabel(Text(item.preview))
        .accessibilityHint(Text("panel.history.item.accessibility.hint"))
    }
}

struct InputTextViewRepresentable: NSViewRepresentable {
    var viewModel: InputPanelViewModel

    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.borderType = .noBorder
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay

        guard let textView = scroll.documentView as? NSTextView else { return scroll }
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.allowsUndo = true
        textView.font = NSFont.systemFont(ofSize: 14)
        textView.textContainerInset = NSSize(width: 4, height: 4)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.usesFindBar = false
        textView.string = viewModel.text
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.lineFragmentPadding = 2
        textView.setAccessibilityLabel(String(localized: "panel.editor.accessibility.label"))
        textView.setAccessibilityHelp(String(localized: "panel.editor.accessibility.hint"))

        context.coordinator.textView = textView
        viewModel.bind(textView: textView)
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        context.coordinator.viewModel = viewModel
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var viewModel: InputPanelViewModel
        weak var textView: NSTextView?

        init(viewModel: InputPanelViewModel) {
            self.viewModel = viewModel
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            if viewModel.isApplyingDictation { return }
            viewModel.text = textView.string
            viewModel.handleUserEditDuringDictation()
            if viewModel.historyIndex != nil {
                let items = viewModel.filteredHistory
                if let idx = viewModel.historyIndex, items.indices.contains(idx),
                   items[idx].text != textView.string {
                    viewModel.historyIndex = nil
                }
            }
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            // 输入法组合中不拦截按键，交给输入法。
            if textView.hasMarkedText() {
                return false
            }

            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                if NSEvent.modifierFlags.contains(.shift) {
                    textView.insertText("\n", replacementRange: textView.selectedRange())
                    return true
                }
                viewModel.submit()
                return true
            }
            if commandSelector == #selector(NSResponder.insertLineBreak(_:))
                || commandSelector == #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)) {
                textView.insertText("\n", replacementRange: textView.selectedRange())
                return true
            }

            if commandSelector == #selector(NSResponder.insertTab(_:)) {
                textView.insertText("\t", replacementRange: textView.selectedRange())
                return true
            }

            if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                viewModel.cancel()
                return true
            }

            if commandSelector == #selector(NSResponder.deleteBackward(_:))
                || commandSelector == #selector(NSResponder.deleteForward(_:))
                || commandSelector == #selector(NSResponder.deleteToBeginningOfLine(_:)) {
                if NSEvent.modifierFlags.contains(.command), viewModel.historyIndex != nil {
                    return viewModel.deleteCurrentHistoryItem()
                }
            }

            if commandSelector == #selector(NSResponder.moveUp(_:)) {
                if NSEvent.modifierFlags.contains(.option)
                    || viewModel.text.isEmpty
                    || viewModel.historyIndex != nil
                    || viewModel.showHistoryPopover {
                    return viewModel.handleHistoryUp()
                }
                return false
            }

            if commandSelector == #selector(NSResponder.moveDown(_:)) {
                if viewModel.historyIndex != nil || viewModel.showHistoryPopover {
                    return viewModel.handleHistoryDown()
                }
                return false
            }

            return false
        }
    }
}

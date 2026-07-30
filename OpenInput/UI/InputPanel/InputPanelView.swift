import AppKit
import Combine
import SwiftUI

@MainActor
final class InputPanelViewModel: ObservableObject {
    @Published var text: String = ""
    @Published var historyIndex: Int? = nil
    @Published var showHistoryPopover: Bool = false
    @Published var historyQuery: String = ""

    var onSubmit: (() -> Void)?
    var onCancel: (() -> Void)?
    var onBorderNeedsUpdate: (() -> Void)?

    private var draftBeforeHistory: String = ""
    private weak var textView: NSTextView?

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
        DispatchQueue.main.async(execute: apply)
    }

    func resetDraft() {
        text = ""
        historyIndex = nil
        draftBeforeHistory = ""
        historyQuery = ""
        showHistoryPopover = false
        textView?.string = ""
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

    /// Empty draft or already browsing: ↑ moves older. Also opens the list.
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
        let items = filteredHistory
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
    @ObservedObject var viewModel: InputPanelViewModel
    @ObservedObject private var preferences = PreferencesStore.shared
    @ObservedObject private var history = HistoryStore.shared

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
                    .padding(.trailing, 18) // room so text doesn't sit under the floating ✕
                    .padding(.bottom, 4)

                HStack(spacing: 10) {
                    Text("字数: \(viewModel.characterCount)")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if viewModel.historyIndex != nil {
                        Text("历史 \( (viewModel.historyIndex ?? 0) + 1 )/\(max(viewModel.filteredHistory.count, 1))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

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
                    .help("历史记录（↑↓）")
                    .disabled(history.items.isEmpty)

                    Text("↩ 插入")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("⇧↩ 换行")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("esc 关闭")
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
            .help("关闭")
            .padding(6)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onChange(of: preferences.borderColor) { _, _ in
            viewModel.onBorderNeedsUpdate?()
        }
    }
}

struct HistoryPopoverView: View {
    @ObservedObject var viewModel: InputPanelViewModel

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                TextField("搜索历史", text: $viewModel.historyQuery)
                    .textFieldStyle(.plain)
                    .font(.caption)
                if !viewModel.historyQuery.isEmpty {
                    Button {
                        viewModel.historyQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6))

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
                    withAnimation(.easeInOut(duration: 0.12)) {
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
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct InputTextViewRepresentable: NSViewRepresentable {
    @ObservedObject var viewModel: InputPanelViewModel

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
            viewModel.text = textView.string
            if viewModel.historyIndex != nil {
                let items = viewModel.filteredHistory
                if let idx = viewModel.historyIndex, items.indices.contains(idx),
                   items[idx].text != textView.string {
                    viewModel.historyIndex = nil
                }
            }
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
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

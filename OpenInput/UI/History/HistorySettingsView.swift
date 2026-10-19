import AppKit
import SwiftUI

struct HistorySettingsView: View {
    @State private var store = HistoryStore.shared
    @State private var query = ""
    @State private var selection = Set<HistoryItem.ID>()

    private var filtered: [HistoryItem] {
        store.filtered(query: query)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                HistorySearchField(text: $query)
                    .frame(height: 24)
                Button("history.clear.all", role: .destructive) {
                    store.clear()
                    selection.removeAll()
                }
                .disabled(store.items.isEmpty)
            }
            .padding(12)

            if filtered.isEmpty {
                ContentUnavailableView(
                    store.items.isEmpty ? "history.empty.title" : "history.empty.noMatch",
                    systemImage: "clock",
                    description: Text(store.items.isEmpty
                        ? "history.empty.description"
                        : "history.empty.noMatch.description")
                )
            } else {
                List(selection: $selection) {
                    ForEach(filtered) { item in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.preview)
                                .lineLimit(3)
                            Text(item.relativeTime)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .tag(item.id)
                        .contextMenu {
                            Button("common.copy") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(item.text, forType: .string)
                            }
                            Button("common.delete", role: .destructive) {
                                store.delete(item.id)
                                selection.remove(item.id)
                            }
                        }
                    }
                    .onDelete { indexSet in
                        let ids = indexSet.map { filtered[$0].id }
                        ids.forEach { store.delete($0) }
                        selection.subtract(ids)
                    }
                }
                .listStyle(.inset)
            }

            HStack {
                Text("history.footer.count \(store.items.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("history.delete.shortcut")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Button("history.delete.selected", role: .destructive) {
                    selection.forEach { store.delete($0) }
                    selection.removeAll()
                }
                .disabled(selection.isEmpty)
                .keyboardShortcut(.delete, modifiers: .command)
            }
            .padding(12)
        }
        .frame(height: 400)
        .focusEffectDisabled()
    }
}

private struct HistorySearchField: NSViewRepresentable {
    @Binding var text: String
    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }
    func makeNSView(context: Context) -> NSSearchField {
        let field = NSSearchField()
        field.placeholderString = String(localized: "common.search.history")
        field.focusRingType = .none
        field.delegate = context.coordinator
        field.setAccessibilityLabel(String(localized: "common.search.history"))
        return field
    }
    func updateNSView(_ field: NSSearchField, context: Context) {
        context.coordinator.text = $text
        if field.stringValue != text { field.stringValue = text }
    }
    final class Coordinator: NSObject, NSSearchFieldDelegate {
        var text: Binding<String>
        init(text: Binding<String>) { self.text = text }
        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSSearchField else { return }
            text.wrappedValue = field.stringValue
        }
    }
}

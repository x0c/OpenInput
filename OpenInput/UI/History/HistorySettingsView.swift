import AppKit
import SwiftUI

struct HistorySettingsView: View {
    @State private var store = HistoryStore.shared
    @State private var query = ""
    @State private var selection = Set<HistoryItem.ID>()
    @FocusState private var searchFocused: Bool

    private var filtered: [HistoryItem] {
        store.filtered(query: query)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                TextField("common.search.history", text: $query)
                    .textFieldStyle(.plain)
                    .focused($searchFocused)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    // 自有焦点态：聚焦时描边提示，替代系统蓝色焦点框。
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color(nsColor: .controlBackgroundColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(
                                searchFocused ? Color.accentColor.opacity(0.65) : Color.clear,
                                lineWidth: 1.5
                            )
                    )
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
    }
}

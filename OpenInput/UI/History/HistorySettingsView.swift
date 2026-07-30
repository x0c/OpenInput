import AppKit
import SwiftUI

struct HistorySettingsView: View {
    @ObservedObject private var store = HistoryStore.shared
    @State private var query = ""
    @State private var selection = Set<HistoryItem.ID>()

    private var filtered: [HistoryItem] {
        store.filtered(query: query)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                TextField("搜索历史", text: $query)
                    .textFieldStyle(.roundedBorder)
                Button("清空全部", role: .destructive) {
                    store.clear()
                    selection.removeAll()
                }
                .disabled(store.items.isEmpty)
            }
            .padding(12)

            if filtered.isEmpty {
                ContentUnavailableView(
                    store.items.isEmpty ? "暂无历史" : "无匹配结果",
                    systemImage: "clock",
                    description: Text(store.items.isEmpty ? "插入过的文本会出现在这里" : "试试其他关键词")
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
                            Button("复制") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(item.text, forType: .string)
                            }
                            Button("删除", role: .destructive) {
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
                Text("共 \(store.items.count) 条")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("⌘⌫ 删除所选")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Button("删除所选", role: .destructive) {
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

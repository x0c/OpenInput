import Foundation
import Observation
import os

/// 历史记录：本地 JSON 持久化，读写都走失败路径并记录日志。
@MainActor
@Observable
final class HistoryStore {
    static let shared = HistoryStore()

    private(set) var items: [HistoryItem] = []

    private let maxItems = 200
    private let fileURL: URL
    private let logger = Logger(subsystem: "com.x0c.openinput", category: "HistoryStore")

    private init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = support.appendingPathComponent("OpenInput", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("history.json")
        load()
    }

    func add(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // 重复文本移到顶部，不产生重复条目。
        if let existingIndex = items.firstIndex(where: { $0.text == text }) {
            var item = items.remove(at: existingIndex)
            item = HistoryItem(id: item.id, text: item.text, createdAt: Date())
            items.insert(item, at: 0)
            save()
            return
        }

        items.insert(HistoryItem(text: text), at: 0)
        if items.count > maxItems {
            items = Array(items.prefix(maxItems))
        }
        save()
    }

    func delete(_ id: UUID) {
        items.removeAll { $0.id == id }
        save()
    }

    func delete(at offsets: IndexSet) {
        items.remove(atOffsets: offsets)
        save()
    }

    func clear() {
        items.removeAll()
        save()
    }

    func filtered(query: String) -> [HistoryItem] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return items }
        return items.filter { $0.text.localizedCaseInsensitiveContains(q) }
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            items = try JSONDecoder().decode([HistoryItem].self, from: data)
        } catch {
            // 文件损坏时不崩溃、不清空原文件，回退到空历史。
            logger.error("读取历史记录失败，回退为空历史：\(error.localizedDescription)")
        }
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(items)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            logger.error("保存历史记录失败：\(error.localizedDescription)")
        }
    }
}

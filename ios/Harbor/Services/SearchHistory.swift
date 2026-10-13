import Foundation
import Observation

@MainActor @Observable
final class SearchHistory {
    static let shared = SearchHistory()
    private let storage: UserDefaults
    private(set) var items: [String]
    private static let key = "harbor.search.recent"
    init(storage: UserDefaults = .standard) {
        self.storage = storage
        items = Array((storage.stringArray(forKey: Self.key) ?? []).prefix(8))
    }
    func record(_ query: String) {
        let value = String(query.trimmingCharacters(in: .whitespacesAndNewlines).prefix(200))
        guard !value.isEmpty else { return }
        items = Array(([value] + items.filter { $0.caseInsensitiveCompare(value) != .orderedSame }).prefix(8))
        storage.set(items, forKey: Self.key)
    }
    func remove(_ query: String) { items.removeAll { $0 == query }; storage.set(items, forKey: Self.key) }
    func clear() { items = []; storage.removeObject(forKey: Self.key) }
}

enum SearchPresentation {
    static func rows(_ rows: [CatalogRow]) -> [CatalogRow] {
        var seen = Set<String>()
        return rows.compactMap { row in
            guard row.plan.kind != "addon_catalog" else { return nil }
            var result = row
            result.metas = row.metas.filter { seen.insert($0.identity).inserted }
            return result.metas.isEmpty ? nil : result
        }
    }
}

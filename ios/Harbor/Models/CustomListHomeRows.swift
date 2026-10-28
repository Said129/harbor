import Foundation

enum CustomListHomeRows {
    static func selected(_ lists: [CustomList], ids: [String]) -> [CustomList] {
        let byID = Dictionary(lists.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        return ids.compactMap { byID[$0] }.filter { !$0.items.isEmpty }
    }
    static func available(_ lists: [CustomList], ids: [String]) -> [CustomList] {
        let selected = Set(ids)
        return lists.filter { !$0.items.isEmpty && !selected.contains($0.id) }
    }
}

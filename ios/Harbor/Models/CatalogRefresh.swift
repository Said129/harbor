import Foundation

enum CatalogRefresh {
    static func merge<T: Identifiable>(order: [String], received: [T], previous: [T]) -> [T] where T.ID == String {
        let fresh = Dictionary(received.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        let saved = Dictionary(previous.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        // A valid empty row replaces prior data. A failed current request keeps
        // its prior row; identities outside the current plan never reappear.
        return order.compactMap { fresh[$0] ?? saved[$0] }
    }
}

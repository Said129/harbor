import Foundation

/// A Suwayomi server category, used by Desktop's Categories tags.
struct MangaCategory: Equatable, Identifiable, Sendable {
    let id: String
    let name: String
}

enum MangaCategoryRules {
    /// Desktop's category tag rule: only numeric ids and string names count, and the server order decides
    /// the sequence (a missing or invalid order counts as 0, ties keep the server's list order).
    static func categories(from values: [JSONValue]) -> [MangaCategory] {
        let rows: [(index: Int, order: Double, category: MangaCategory)] = values.enumerated().compactMap { index, value in
            guard let id = digitsID(value["id"]), let name = value["name"].string else { return nil }
            return (index: index, order: orderValue(value["order"]), category: MangaCategory(id: id, name: name))
        }
        return rows.sorted { $0.order != $1.order ? $0.order < $1.order : $0.index < $1.index }.map(\.category)
    }

    /// Desktop's /^\d+$/ test on String(id). JSON numbers are accepted when they are whole and not negative.
    static func digitsID(_ value: JSONValue) -> String? {
        switch value {
        case .string(let text): return !text.isEmpty && text.utf8.allSatisfy { (48...57).contains($0) } ? text : nil
        case .integer(let number): return number >= 0 ? String(number) : nil
        case .unsigned(let number): return String(number)
        case .number(let number): return number >= 0 && number < 9.0e15 && number.rounded() == number ? String(Int64(number)) : nil
        default: return nil
        }
    }

    /// Desktop's Number(order) || 0.
    static func orderValue(_ value: JSONValue) -> Double {
        let number: Double?
        switch value {
        case .integer(let raw): number = Double(raw)
        case .unsigned(let raw): number = Double(raw)
        case .number(let raw): number = raw
        case .string(let raw): number = Double(raw)
        default: number = nil
        }
        guard let number, number.isFinite else { return 0 }
        return number
    }
}

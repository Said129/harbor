import Foundation

/// Desktop's Simkl anime grouping (`lib/simkl/anime-grouping.ts`): titles whose normalized names match are one franchise.
/// Only the pure rules are here. Desktop's relations lookup (`enhanceGroupsWithRelations`) needs the network and is not ported.
enum SimklAnimeGrouping {
    struct Item: Equatable, Sendable {
        let simklID: Int
        let title: String
        let year: Int?
    }

    struct Franchise: Equatable, Sendable {
        let key: String
        let name: String
        let simklIDs: [Int]
        let yearStart: Int?
        let yearEnd: Int?
    }

    /// Desktop's `SEASON_PATTERNS`, applied to the lowercased title until none of them matches.
    private static let seasonPatterns: [String] = [
        #"[.°'`:!?,_\-\(\)\[\]\{\}#]+$"#,
        #"\s+season\s*\d+$"#,
        #"\s+s\d+$"#,
        #"\s+\d+(st|nd|rd|th)\s+season$"#,
        #"\s+part\s*\d+$"#,
        #"\s+cour\s*\d+$"#,
        #"\s+(ii|iii|iv|v|vi|vii|viii|ix|x)$"#,
        #"\s+\d+(st|nd|rd|th)$"#,
        #"\s+\d{4}$"#,
        #"\s+final\s+season$"#,
        #"\s+the\s+final$"#,
        #"\s+final$"#,
        #"\s+shippuden$"#,
        #"\s+gaiden$"#,
        #"\s+side\s+story$"#,
        #"\s+r\d?$"#,
        #"\s+tv$"#,
        #"\s+porori\s+hen$"#,
        #"\s+enchousen$"#,
        #"\s+hen$"#,
        #"\s+season$"#,
        #"\s*\(tv\)$"#,
        #"\s*\(movie\)$"#,
        #"\s*\(ova\)$"#,
        #"\s*\[tv\]$"#,
        #"\s*\[movie\]$"#,
        #"\s*\[ova\]$"#,
    ]

    /// Desktop's `normalizeAnimeTitle`: the lowercased title without season and format suffixes, before any colon, letters and digits only.
    static func normalizedTitle(_ title: String) -> String {
        var normalized = title.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
        var changed = true
        while changed {
            changed = false
            for pattern in seasonPatterns {
                if normalized.range(of: pattern, options: [.regularExpression]) != nil {
                    normalized = normalized
                        .replacingOccurrences(of: pattern, with: "", options: [.regularExpression])
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    changed = true
                }
            }
        }
        if let colon = normalized.firstIndex(of: ":") {
            normalized = String(normalized[..<colon]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let allowed = "abcdefghijklmnopqrstuvwxyz0123456789"
        return String(normalized.filter { allowed.contains($0) })
    }

    /// Desktop's `groupAnimeByFranchise`: one franchise per normalized title, years ordered, the shortest title as its name.
    /// Franchises are sorted by name, and ties keep their input order.
    static func franchises(_ items: [Item]) -> [Franchise] {
        var order: [String] = []
        var groups: [String: [Item]] = [:]
        for item in items {
            let key = normalizedTitle(item.title)
            if key.isEmpty { continue }
            if groups[key] == nil { order.append(key) }
            groups[key, default: []].append(item)
        }
        let built = order.map { key -> Franchise in
            let sorted = (groups[key] ?? []).enumerated().sorted { lhs, rhs in
                let left = lhs.element.year ?? 9999, right = rhs.element.year ?? 9999
                if left != right { return left < right }
                return lhs.offset < rhs.offset
            }.map(\.element)
            return franchise(key: key, items: sorted)
        }
        return built.enumerated().sorted { lhs, rhs in
            let comparison = lhs.element.name.localizedCompare(rhs.element.name)
            if comparison != .orderedSame { return comparison == .orderedAscending }
            return lhs.offset < rhs.offset
        }.map(\.element)
    }

    private static func franchise(key: String, items: [Item]) -> Franchise {
        var best = items[0].title
        for item in items.dropFirst() where item.title.utf16.count < best.utf16.count {
            best = item.title
        }
        let years = items.compactMap(\.year)
        return Franchise(key: key, name: best, simklIDs: items.map(\.simklID), yearStart: years.min(), yearEnd: years.max())
    }

    /// Desktop's `computeFranchiseAverageRating`: the mean of the positive ratings, nil when there are none.
    static func averageRating(simklIDs: [Int], rating: (Int) -> Double?) -> Double? {
        let values = simklIDs.compactMap(rating).filter { $0 > 0 }
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    /// Desktop's `formatYearRange`: one year, a `start-end` range, or nothing.
    static func yearRange(start: Int?, end: Int?) -> String {
        if start == nil && end == nil { return "" }
        if start == end, let start { return String(start) }
        if let start, let end { return "\(start)-\(end)" }
        if let start { return String(start) }
        return end.map { String($0) } ?? ""
    }
}

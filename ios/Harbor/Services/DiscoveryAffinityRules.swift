import Foundation

/// Desktop's affinity ranking for feed rows (`src/lib/feed/rank.ts`, `rankByAffinity`). Each genre adds up to 4 and the
/// decade up to 1.5, each weight divided by the largest absolute weight of its map. Rows with no taste keep their order.
/// Desktop's locale penalty is not ported, because iOS has no feed locale weights.
enum DiscoveryAffinityRules {
    static let genreWeight = 4.0
    static let decadeWeight = 1.5

    /// Desktop's `decadeOf`: "1995" becomes "1990s". Nil when the year has no number.
    static func decadeKey(year: String?) -> String? {
        guard let year = year, let value = Int(year.prefix(4)) else { return nil }
        return "\(value / 10 * 10)s"
    }

    /// Desktop's `rankByAffinity`: the items sorted by affinity, highest first, ties in their original order.
    static func ranked(_ items: [Media], affinity: DiscoveryPreferences.Affinity) -> [Media] {
        let genreScale = scale(affinity.genres)
        let decadeScale = scale(affinity.decades)
        let scores = items.map { media -> Double in
            var total = 0.0
            for genre in media.genres ?? [] {
                let weight = affinity.genres[genre] ?? 0
                if weight != 0 { total += weight / genreScale * genreWeight }
            }
            if let decade = decadeKey(year: media.releaseInfo) {
                let weight = affinity.decades[decade] ?? 0
                if weight != 0 { total += weight / decadeScale * decadeWeight }
            }
            return total
        }
        let order = items.indices.sorted { left, right in
            scores[left] == scores[right] ? left < right : scores[left] > scores[right]
        }
        return order.map { items[$0] }
    }

    /// Desktop's `maxAbs(...) || 1`: the largest absolute weight, or 1 when the map is empty or all zero.
    private static func scale(_ weights: [String: Double]) -> Double {
        let largest = weights.values.map { abs($0) }.max() ?? 0
        return largest > 0 ? largest : 1
    }
}

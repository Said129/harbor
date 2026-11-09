import Foundation

/// Desktop's affinity ranking for feed rows (`src/lib/feed/rank.ts`, `rankByAffinity`). Each genre adds up to 4 and the
/// decade up to 1.5, each weight divided by the largest absolute weight of its map. Rows with no taste keep their order.
/// Desktop's locale penalty is not ported, because iOS has no feed locale weights.
enum DiscoveryAffinityRules {
    static let genreWeight = 4.0
    static let decadeWeight = 1.5
    static let localePenalty = 3.0

    struct LocaleBias: Equatable {
        let codes: Set<String>
        let penalty: Double

        static let disabled = LocaleBias(codes: [], penalty: 0)
    }

    struct Downvote {
        let id: String
        let titleKey: String
    }

    /// Desktop combines preferred languages and TMDB language before falling back to region.
    /// The native stream-language preference is the closest equivalent to Desktop's preferredLanguages.
    static func localeBias(preferredLanguages: [String], metadataLanguage: String, region: String, enabled: Bool = true) -> LocaleBias {
        guard enabled else { return .disabled }
        var codes = Set((preferredLanguages + [metadataLanguage]).compactMap(languageCode))
        if codes.isEmpty, let language = regionLanguages[region.uppercased()] { codes.insert(language) }
        return codes.isEmpty ? .disabled : LocaleBias(codes: codes, penalty: localePenalty)
    }

    static func languageCode(_ value: String) -> String? {
        let base = SubtitleLanguages.normalize(value).split(separator: "-").first.map(String.init) ?? ""
        return base.utf8.count == 2 && base.utf8.allSatisfy { (97...122).contains($0) } ? base : nil
    }

    private static let regionLanguages: [String: String] = [
        "US": "en", "GB": "en", "CA": "en", "AU": "en", "NZ": "en", "IE": "en",
        "ES": "es", "MX": "es", "AR": "es", "CO": "es", "CL": "es", "PE": "es",
        "FR": "fr", "BE": "fr", "DE": "de", "AT": "de", "IT": "it", "BR": "pt",
        "PT": "pt", "JP": "ja", "KR": "ko", "CN": "zh", "TW": "zh", "HK": "zh",
        "IN": "hi", "RU": "ru", "SE": "sv", "DK": "da", "NO": "no", "NL": "nl",
        "PL": "pl", "TR": "tr",
    ]

    /// Desktop's `decadeOf`: "1995" becomes "1990s". Nil when the year has no number.
    static func decadeKey(year: String?) -> String? {
        guard let year = year, let value = Int(year.prefix(4)) else { return nil }
        return "\(value / 10 * 10)s"
    }

    /// Desktop's `rankByAffinity`: the items sorted by affinity, highest first, ties in their original order.
    static func ranked(_ items: [Media], affinity: DiscoveryPreferences.Affinity, locale: LocaleBias = .disabled) -> [Media] {
        let genreScale = scale(affinity.genres)
        let decadeScale = scale(affinity.decades)
        let languageScale = scale(affinity.languages)
        let scores = items.map { media -> Double in
            var total = localeScore(media, locale: locale, languages: affinity.languages, scale: languageScale)
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

    /// Desktop's Discover recommendations hide downvoted ids and title aliases from suggestion pools.
    static func excludingDownvoted(_ items: [Media], downvotes: [Downvote]) -> [Media] {
        let ids = Set(downvotes.map(\.id))
        let titles = Set(downvotes.map(\.titleKey).filter { !$0.isEmpty })
        return items.filter { !ids.contains($0.id) && !titles.contains(DiscoveryPreferences.titleKey($0.name)) }
    }

    private static func localeScore(_ media: Media, locale: LocaleBias, languages: [String: Double], scale: Double) -> Double {
        guard locale.penalty != 0,
              let originalLanguage = media.originalLanguage,
              let code = languageCode(originalLanguage),
              !locale.codes.contains(code) else { return 0 }
        let liked = max(0, (languages[code] ?? 0) / scale)
        return -locale.penalty * (1 - liked)
    }

    /// Desktop's `maxAbs(...) || 1`: the largest absolute weight, or 1 when the map is empty or all zero.
    private static func scale(_ weights: [String: Double]) -> Double {
        let largest = weights.values.map { abs($0) }.max() ?? 0
        return largest > 0 ? largest : 1
    }
}

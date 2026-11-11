import Foundation

/// Desktop's anime picks rules: which titles the Anime page's hero and Top Picks may show
/// (`lib/anime-filter.ts`, `views/anime.tsx`) and which genres seed the picks (`lib/anime-top-picks-utils.ts`).
/// Pure value logic. The Anime page applies it; nothing here reads the network or the Keychain.
enum AnimePicksPolicy {
    struct Options: Equatable, Sendable {
        /// Desktop's `animeFavoriteGenres`: Jikan genre ids, used to seed the genre rows.
        var favoriteGenres: [Int]
        /// Desktop's `animeExcludeOrigins`: ISO country codes whose titles are hidden.
        var excludeOrigins: [String]
        /// Desktop's `animeHideWatchedPicks`.
        var hideWatched: Bool

        /// Desktop's `defaults.ts`: no favourite genres, Chinese donghua hidden, watched titles hidden.
        static let desktopDefault = Options(favoriteGenres: [], excludeOrigins: ["CN"], hideWatched: true)
    }

    struct Genre: Equatable, Sendable {
        let id: Int
        let label: String
    }

    struct Origin: Equatable, Sendable {
        let code: String
        let label: String
    }

    /// Desktop's `ANIME_GENRE_OPTIONS` (`components/anime-genre-picker.tsx`) with the Jikan ids of `ANIME_GENRE_TO_JIKAN`.
    static let genres: [Genre] = [
        Genre(id: 1, label: "Action"), Genre(id: 2, label: "Adventure"), Genre(id: 4, label: "Comedy"),
        Genre(id: 8, label: "Drama"), Genre(id: 10, label: "Fantasy"), Genre(id: 24, label: "Sci-Fi"),
        Genre(id: 22, label: "Romance"), Genre(id: 36, label: "Slice of Life"), Genre(id: 37, label: "Supernatural"),
        Genre(id: 7, label: "Mystery"), Genre(id: 40, label: "Psychological"), Genre(id: 14, label: "Horror"),
        Genre(id: 41, label: "Thriller"), Genre(id: 18, label: "Mecha"), Genre(id: 30, label: "Sports"),
        Genre(id: 19, label: "Music")
    ]

    /// Desktop's `ORIGIN_OPTIONS` (`lib/anime-filter.ts`).
    static let origins: [Origin] = [
        Origin(code: "CN", label: "Chinese (Donghua)"),
        Origin(code: "KR", label: "Korean (Aeni)"),
        Origin(code: "TW", label: "Taiwanese")
    ]

    /// Desktop's `animeSeedGenres` takes at most three genres.
    static let seedLimit = 3

    static func genreID(named name: String) -> Int? {
        genres.first { $0.label == name }?.id
    }

    /// Desktop's `animeSeedGenres`: genres from the viewer's own taste first (`tasteGenres`, most watched first),
    /// then the favourites, at most `seedLimit`, with no repeats.
    static func seedGenreIDs(favorites: [Int], tasteGenres: [String]) -> [Int] {
        var out: [Int] = []
        for name in tasteGenres {
            guard let id = genreID(named: name), !out.contains(id) else { continue }
            out.append(id)
            if out.count >= seedLimit { return out }
        }
        for id in favorites {
            if out.count >= seedLimit { break }
            if !out.contains(id) { out.append(id) }
        }
        return out
    }

    /// Desktop's `animeOriginExcluded`: a title with a known country on the excluded list.
    /// A title without a country is never hidden by this rule.
    static func originExcluded(_ media: Media, excludeOrigins: [String]) -> Bool {
        guard !excludeOrigins.isEmpty, let country = media.country else { return false }
        return excludeOrigins.contains(country)
    }

    /// Desktop's `animeFiltered`: hidden by origin, or hidden as watched when that setting is on.
    static func isHidden(_ media: Media, options: Options, isWatched: (String) -> Bool) -> Bool {
        if originExcluded(media, excludeOrigins: options.excludeOrigins) { return true }
        return options.hideWatched && isWatched(media.id)
    }

    /// The titles a picks list may show, in their original order.
    static func filtered(_ items: [Media], options: Options, isWatched: (String) -> Bool) -> [Media] {
        items.filter { !isHidden($0, options: options, isWatched: isWatched) }
    }

    /// Desktop's hero front (`anime.tsx`, `heroSlides`): with hide-watched on, watched titles leave the front only
    /// while at least one unwatched title remains. Otherwise the list is returned unchanged.
    static func heroFront(_ items: [Media], options: Options, isWatched: (String) -> Bool) -> [Media] {
        guard options.hideWatched, items.contains(where: { !isWatched($0.id) }) else { return items }
        return items.filter { !isWatched($0.id) }
    }

    /// Desktop's `pageFor`: a page from 1 to 3, fixed for the UTC day and the seed key.
    static func dailyPage(seedKey: String, day: Int) -> Int {
        var generator = DiscoveryFeedRandom.generator(base: day, salt: seedKey)
        return 1 + Int(generator.next() * 3)
    }

    /// Desktop's taste input to `animeSeedGenres`: the genres with a positive weight, heaviest first, at most eight.
    static func tasteGenreNames(_ weights: [String: Double]) -> [String] {
        let positive = weights.filter { $0.value > 0 }
        let ranked = positive.sorted { first, second in
            first.value == second.value ? first.key < second.key : first.value > second.value
        }
        return ranked.prefix(8).map { $0.key }
    }

    /// The MAL id of a `mal:` title, or nil for any other provider.
    static func malID(_ id: String) -> Int? {
        guard id.hasPrefix("mal:") else { return nil }
        return Int(id.dropFirst(4))
    }

    /// Desktop's `anilistCountriesByMalIds` response: the two-letter country of each MAL id that AniList knows.
    static func countries(from media: [JSONValue]) -> [Int: String] {
        var out: [Int: String] = [:]
        for value in media {
            guard let mal = value["idMal"].integer, mal > 0, let code = value["countryOfOrigin"].string, code.count == 2 else { continue }
            out[mal] = code
        }
        return out
    }

    /// Sets the country of picks that lack one (Desktop's `enrichAnimeCountry`), so the origin setting can hide them.
    static func withCountries(_ items: [Media], countries: [Int: String]) -> [Media] {
        items.map { item in
            guard item.country == nil, let mal = malID(item.id), let code = countries[mal] else { return item }
            var copy = item
            copy.country = code
            return copy
        }
    }

    /// Desktop's `FRANCHISE_STRIP_RX`: each pattern removes the first match, in order (the last one is a year).
    private static let franchisePatterns: [(pattern: String, caseless: Bool)] = [
        (#"\s*[-:(]?\s*(?:1st|2nd|3rd|4th|5th|6th|7th|8th|9th|10th|11th|12th|First|Second|Third|Fourth|Fifth|Sixth|Seventh|Eighth|Ninth|Tenth|Final|Last)\s+(?:Season|Cour|Part|Chapter)\b.*$"#, true),
        (#"\s*[-:(]?\s*Season\s+\d+\b.*$"#, true),
        (#"\s*[-:(]?\s*S\d+(?:\s|\)|:|$).*"#, true),
        (#"\s*[-:(]?\s*(?:Part|Cour|Chapter)\s+\d+\b.*$"#, true),
        (#"\s*[-:(]?\s*(?:II|III|IV|V|VI|VII|VIII|IX|X)\b[)\s:-]*$"#, true),
        (#"\s+[-:(]*\s*(?:19|20)\d{2}[)\s:]*$"#, false),
    ]

    /// Desktop's `stripFranchiseSuffix`: the title without its season, part, numeral or year suffix.
    static func strippedName(_ name: String) -> String {
        var text = name
        for entry in franchisePatterns {
            var options: String.CompareOptions = .regularExpression
            if entry.caseless { options.insert(.caseInsensitive) }
            if let range = text.range(of: entry.pattern, options: options) { text.removeSubrange(range) }
        }
        if let range = text.range(of: #"[\s°'."’˚_:-]+$"#, options: .regularExpression) { text.removeSubrange(range) }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Desktop's `animeFranchiseKey`: the lowercased stripped name. Titles with the same key are one franchise.
    static func franchiseKey(_ name: String) -> String {
        strippedName(name).lowercased()
    }

    /// Desktop's `filteredRowsByKey`: a franchise is shown once per pool, and the hero and Top Picks claim theirs first.
    /// Each row is a pool name and its titles, in Desktop row order. Kept titles get the stripped name, as Desktop's `cleanMeta` does.
    static func pooledRows(_ rows: [(pool: String, metas: [Media])], seeds: [Media]) -> [[Media]] {
        let base = Set(seeds.map { franchiseKey($0.name) })
        var claimedByPool: [String: Set<String>] = [:]
        var out: [[Media]] = []
        for row in rows {
            var claimed = claimedByPool[row.pool] ?? base
            var kept: [Media] = []
            for media in row.metas {
                guard claimed.insert(franchiseKey(media.name)).inserted else { continue }
                var copy = media
                copy.name = strippedName(media.name)
                kept.append(copy)
            }
            claimedByPool[row.pool] = claimed
            out.append(kept)
        }
        return out
    }
}

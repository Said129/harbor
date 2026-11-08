import Foundation

/// The kind of query Desktop recognizes before searching (`SearchIntent` in `src/lib/search.ts`).
enum SearchQueryIntent: Equatable, Sendable {
    case year(Int)
    /// `isSeries` is true for a TV genre ("Sci-Fi & Fantasy shows") and false for a movie genre.
    case genre(name: String, isSeries: Bool)
}

/// A title that an anime source returned, as Desktop's `AnimeHit` keeps it for the anime merge.
struct AnimeSearchCandidate: Equatable, Sendable {
    /// The MyAnimeList id, or 0 when the source has none (Kitsu).
    let malId: Int
    let name: String
}

/// Desktop's pure search rules from `src/lib/search.ts`: the top match, the query intent, the key that
/// recognizes one title from two sources, and the anime merge with its cap.
enum SearchRanking {
    /// Desktop's `topRaw` and `topPop`: the index of the most popular title. A tie keeps the earlier title.
    static func topMatchIndex(popularities: [Double]) -> Int? {
        var best: Int?
        var bestValue = -1.0
        for (index, value) in popularities.enumerated() where value > bestValue {
            best = index
            bestValue = value
        }
        return best
    }

    /// Desktop's `detectIntent`: a year from 1900 to 2099, or a genre name with an optional "movies" or "shows" suffix.
    /// Movie genres are checked first, as Desktop does, so "Animation" is a movie genre.
    static func intent(
        _ query: String,
        movieGenres: [(String, Int)] = CustomCalendar.movieGenres,
        tvGenres: [(String, Int)] = CustomCalendar.tvGenres
    ) -> SearchQueryIntent? {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.range(of: "^(19|20)[0-9]{2}$", options: .regularExpression) != nil, let year = Int(text) {
            return .year(year)
        }
        let lower = text.lowercased()
        if let genre = movieGenres.first(where: { lower == $0.0.lowercased() || lower == $0.0.lowercased() + " movies" }) {
            return .genre(name: genre.0, isSeries: false)
        }
        if let genre = tvGenres.first(where: { lower == $0.0.lowercased() || lower == $0.0.lowercased() + " shows" }) {
            return .genre(name: genre.0, isSeries: true)
        }
        return nil
    }

    /// The keys that identify a title across sources: its IMDb id when it is known, and its normalized name with
    /// its type and year. Two titles are one title when they share any key, so a TMDB title without an IMDb id
    /// still matches the same title from an addon that has one.
    static func identityKeys(for media: Media) -> [String] {
        var keys: [String] = []
        let imdb = (media.imdbID ?? media.id).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if imdb.range(of: "^tt[0-9]{7,}$", options: .regularExpression) != nil {
            keys.append("imdb:" + imdb)
        }
        let title = normalizedName(media.name)
        if !title.isEmpty {
            let year = String((media.releaseInfo ?? media.released ?? "").prefix(4))
            keys.append("title:\(media.type):\(title):\(year)")
        }
        return keys
    }

    /// Lowercase letters and digits only, with accents removed.
    static func normalizedName(_ name: String) -> String {
        name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en"))
            .replacingOccurrences(of: "[^a-z0-9]+", with: "", options: .regularExpression)
    }

    /// The items that do not repeat a title of `existing` or of an earlier item, in their order.
    static func dropDuplicates(_ items: [Media], against existing: [Media]) -> [Media] {
        var taken = Set(existing.flatMap { identityKeys(for: $0) })
        var output: [Media] = []
        for item in items {
            let keys = identityKeys(for: item)
            if keys.contains(where: { taken.contains($0) }) { continue }
            taken.formUnion(keys)
            output.append(item)
        }
        return output
    }

    /// Desktop's `searchAnime`: the sources in their order (AniList, Jikan, Kitsu). A title with no name or named
    /// "Untitled" is left out, a repeated MAL id or name is skipped, and at most `limit` titles are kept.
    static func mergeAnime(_ sources: [[AnimeSearchCandidate]], limit: Int = 8) -> [AnimeSearchCandidate] {
        var output: [AnimeSearchCandidate] = []
        var seenMal = Set<Int>()
        var seenName = Set<String>()
        for candidate in sources.flatMap({ $0 }) {
            let key = candidate.name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            if key.isEmpty || key == "untitled" { continue }
            if candidate.malId != 0 && seenMal.contains(candidate.malId) { continue }
            if seenName.contains(key) { continue }
            if candidate.malId != 0 { seenMal.insert(candidate.malId) }
            seenName.insert(key)
            output.append(candidate)
        }
        return Array(output.prefix(limit))
    }
}

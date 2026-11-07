import Foundation

/// The score chips printed on a poster, in Desktop's push order (`components/pick-card.tsx`, cardBadges).
/// IMDb, TMDB and MAL share the first chip; the rest are one chip each.
enum CardRatingProvider: String, CaseIterable, Sendable {
    case imdb, tmdb, mal, simkl, rt, audience, metacritic, letterboxd, mdblist, trakt
}

/// The keys that gate card chips (Desktop's `cards-tab.tsx`): OMDb for Rotten Tomatoes, MDBList for the rest.
enum CardRatingKey: String, CaseIterable, Sendable {
    case omdb, mdblist
}

/// Which sources a poster needs a fetch for.
struct CardRatingNeeds: OptionSet, Sendable, Hashable {
    let rawValue: Int
    static let omdb = CardRatingNeeds(rawValue: 1)
    static let mdblist = CardRatingNeeds(rawValue: 2)
    static let simkl = CardRatingNeeds(rawValue: 4)
}

/// The raw answers for one title. Chips are worked out from these when the card draws.
struct CardRatingScores: Equatable, Sendable {
    var omdb: OmdbScores?
    var mdblist: MdblistScores?
    var simkl: Double?
}

struct CardRatingChip: Equatable, Sendable {
    let provider: CardRatingProvider
    let text: String
}

/// The pure rules for card chips: which providers show, in what order, how many, and what they read.
enum CardRatingPolicy {
    /// Desktop's `cards-tab.tsx` gating: Rotten Tomatoes needs OMDb, the MDBList scores need MDBList.
    /// IMDb, TMDB, MAL and SIMKL need no key.
    static func requiredKey(_ provider: CardRatingProvider) -> CardRatingKey? {
        switch provider {
        case .rt: return .omdb
        case .audience, .metacritic, .letterboxd, .mdblist, .trakt: return .mdblist
        case .imdb, .tmdb, .mal, .simkl: return nil
        }
    }

    /// The Desktop message shown under a score whose key is missing, or nil when the score can be used.
    static func missingKeyHint(_ provider: CardRatingProvider, keys: Set<CardRatingKey>) -> String? {
        guard let required = requiredKey(provider), !keys.contains(required) else { return nil }
        return required == .omdb ? "Cards need an OMDb key." : "Cards need an MDBList key."
    }

    static func keySources(omdb: String, mdblist: String) -> Set<CardRatingKey> {
        var found: Set<CardRatingKey> = []
        if !omdb.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { found.insert(.omdb) }
        if !mdblist.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { found.insert(.mdblist) }
        return found
    }

    /// The selected providers that have their key, in Desktop's push order.
    static func enabled(selected: Set<CardRatingProvider>, keys: Set<CardRatingKey>) -> [CardRatingProvider] {
        CardRatingProvider.allCases.filter { provider in
            selected.contains(provider) && isUsable(provider, keys: keys)
        }
    }

    private static func isUsable(_ provider: CardRatingProvider, keys: Set<CardRatingKey>) -> Bool {
        guard let required = requiredKey(provider) else { return true }
        return keys.contains(required)
    }

    private static func isPrimary(_ provider: CardRatingProvider) -> Bool {
        provider == .imdb || provider == .tmdb || provider == .mal
    }

    /// Desktop's enabled count in the settings: IMDb, TMDB and MAL take one slot between them.
    static func chipCount(_ enabled: [CardRatingProvider]) -> Int {
        let primary = enabled.contains(where: isPrimary) ? 1 : 0
        return primary + enabled.filter { !isPrimary($0) }.count
    }

    /// Desktop's `cardBadgeLimit` after the enabled count changes: a rise past the limit lifts it to the count, up to 6.
    static func limitAfterEnabling(previous: Int, current: Int, limit: Int) -> Int {
        current > previous && current > limit ? min(6, current) : limit
    }

    /// The most chips a card shows (Desktop's `ScoreStack`: at least one).
    static func visibleLimit(_ limit: Int) -> Int { max(1, limit) }

    static func imdbID(_ media: Media) -> String? {
        [media.id, media.imdbID ?? ""].first { $0.range(of: "^tt[0-9]+$", options: .regularExpression) != nil }
    }

    /// The sources a card has to ask for. An anime card reads only its catalog score, and a title without an IMDb id asks nothing.
    static func needs(anime: Bool, enabled: [CardRatingProvider], inlineRating: String?, inlineSource: String?) -> CardRatingNeeds {
        if anime { return [] }
        var result: CardRatingNeeds = []
        let imdbFromOMDb = inlineSource == "TMDB" || (inlineRating ?? "").isEmpty
        if enabled.contains(.rt) || (enabled.contains(.imdb) && imdbFromOMDb) { result.insert(.omdb) }
        let mdblistProviders: [CardRatingProvider] = [.audience, .metacritic, .letterboxd, .mdblist, .trakt]
        if enabled.contains(where: { mdblistProviders.contains($0) }) { result.insert(.mdblist) }
        if enabled.contains(.simkl) { result.insert(.simkl) }
        return result
    }

    /// The chips for one card: the enabled providers that have a value, in order, cut to the limit.
    static func chips(anime: Bool, inlineRating: String?, inlineSource: String?, scores: CardRatingScores, enabled: [CardRatingProvider], limit: Int) -> [CardRatingChip] {
        var result: [CardRatingChip] = []
        for provider in enabled {
            guard let value = text(provider, anime: anime, inlineRating: inlineRating, inlineSource: inlineSource, scores: scores) else { continue }
            result.append(CardRatingChip(provider: provider, text: value))
        }
        return Array(result.prefix(visibleLimit(limit)))
    }

    /// The text Desktop's `BadgeContent` prints for each provider.
    static func text(_ provider: CardRatingProvider, anime: Bool, inlineRating: String?, inlineSource: String?, scores: CardRatingScores) -> String? {
        if anime { return provider == .mal ? nonEmpty(inlineRating) : nil }
        switch provider {
        case .imdb:
            if inlineSource == "TMDB" { return scores.omdb.flatMap { $0.imdbRating } }
            return nonEmpty(inlineRating) ?? scores.omdb.flatMap { $0.imdbRating }
        case .tmdb:
            return inlineSource == "TMDB" ? nonEmpty(inlineRating) : nil
        case .mal:
            return nil
        case .simkl:
            return scores.simkl.map { String(DetailRatings.rounded($0)) }
        case .rt:
            return scores.omdb.flatMap { $0.rtCritics }.map { "\($0)%" }
        case .audience:
            return scores.mdblist.flatMap { $0.rtAudience }.map { "\(DetailRatings.rounded($0))%" }
        case .metacritic:
            return scores.mdblist.flatMap { $0.metacritic }.map { String(DetailRatings.rounded($0)) }
        case .letterboxd:
            return scores.mdblist.flatMap { $0.letterboxd }.map { String(format: "%.1f", $0 / 2) }
        case .mdblist:
            return scores.mdblist.flatMap { $0.score }.map { String(DetailRatings.rounded($0)) }
        case .trakt:
            return scores.mdblist.flatMap { $0.trakt }.map { "\(DetailRatings.rounded($0))%" }
        }
    }

    private static func nonEmpty(_ text: String?) -> String? {
        guard let text, !text.isEmpty else { return nil }
        return text
    }
}

/// The per-title score cache shared by every poster (Desktop's `useOmdbScores`, `useMdblistCardScores`, `useSimklCardScores`).
/// OMDb keeps its own budget and prefetch rule; a title is asked once per source and key set.
actor CardRatings {
    static let shared = CardRatings()
    /// Stops a long session from growing without bound; the services keep their own caches too.
    static let cacheLimit = 2_000

    private struct Entry {
        var tag = ""
        var fetched = CardRatingNeeds()
        var scores = CardRatingScores()
    }
    private var entries: [String: Entry] = [:]

    /// OMDb is asked on every request through `prefetch` and then read back from its cache, so the daily budget stops at
    /// 90 percent, a recent miss is not repeated, and a title another row just fetched is picked up. MDBList and SIMKL
    /// count as fetched only once they return a value; their services already remember misses and failures.
    /// A missing key asks nothing.
    func scores(imdbID: String, omdbKey: String, mdblistKey: String, show: Bool, needs: CardRatingNeeds) async -> CardRatingScores {
        let tag = "\(omdbKey.hashValue)|\(mdblistKey.hashValue)"
        if entries[imdbID]?.tag != tag {
            if entries.count >= Self.cacheLimit { entries.removeAll() }
            entries[imdbID] = Entry(tag: tag)
        }
        let already = entries[imdbID]?.fetched ?? CardRatingNeeds()
        let missing = needs.subtracting(already)
        if needs.contains(.omdb), !omdbKey.isEmpty {
            await OmdbService.shared.prefetch(key: omdbKey, imdbID: imdbID)
            let value = await OmdbService.shared.cached(imdbID)
            update(imdbID) { entry in
                entry.scores.omdb = value
            }
        }
        if missing.contains(.mdblist), !mdblistKey.isEmpty {
            let value = await MdblistService.shared.scores(key: mdblistKey, imdbID: imdbID, type: show ? "show" : "movie")
            if let value {
                update(imdbID) { entry in
                    entry.scores.mdblist = value
                    entry.fetched.insert(.mdblist)
                }
            }
        }
        if missing.contains(.simkl) {
            let value = await SimklCommunityRatings.shared.rating("imdb:" + imdbID)
            if let value {
                update(imdbID) { entry in
                    entry.scores.simkl = value
                    entry.fetched.insert(.simkl)
                }
            }
        }
        return entries[imdbID]?.scores ?? CardRatingScores()
    }

    private func update(_ imdbID: String, _ change: (inout Entry) -> Void) {
        var entry = entries[imdbID] ?? Entry()
        change(&entry)
        entries[imdbID] = entry
    }
}

extension InterfacePreferences {
    /// Desktop's card switches (`showRtBadge` and so on) for each provider.
    func cardRatingOn(_ provider: CardRatingProvider) -> Bool {
        switch provider {
        case .imdb: showImdbBadge
        case .tmdb: showTmdbBadge
        case .mal: showMalBadge
        case .simkl: showSimklBadge
        case .rt: showRtBadge
        case .audience: showPopcornBadge
        case .metacritic: showMetacriticBadge
        case .letterboxd: showLetterboxdBadge
        case .mdblist: showMdblistBadge
        case .trakt: showTraktBadge
        }
    }

    func setCardRating(_ provider: CardRatingProvider, _ on: Bool) {
        switch provider {
        case .imdb: showImdbBadge = on
        case .tmdb: showTmdbBadge = on
        case .mal: showMalBadge = on
        case .simkl: showSimklBadge = on
        case .rt: showRtBadge = on
        case .audience: showPopcornBadge = on
        case .metacritic: showMetacriticBadge = on
        case .letterboxd: showLetterboxdBadge = on
        case .mdblist: showMdblistBadge = on
        case .trakt: showTraktBadge = on
        }
    }
}

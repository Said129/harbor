import Foundation

// Desktop's Critics Pick: `src/lib/feed/sections.ts` (fetchCriticsPickList), the `criticsPick` memo in
// `src/views/discover.tsx`, `src/components/critics-pick.tsx` and `src/lib/providers/tmdb/tmdb-critic.ts`.
// The pick does not depend on any score. Desktop chooses by day, and OMDb only adds the Rotten Tomatoes and
// Metacritic numbers printed on the card.

/// One TMDB review kept for the card (Desktop's `CriticReview`).
struct CriticsPickReview: Equatable, Sendable {
    let author: String
    let rating: Double?
    let content: String
    let url: String?
}

/// What the card reads from TMDB for one title: tagline, overview, reviews and the IMDb id for OMDb.
/// Cast, crew and stills are not read on iOS.
struct CriticsPickDetails: Equatable, Sendable {
    var tagline: String?
    var overview: String?
    var reviews: [CriticsPickReview] = []
    var imdbID: String?

    /// Desktop's `tmdbCriticData`: reviews of at least 120 characters, one per author, six at most, best rated first.
    static func parse(_ json: JSONValue) -> CriticsPickDetails {
        var details = CriticsPickDetails()
        details.tagline = CriticsPickRules.trimmed(json["tagline"].string)
        details.overview = CriticsPickRules.trimmed(json["overview"].string)
        let imdb = CriticsPickRules.trimmed(json["external_ids"]["imdb_id"].string ?? json["imdb_id"].string)
        if let imdb, imdb.range(of: "^tt[0-9]+$", options: .regularExpression) != nil { details.imdbID = imdb }
        var seen = Set<String>()
        var reviews: [CriticsPickReview] = []
        for row in json["reviews"]["results"].array {
            if reviews.count >= 6 { break }
            let content = (row["content"].string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard content.count >= 120 else { continue }
            let username = row["author_details"]["username"].string ?? ""
            let name = username.isEmpty ? (row["author"].string ?? "") : username
            let author = name.isEmpty ? "Anonymous" : name
            guard seen.insert(author.lowercased()).inserted else { continue }
            reviews.append(CriticsPickReview(author: author, rating: row["author_details"]["rating"].numericValue, content: content, url: row["url"].string))
        }
        details.reviews = reviews.enumerated().sorted { left, right in
            let a = left.element.rating ?? 0
            let b = right.element.rating ?? 0
            return a == b ? left.offset < right.offset : a > b
        }.map(\.element)
        return details
    }
}

/// The OMDb numbers one card shows. Rotten Tomatoes is left out when Desktop's `showRtBadge` setting is off.
struct CriticsPickScores: Equatable, Sendable {
    var rottenTomatoes: Int?
    var metascore: Int?
    var imdbRating: String?

    static func from(_ omdb: OmdbScores?, showRottenTomatoes: Bool) -> CriticsPickScores {
        CriticsPickScores(rottenTomatoes: showRottenTomatoes ? omdb?.rtCritics : nil, metascore: omdb?.metascore, imdbRating: omdb?.imdbRating)
    }
}

enum CriticsPickRules {
    /// One of Desktop's four discover queries. `offset` shifts the page so the four lists do not repeat each other.
    struct Source: Equatable, Sendable {
        let id: String
        let parameters: [String: String]
        let offset: Int
    }

    /// Desktop's `fetchCriticsPickList` filters, in the same order.
    static let sources: [Source] = [
        Source(id: "critics-pick-acclaimed", parameters: ["vote_average.gte": "8.0", "vote_count.gte": "5000", "sort_by": "vote_average.desc"], offset: 0),
        Source(id: "critics-pick-recent", parameters: ["vote_average.gte": "7.6", "vote_count.gte": "1500", "primary_release_date.gte": "2018-01-01", "sort_by": "vote_average.desc"], offset: 1),
        Source(id: "critics-pick-popular", parameters: ["vote_average.gte": "7.5", "vote_count.gte": "1200", "sort_by": "vote_count.desc"], offset: 2),
        Source(id: "critics-pick-classic", parameters: ["vote_average.gte": "7.5", "vote_count.gte": "800", "primary_release_date.lte": "1999-12-31", "sort_by": "vote_average.desc"], offset: 3)
    ]

    /// Whole days since the local midnight that starts the day before January 1 of the UTC year (Desktop's `dayOfYear`).
    static func dayOfYear(now: Date, timeZone: TimeZone = .current) -> Int {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC") ?? .current
        let year = utc.component(.year, from: now)
        var local = Calendar(identifier: .gregorian)
        local.timeZone = timeZone
        guard let january = local.date(from: DateComponents(year: year, month: 1, day: 1)),
              let start = local.date(byAdding: .day, value: -1, to: january) else { return 0 }
        return max(0, Int(floor(now.timeIntervalSince(start) / 86_400)))
    }

    /// Desktop's `pageOf`: pages 1 to 5, moved by the day and the source.
    static func page(_ source: Source, dayOfYear: Int) -> Int {
        ((dayOfYear + source.offset) % 5) + 1
    }

    static func rail(_ source: Source, locale: DiscoveryAffinityRules.LocaleBias = .disabled, region: String = "") -> DiscoveryRail {
        let floor = DiscoveryDailyFeed.localizeFloor(source.parameters, kind: "movie", enabled: locale.penalty > 0,
                                                      localeCodes: locale.codes, region: region)
        return DiscoveryRail(id: source.id, title: "Critics' Pick", kind: "movie", path: "discover/movie", parameters: floor)
    }

    /// Desktop's merge: the lists are read in turn, a title once, in the order it first appears.
    static func merge(_ lists: [[Media]]) -> [Media] {
        var seen = Set<String>()
        var merged: [Media] = []
        let longest = lists.map(\.count).max() ?? 0
        for index in 0..<longest {
            for list in lists where index < list.count {
                let media = list[index]
                guard seen.insert(media.id).inserted else { continue }
                merged.append(media)
            }
        }
        return merged
    }

    /// Desktop's `criticsPick` memo: titles with artwork and a description first, one chosen by the day.
    /// Titles in Featured are skipped, and when no title has both, the first one left is used.
    /// `excludedTitleKeys` are watched titles by `titleKey`, since TMDB and library ids rarely match.
    static func pick(from list: [Media], excludedIDs: Set<String>, featuredIDs: Set<String>, excludedTitleKeys: Set<String> = [], dayOfYear: Int) -> Media? {
        let available = list.filter { media in
            !excludedIDs.contains(media.id) && !featuredIDs.contains(media.id) && !excludedTitleKeys.contains(titleKey(media.name))
        }
        let candidates = available.filter { !(trimmed($0.background) ?? "").isEmpty && !(trimmed($0.description) ?? "").isEmpty }
        if candidates.isEmpty { return available.first }
        return candidates[max(0, dayOfYear) % candidates.count]
    }

    /// Desktop's `excerptReview`: a review of up to 320 characters, cut at a sentence end past the middle or else at a word.
    static func excerpt(_ content: String) -> String {
        let text = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count > 320 else { return text }
        let cutoff = String(text.prefix(320))
        if let sentence = cutoff.range(of: ". ", options: .backwards) {
            let index = cutoff.distance(from: cutoff.startIndex, to: sentence.lowerBound)
            if index > 160 { return String(text.prefix(index + 1)) }
        }
        var wordEnd = 320
        if let space = cutoff.range(of: " ", options: .backwards) {
            let index = cutoff.distance(from: cutoff.startIndex, to: space.lowerBound)
            if index > 0 { wordEnd = index }
        }
        return String(text.prefix(wordEnd)) + "…"
    }

    /// Desktop's `overview.split(/(?<=[.!?])\s+/)[0]`: the text up to the first sentence end.
    static func firstSentence(_ text: String) -> String {
        guard let end = text.range(of: "[.!?]\\s", options: .regularExpression) else { return text }
        return String(text[...end.lowerBound])
    }

    /// The italic line on the card: the shown review, else the tagline, else the first sentence of the overview.
    static func quote(review: CriticsPickReview?, tagline: String?, overview: String?, fallback: String) -> String {
        if let review { return excerpt(review.content) }
        if let tagline = trimmed(tagline) { return tagline }
        if let overview = trimmed(overview) { return firstSentence(overview) }
        return fallback
    }

    /// The TMDB detail path for a `tmdb:movie:ID` id, or nil for anything else.
    static func detailPath(_ media: Media) -> String? {
        let prefix = "tmdb:movie:"
        guard media.id.hasPrefix(prefix) else { return nil }
        let number = String(media.id.dropFirst(prefix.count))
        guard !number.isEmpty, number.allSatisfy(\.isNumber) else { return nil }
        return "movie/" + number
    }

    static func detailURL(path: String, key: String, language: String) -> String? {
        guard var parts = URLComponents(string: "https://api.themoviedb.org/3/" + path) else { return nil }
        parts.queryItems = [
            URLQueryItem(name: "api_key", value: key),
            URLQueryItem(name: "language", value: language),
            URLQueryItem(name: "append_to_response", value: "reviews,external_ids")
        ]
        return parts.url?.absoluteString
    }

    static func trimmed(_ text: String?) -> String? {
        guard let value = text?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return value
    }

    /// Desktop's `watchTitleKey`: lower case, no "(1995)"-style year, and only a to z and 0 to 9 kept.
    static func titleKey(_ name: String?) -> String {
        guard let name, !name.isEmpty else { return "" }
        let lower = name.lowercased().replacingOccurrences(of: "\\(\\d{4}\\)", with: "", options: .regularExpression)
        var key = ""
        for scalar in lower.unicodeScalars where (scalar.value >= 97 && scalar.value <= 122) || (scalar.value >= 48 && scalar.value <= 57) {
            key.unicodeScalars.append(scalar)
        }
        return key
    }
}

/// The network behind the pick. Every call is a closure, so tests run without the network.
struct CriticsPickService: Sendable {
    typealias Discover = @Sendable (DiscoveryRail, Int, MetadataConfiguration) async throws -> [Media]
    typealias JSONLoader = @Sendable (String) async throws -> JSONValue
    typealias Scores = @Sendable (String, String) async -> OmdbScores?

    let discover: Discover
    let json: JSONLoader
    /// Desktop's `omdbScores` through `OmdbService`, which keeps the day's budget and the cache.
    let scores: Scores

    init(discover: @escaping Discover = { rail, page, configuration in
            try await TMDBService().page(rail, page: page, configuration: configuration, includeRegion: false)
         },
         json: @escaping JSONLoader = { url in
            try await HTTPClient().json(url, timeout: 15, credentialed: true)
         },
         scores: @escaping Scores = { key, imdbID in
            // Desktop's card only reads the OMDb cache. The fetch is the prefetch other cards and the hero already do.
            await OmdbService.shared.prefetch(key: key, imdbID: imdbID, type: "movie")
            return await OmdbService.shared.cached(imdbID)
         }) {
        self.discover = discover; self.json = json; self.scores = scores
    }

    /// The four Desktop queries, read at once. A query that fails contributes nothing (Desktop would drop the whole list).
    func candidates(dayOfYear: Int, configuration: MetadataConfiguration, locale: DiscoveryAffinityRules.LocaleBias = .disabled) async -> [Media] {
        guard !configuration.tmdbKey.isEmpty else { return [] }
        let sources = CriticsPickRules.sources
        let discover = self.discover
        var lists = [[Media]](repeating: [], count: sources.count)
        await withTaskGroup(of: (Int, [Media]).self) { group in
            for (index, source) in sources.enumerated() {
                let rail = CriticsPickRules.rail(source, locale: locale, region: configuration.region)
                let page = CriticsPickRules.page(source, dayOfYear: dayOfYear)
                group.addTask {
                    let found = (try? await discover(rail, page, configuration)) ?? []
                    return (index, found)
                }
            }
            for await (index, found) in group { lists[index] = found }
        }
        return CriticsPickRules.merge(lists)
    }

    /// TMDB reviews, tagline and overview for one title, kept for the session.
    func details(for media: Media, configuration: MetadataConfiguration) async -> CriticsPickDetails? {
        let cacheID = media.id + "|" + configuration.language
        if let saved = await CriticsPickCache.shared.details(cacheID) { return saved }
        guard let path = CriticsPickRules.detailPath(media),
              let url = CriticsPickRules.detailURL(path: path, key: configuration.tmdbKey, language: configuration.language),
              let value = try? await json(url) else { return nil }
        let parsed = CriticsPickDetails.parse(value)
        await CriticsPickCache.shared.store(cacheID, parsed)
        return parsed
    }

    /// OMDb scores for the IMDb id of a title. No key or no id asks nothing.
    func omdbScores(for details: CriticsPickDetails, key: String) async -> OmdbScores? {
        let apiKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty, let imdb = details.imdbID else { return nil }
        return await scores(apiKey, imdb)
    }
}

/// Recent TMDB details per title. Full when it reaches its limit, which keeps a long session bounded.
actor CriticsPickCache {
    static let shared = CriticsPickCache()
    static let limit = 400
    private var values: [String: CriticsPickDetails] = [:]

    func details(_ id: String) -> CriticsPickDetails? { values[id] }

    func store(_ id: String, _ details: CriticsPickDetails) {
        if values.count >= Self.limit { values.removeAll() }
        values[id] = details
    }
}

import Foundation

/// IMDb's rating of each episode of a series, read from the Harbor community server (Desktop's `harborImdbEpisodes`
/// in `lib/providers/harbor-imdb.ts`). Keys are "season:episode". A failed read is remembered for a minute, a good
/// one for an hour, so a short outage does not pin missing ratings.
actor HarborEpisodeRatings {
    static let shared = HarborEpisodeRatings()
    static let lifetime: TimeInterval = 60 * 60
    static let emptyLifetime: TimeInterval = 60
    static let cacheLimit = 200
    typealias Fetch = @Sendable (URL) async throws -> JSONValue

    private struct Entry { let ratings: [String: Double]; let expires: Date }
    private let fetch: Fetch
    private var cache: [String: Entry] = [:]
    private var inflight: [String: Task<[String: Double], Never>] = [:]

    init(fetch: @escaping Fetch = { try await HTTPClient().json($0.absoluteString, timeout: 15) }) { self.fetch = fetch }

    static func url(_ seriesID: String) -> URL? {
        guard seriesID.range(of: "^tt[0-9]+$", options: .regularExpression) != nil else { return nil }
        return URL(string: "https://harborcommunity.site/api/imdb/episodes/\(seriesID)")
    }

    func ratings(_ seriesID: String, now: Date = Date()) async -> [String: Double] {
        guard let url = Self.url(seriesID) else { return [:] }
        if let hit = cache[seriesID] { if now < hit.expires { return hit.ratings }; cache[seriesID] = nil }
        if let pending = inflight[seriesID] { return await pending.value }
        let load = fetch
        let task = Task<[String: Double], Never> {
            guard let data = try? await load(url) else { return [:] }
            var map: [String: Double] = [:]
            for (key, raw) in data["ratings"].objectValue {
                if let value = raw.numericValue ?? raw.string.flatMap({ Double($0) }), value.isFinite, value > 0 { map[key] = value }
            }
            return map
        }
        inflight[seriesID] = task
        let map = await task.value
        inflight[seriesID] = nil
        if cache.count >= Self.cacheLimit, let oldest = cache.min(by: { $0.value.expires < $1.value.expires })?.key { cache[oldest] = nil }
        cache[seriesID] = Entry(ratings: map, expires: now.addingTimeInterval(map.isEmpty ? Self.emptyLifetime : Self.lifetime))
        return map
    }
}

/// Desktop's episode rating rules (`use-episode-enrich.ts`, `series-episode-row.tsx`).
enum EpisodeRatings {
    /// The key an episode has in IMDb's numbering: its IMDb coordinates when the source gives them, else its own.
    static func key(_ episode: Episode) -> String { "\(episode.imdbSeason ?? episode.season ?? 0):\(episode.imdbEpisode ?? episode.episode ?? 0)" }

    /// The community's ratings with OMDb's season ratings filling what it lacks; the community's rating wins.
    static func merged(community: [String: Double], seasons: [Int: [Int: Double]]) -> [String: Double] {
        var merged = community
        for (season, episodes) in seasons {
            for (number, rating) in episodes where merged["\(season):\(number)"] == nil { merged["\(season):\(number)"] = rating }
        }
        return merged
    }

    /// The rating to print on an episode, or nil to print none: a zero or missing rating shows nothing.
    static func rating(for episode: Episode, in ratings: [String: Double]) -> Double? {
        guard let value = ratings[key(episode)], value > 0 else { return nil }
        return value
    }

    /// Desktop's `value.toFixed(1)`.
    static func label(_ value: Double) -> String { String(format: "%.1f", value) }

    /// The seasons OMDb is asked about: each IMDb season of the shown episodes, from 1 up.
    static func seasons(of episodes: [Episode]) -> [Int] {
        Array(Set(episodes.compactMap { $0.imdbSeason ?? $0.season }.filter { $0 >= 1 })).sorted()
    }
}

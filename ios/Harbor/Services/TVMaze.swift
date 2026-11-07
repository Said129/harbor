import Foundation

/// A TVMaze show found by IMDb or TVDB id (Desktop's `TvmazeShow` in `src/lib/providers/tvmaze.ts`).
struct TVMazeShow: Equatable, Sendable {
    let id: Int
    let name: String
    let image: String?
    let isAnime: Bool
}

/// One dated TVMaze episode (Desktop's `TvmazeEpisode`). Episodes without an airdate are not kept.
struct TVMazeEpisode: Equatable, Sendable {
    let season: Int
    let number: Int
    let name: String
    /// TVMaze's airdate, yyyy-MM-dd, on the network's day.
    let airdate: String
    /// TVMaze's `airstamp` in milliseconds since 1970. Desktop never reads it; Harbor uses it for the hour only.
    let airstampMs: Double?
    let image: String?
    let summary: String
}

/// An episode's day and, when TVMaze gives an airstamp, its hour. The day and hour are in the device's time zone.
struct TVMazeAirtime: Equatable, Sendable {
    let date: String
    let time: String?
    let atMs: Double?
}

/// The network call behind the client: the JSON at a URL, or nil when the request fails or is not a success.
protocol TVMazeTransport: Sendable {
    func json(_ url: URL) async -> JSONValue?
}

struct TVMazeHTTPTransport: TVMazeTransport {
    func json(_ url: URL) async -> JSONValue? {
        try? await HTTPClient().json(url.absoluteString, timeout: 15)
    }
}

/// Desktop's TVMaze rules as pure functions: URLs, parsing and the airtime of one episode.
enum TVMazeRules {
    static let base = "https://api.tvmaze.com"
    /// Desktop's `EP_TTL_MS`: an episode list is reused for six hours.
    static let episodeTTL: TimeInterval = 6 * 60 * 60

    static func lookupURL(imdb: String) -> URL? {
        lookup([URLQueryItem(name: "imdb", value: imdb)])
    }

    /// The TVDB id lookup Trakt rows carry; Desktop only looks up by IMDb.
    static func lookupURL(tvdb: Int) -> URL? {
        lookup([URLQueryItem(name: "thetvdb", value: String(tvdb))])
    }

    private static func lookup(_ items: [URLQueryItem]) -> URL? {
        var parts = URLComponents(string: base + "/lookup/shows")
        parts?.queryItems = items
        return parts?.url
    }

    static func episodesURL(showID: Int) -> URL? {
        URL(string: "\(base)/shows/\(showID)/episodes")
    }

    /// Desktop's `tvmazeShow` mapping: the id is required; the image prefers the original size; anime is a genre.
    static func show(_ json: JSONValue) -> TVMazeShow? {
        guard let id = json["id"].integer else { return nil }
        let genres = json["genres"].array.compactMap { $0.string }
        let image = json["image"]["original"].string ?? json["image"]["medium"].string
        let isAnime = genres.contains { $0.lowercased() == "anime" }
        return TVMazeShow(id: id, name: json["name"].string ?? "", image: image, isAnime: isAnime)
    }

    /// Desktop's `tvmazeEpisodes` mapping: rows without an airdate are dropped and the summary loses its tags.
    static func episodes(_ json: JSONValue) -> [TVMazeEpisode] {
        json.array.compactMap { row -> TVMazeEpisode? in
            guard let airdate = row["airdate"].string, !airdate.isEmpty else { return nil }
            let image = row["image"]["original"].string ?? row["image"]["medium"].string
            return TVMazeEpisode(season: row["season"].integer ?? 0, number: row["number"].integer ?? 0, name: row["name"].string ?? "",
                                 airdate: String(airdate.prefix(10)), airstampMs: instantMs(row["airstamp"].string),
                                 image: image, summary: stripTags(row["summary"].string))
        }
    }

    /// Desktop's `stripHtml`: tags are removed and the rest is trimmed.
    static func stripTags(_ text: String?) -> String {
        (text ?? "").replacingOccurrences(of: "<[^>]*>", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func instantMs(_ text: String?) -> Double? {
        guard let text, let date = CalendarTime.instant(text) else { return nil }
        return date.timeIntervalSince1970 * 1_000
    }

    static func episode(_ episodes: [TVMazeEpisode], season: Int, number: Int) -> TVMazeEpisode? {
        episodes.first { $0.season == season && $0.number == number }
    }

    /// The airtime the calendar can show. With an airstamp, the day and hour are the device's, the same rule as
    /// `CalendarTime.parse` for Trakt and Cinemeta. Without one, the network's airdate stands (Desktop's only rule).
    static func airtime(_ episode: TVMazeEpisode, calendar: Calendar = .current) -> TVMazeAirtime {
        guard let ms = episode.airstampMs else { return TVMazeAirtime(date: episode.airdate, time: nil, atMs: nil) }
        let date = Date(timeIntervalSince1970: ms / 1_000)
        return TVMazeAirtime(date: CalendarTime.dateString(date, calendar: calendar), time: CalendarTime.timeLabel(date, calendar: calendar), atMs: ms)
    }
}

/// Desktop's TVMaze caches, as an actor: one lookup per IMDb id and one episode list per show, with concurrent callers
/// sharing a request. A failed refresh answers the last good list. Misses are not kept, as on Desktop.
actor TVMazeService {
    static let shared = TVMazeService(transport: TVMazeHTTPTransport())

    private let transport: any TVMazeTransport
    private var showCache: [String: TVMazeShow] = [:]
    private var showTasks: [String: Task<TVMazeShow?, Never>] = [:]
    private var episodeCache: [Int: (at: Date, episodes: [TVMazeEpisode])] = [:]
    private var episodeTasks: [Int: Task<[TVMazeEpisode]?, Never>] = [:]

    init(transport: any TVMazeTransport) {
        self.transport = transport
    }

    /// Desktop's `tvmazeShow`, by IMDb id.
    func lookupShow(imdb: String) async -> TVMazeShow? {
        await cachedShow(key: imdb, url: TVMazeRules.lookupURL(imdb: imdb))
    }

    /// The same lookup by TVDB id, for the Trakt rows that carry one.
    func lookupShow(tvdb: Int) async -> TVMazeShow? {
        await cachedShow(key: "tvdb:\(tvdb)", url: TVMazeRules.lookupURL(tvdb: tvdb))
    }

    private func cachedShow(key: String, url: URL?) async -> TVMazeShow? {
        if let cached = showCache[key] { return cached }
        if let task = showTasks[key] { return await task.value }
        guard let url else { return nil }
        let transport = self.transport
        let task = Task<TVMazeShow?, Never> { () -> TVMazeShow? in
            guard let value = await transport.json(url) else { return nil }
            return TVMazeRules.show(value)
        }
        showTasks[key] = task
        let found = await task.value
        showTasks[key] = nil
        if let found { showCache[key] = found }
        return found
    }

    /// Desktop's `tvmazeEpisodes`: reused for six hours; a failed refresh answers the stale list, or nothing.
    func episodes(showID: Int, now: Date = Date()) async -> [TVMazeEpisode] {
        let cached = episodeCache[showID]
        if let cached, now.timeIntervalSince(cached.at) < TVMazeRules.episodeTTL { return cached.episodes }
        if let task = episodeTasks[showID] {
            return (await task.value) ?? (cached?.episodes ?? [])
        }
        guard let url = TVMazeRules.episodesURL(showID: showID) else { return cached?.episodes ?? [] }
        let transport = self.transport
        let task = Task<[TVMazeEpisode]?, Never> { () -> [TVMazeEpisode]? in
            guard let value = await transport.json(url) else { return nil }
            return TVMazeRules.episodes(value)
        }
        episodeTasks[showID] = task
        let fetched = await task.value
        episodeTasks[showID] = nil
        guard let fetched else { return cached?.episodes ?? [] }
        episodeCache[showID] = (now, fetched)
        return fetched
    }

    /// Desktop's `tvmazeUpcoming`: the show and its episodes whose airdate passes `inWindow`.
    func upcoming(imdb: String, inWindow: @Sendable (String) -> Bool, now: Date = Date()) async -> (show: TVMazeShow, episodes: [TVMazeEpisode])? {
        guard let show = await lookupShow(imdb: imdb) else { return nil }
        let all = await episodes(showID: show.id, now: now)
        return (show, all.filter { inWindow($0.airdate) })
    }

    /// The calendar's hook: the airtime of one episode of a show the calendar knows by IMDb id, or nil when TVMaze
    /// has no such episode. The calendar keeps its own date when this returns nil.
    func airtime(imdb: String, season: Int, number: Int, calendar: Calendar = .current, now: Date = Date()) async -> TVMazeAirtime? {
        guard let known = await lookupShow(imdb: imdb) else { return nil }
        let all = await episodes(showID: known.id, now: now)
        guard let episode = TVMazeRules.episode(all, season: season, number: number) else { return nil }
        return TVMazeRules.airtime(episode, calendar: calendar)
    }
}

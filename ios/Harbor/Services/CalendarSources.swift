import Foundation

/// The calendar's sources (Desktop's `calendarSource` setting, same values). Simkl, Custom and Games are not offered yet.
enum CalendarSource: String, CaseIterable, Sendable {
    case library, all, trakt, anticipated, anime

    /// Desktop's label, a translation key.
    var label: String {
        switch self {
        case .library: "My library"
        case .all: "All upcoming"
        case .trakt: "My Trakt"
        case .anticipated: "Trakt anticipated"
        case .anime: "Anime"
        }
    }
    var hint: String {
        switch self {
        case .library: "Upcoming episodes and movies from your saved shows"
        case .all: "Everything releasing this month from TMDB"
        case .trakt: "Upcoming episodes and movies from your Trakt watchlist"
        case .anticipated: "The most anticipated upcoming releases on Trakt"
        case .anime: "Anime episodes airing this month, sub or dub"
        }
    }
    var icon: String {
        switch self {
        case .library: "nav-library"
        case .all: "nav-explore"
        case .trakt, .anticipated: "tracker-trakt"
        case .anime: "nav-anime"
        }
    }
    /// Desktop hides "My Trakt" until Trakt is connected.
    static func offered(traktConnected: Bool) -> [CalendarSource] { allCases.filter { $0 != .trakt || traktConnected } }
}

/// One day's entry from Trakt's calendar before it is joined with its poster.
struct TraktCalendarEntry: Equatable, Sendable {
    var title: String
    var imdb: String?
    var tmdb: Int?
    var tvdb: Int?
    var isMovie: Bool
    var date: String
    var time: String?
    var atMs: Double?
    var season = 0
    var number = 0
    var episodeTitle: String?
    var overview: String?
}

/// Reads of Desktop's `lib/calendar.ts`, `calendar-sources.ts`, `trakt/calendar.ts` and `anilist/airing.ts`.
enum CalendarSources {
    private static func pad(_ value: Int) -> String { value < 10 ? "0\(value)" : "\(value)" }
    private static let image = "https://image.tmdb.org/t/p"
    private static let animationGenre = 16

    // MARK: TMDB (All upcoming)

    static func tmdbURL(_ path: String, key: String, _ query: [(String, String)]) -> URL? {
        var parts = URLComponents(string: "https://api.themoviedb.org/3" + path)
        parts?.queryItems = ([("api_key", key)] + query).map { URLQueryItem(name: $0.0, value: $0.1) }
        return parts?.url
    }
    static func discoverMovies(key: String, start: String, end: String, region: String, page: Int) -> URL? {
        var query: [(String, String)] = [("primary_release_date.gte", start), ("primary_release_date.lte", end)]
        if !region.isEmpty { query.append(("region", region)) }
        query += [("sort_by", "popularity.desc"), ("include_adult", "false"), ("with_runtime.gte", "30"), ("page", String(page))]
        return tmdbURL("/discover/movie", key: key, query)
    }
    static func discoverShows(key: String, start: String, end: String, page: Int) -> URL? {
        tmdbURL("/discover/tv", key: key, [("first_air_date.gte", start), ("first_air_date.lte", end), ("sort_by", "popularity.desc"), ("include_adult", "false"), ("page", String(page))])
    }
    static func upcomingMovies(key: String, region: String, page: Int) -> URL? {
        var query: [(String, String)] = []
        if !region.isEmpty { query.append(("region", region)) }
        query.append(("page", String(page)))
        return tmdbURL("/movie/upcoming", key: key, query)
    }

    private static func isAnimeRow(_ row: JSONValue) -> Bool {
        let animation = row["genre_ids"].array.contains { $0.integer == animationGenre }
        let japanese = row["original_language"].string == "ja" || row["origin_country"].array.contains { $0.string == "JP" }
        return animation && japanese
    }

    /// Desktop's `fetchCalendarRange` mapping: discover pages and upcoming movies in range, one item per title, by date.
    static func tmdbItems(movies: [JSONValue], shows: [JSONValue]) -> [CalendarItem] {
        func picture(_ row: JSONValue, _ field: String, _ size: String) -> String? {
            guard let path = row[field].string, !path.isEmpty else { return nil }
            return "\(image)/\(size)\(path)"
        }
        func poster(_ row: JSONValue) -> String? { picture(row, "poster_path", "w342") }
        func backdrop(_ row: JSONValue) -> String? { picture(row, "backdrop_path", "w780") }
        var items: [CalendarItem] = []
        for row in movies {
            guard let id = row["id"].integer, let date = row["release_date"].string, !date.isEmpty, let title = row["title"].string, !title.isEmpty else { continue }
            items.append(CalendarItem(id: "tmdb:movie:\(id)", imdbID: nil, isMovie: true, name: title, poster: poster(row), background: backdrop(row),
                                      releaseDate: String(date.prefix(10)), isAnime: isAnimeRow(row), overview: row["overview"].string ?? "", voteAverage: row["vote_average"].numericValue ?? 0))
        }
        for row in shows {
            guard let id = row["id"].integer, let date = row["first_air_date"].string, !date.isEmpty, let name = row["name"].string, !name.isEmpty else { continue }
            items.append(CalendarItem(id: "tmdb:tv:\(id)", imdbID: nil, isMovie: false, name: name, poster: poster(row), background: backdrop(row),
                                      releaseDate: String(date.prefix(10)), isAnime: isAnimeRow(row), overview: row["overview"].string ?? "", voteAverage: row["vote_average"].numericValue ?? 0))
        }
        var seen = Set<String>()
        return byDate(items.filter { seen.insert($0.id).inserted })
    }
    static func inRange(_ row: JSONValue, start: String, end: String) -> Bool {
        guard let date = row["release_date"].string, !date.isEmpty else { return false }
        return date >= start && date <= end
    }

    // MARK: Trakt (My Trakt, anticipated)

    private static func ids(_ value: JSONValue) -> (imdb: String?, tmdb: Int?, tvdb: Int?) {
        var imdb: String?
        if let text = value["imdb"].string, !text.isEmpty { imdb = text }
        return (imdb, value["tmdb"].integer, value["tvdb"].integer)
    }

    /// `/calendars/my/shows`: one entry per episode, on the local day it airs.
    static func traktEpisodes(_ value: JSONValue?, calendar: Calendar = .current) -> [TraktCalendarEntry] {
        (value?.array ?? []).compactMap { row -> TraktCalendarEntry? in
            guard let title = row["show"]["title"].string, let season = row["episode"]["season"].integer, let number = row["episode"]["number"].integer else { return nil }
            let when = CalendarTime.parse(row["first_aired"].string, calendar: calendar)
            let found = ids(row["show"]["ids"])
            return TraktCalendarEntry(title: title, imdb: found.imdb, tmdb: found.tmdb, tvdb: found.tvdb, isMovie: false, date: when.date, time: when.time, atMs: when.atMs,
                                      season: season, number: number, episodeTitle: row["episode"]["title"].string)
        }
    }
    /// `/calendars/my/movies`.
    static func traktMovies(_ value: JSONValue?, calendar: Calendar = .current) -> [TraktCalendarEntry] {
        (value?.array ?? []).compactMap { row -> TraktCalendarEntry? in
            guard let title = row["movie"]["title"].string else { return nil }
            let when = CalendarTime.parse(row["released"].string, calendar: calendar)
            let found = ids(row["movie"]["ids"])
            return TraktCalendarEntry(title: title, imdb: found.imdb, tmdb: found.tmdb, tvdb: nil, isMovie: true, date: when.date, time: when.time, atMs: when.atMs)
        }
    }
    /// `/shows/anticipated` and `/movies/anticipated`: only titles with a date, which is a plain day.
    static func anticipatedEntries(_ value: JSONValue?, movies: Bool) -> [TraktCalendarEntry] {
        (value?.array ?? []).compactMap { row -> TraktCalendarEntry? in
            let item = row[movies ? "movie" : "show"]
            guard let title = item["title"].string, let when = item[movies ? "released" : "first_aired"].string, !when.isEmpty else { return nil }
            let found = ids(item["ids"])
            return TraktCalendarEntry(title: title, imdb: found.imdb, tmdb: found.tmdb, tvdb: found.tvdb, isMovie: movies, date: String(when.prefix(10)), time: nil, atMs: nil, overview: item["overview"].string)
        }
    }

    /// The title's own id: IMDb when Trakt has it, otherwise an id Harbor can open from the TMDB id.
    static func traktBaseID(_ entry: TraktCalendarEntry) -> String {
        if let imdb = entry.imdb { return imdb }
        if let tmdb = entry.tmdb { return "tmdb:\(entry.isMovie ? "movie" : "tv"):\(tmdb)" }
        return "trakt:\(entry.tvdb.map(String.init) ?? entry.title)"
    }
    private static func isAnimation(_ genres: [String]?) -> Bool { (genres ?? []).contains { ["animation", "anime"].contains($0.lowercased()) } }

    /// Desktop's `fetchTraktCalendar` mapping: entries of the month joined with Cinemeta's poster, rating and genres.
    static func traktItems(_ entries: [TraktCalendarEntry], year: Int, month: Int, metas: [String: Media]) -> [CalendarItem] {
        var items: [CalendarItem] = []
        for entry in entries where CalendarTime.inMonth(entry.date, year: year, month: month) {
            let meta = entry.imdb.flatMap { metas[$0] }
            let base = traktBaseID(entry)
            let rating = meta?.imdbRating.flatMap { Double($0) } ?? 0
            if entry.isMovie {
                items.append(CalendarItem(id: base, imdbID: entry.imdb, isMovie: true, name: entry.title, poster: meta?.poster, background: meta?.background,
                                          releaseDate: entry.date, releaseTime: entry.time, releaseAtMs: entry.atMs, isAnime: isAnimation(meta?.genres),
                                          overview: meta?.description ?? "", voteAverage: rating))
            } else {
                let label = "S\(pad(entry.season))E\(pad(entry.number))"
                let video = meta?.videos?.first { ($0.season ?? 0) == entry.season && ($0.episode ?? 0) == entry.number }
                var name = "\(entry.title) \(label)"
                if let episodeTitle = entry.episodeTitle, !episodeTitle.isEmpty { name += ": \(episodeTitle)" }
                items.append(CalendarItem(id: "\(base):\(entry.season):\(entry.number)", imdbID: entry.imdb, isMovie: false, name: name, poster: meta?.poster ?? video?.thumbnail,
                                          background: meta?.background, releaseDate: entry.date, releaseTime: entry.time, releaseAtMs: entry.atMs,
                                          isAnime: isAnimation(meta?.genres), overview: meta?.description ?? "", voteAverage: rating))
            }
        }
        return byDate(items)
    }

    /// Desktop's `fetchAnticipatedCalendar` mapping: titles dated in the month, shows marked as premieres.
    static func anticipatedItems(_ entries: [TraktCalendarEntry], year: Int, month: Int, metas: [String: Media]) -> [CalendarItem] {
        var items: [CalendarItem] = []
        for entry in entries where CalendarTime.inMonth(entry.date, year: year, month: month) {
            let meta = entry.imdb.flatMap { metas[$0] }
            let base = traktBaseID(entry)
            items.append(CalendarItem(id: entry.isMovie ? base : "\(base):premiere", imdbID: entry.imdb, isMovie: entry.isMovie,
                                      name: entry.isMovie ? entry.title : "\(entry.title) (premiere)", poster: meta?.poster, background: meta?.background,
                                      releaseDate: entry.date, isAnime: false, overview: meta?.description ?? entry.overview ?? "",
                                      voteAverage: meta?.imdbRating.flatMap { Double($0) } ?? 0))
        }
        // Desktop lists the premieres before the movies.
        return byDate(items.filter { !$0.isMovie } + items.filter(\.isMovie))
    }

    // MARK: AniList (Anime)

    static let airingQuery = """
    query ($start: Int, $end: Int, $page: Int) {
      Page(page: $page, perPage: 50) {
        airingSchedules(airingAt_greater: $start, airingAt_lesser: $end, sort: TIME) {
          airingAt
          episode
          media {
            id
            idMal
            type
            isAdult
            format
            title { romaji english }
            coverImage { extraLarge large }
            bannerImage
            averageScore
            description
          }
        }
        pageInfo {
          hasNextPage
        }
      }
    }
    """

    static func stripHTML(_ text: String) -> String {
        text.replacingOccurrences(of: #"<br\s*/?>"#, with: " ", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Desktop's `fetchAniListAiringCalendar` mapping: one item per aired episode, adult titles and movies left out.
    static func airingItems(_ nodes: [JSONValue], calendar: Calendar = .current) -> [CalendarItem] {
        var items: [CalendarItem] = []
        var seen = Set<String>()
        for node in nodes {
            let media = node["media"]
            guard media != .null, media["type"].string == "ANIME", media["isAdult"] != .bool(true), media["format"].string != "MOVIE",
                  let episode = node["episode"].integer, let airing = node["airingAt"].numericValue, let mediaID = media["id"].integer else { continue }
            let english = media["title"]["english"].string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let romaji = media["title"]["romaji"].string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let title = !english.isEmpty ? english : (!romaji.isEmpty ? romaji : "Untitled")
            let base = media["idMal"].integer.map { "mal:\($0)" } ?? "anilist:\(mediaID)"
            let id = "\(base):1:\(episode)"
            guard seen.insert(id).inserted else { continue }
            let date = Date(timeIntervalSince1970: airing)
            items.append(CalendarItem(id: id, imdbID: nil, isMovie: false, name: "\(title) S1E\(pad(episode))",
                                      poster: media["coverImage"]["large"].string ?? media["coverImage"]["extraLarge"].string, background: media["bannerImage"].string,
                                      releaseDate: CalendarTime.dateString(date, calendar: calendar), releaseTime: CalendarTime.timeLabel(date, calendar: calendar),
                                      releaseAtMs: airing * 1_000, isAnime: true, overview: media["description"].string.map(stripHTML) ?? "",
                                      voteAverage: (media["averageScore"].numericValue ?? 0) / 10))
        }
        return byDate(items)
    }

    // MARK: Library names and empty months

    /// Desktop's `normalizeName`.
    static func normalizeName(_ text: String) -> String {
        text.lowercased().replacingOccurrences(of: "[’‘“”'\"`]", with: "", options: .regularExpression)
            .replacingOccurrences(of: "[^a-z0-9]+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    /// The key Desktop's "Watchlist only" matches a release against (`buildLibraryNameSet`).
    static func libraryKey(name: String, isSeries: Bool) -> String { "\(normalizeName(name))::\(isSeries ? "tv" : "movie")" }

    struct EmptyMonth: Equatable, Sendable {
        let heading: String
        let message: String
        var variables: [String: String] = [:]
    }
    /// Desktop's `EmptyState` (`views/calendar/empty-states.tsx`): texts are translation keys.
    static func emptyMonth(source: CalendarSource, filter: String, watchlistOnly: Bool) -> EmptyMonth {
        switch source {
        case .library:
            return EmptyMonth(heading: "Nothing from your library this month", message: "Your saved shows have no episodes scheduled for this month. Switch to All upcoming to browse the full release calendar.")
        case .trakt:
            return EmptyMonth(heading: "Nothing on Trakt this month", message: "Trakt has no upcoming releases for your watchlist this month. Past months and dates more than six months out aren't covered by Trakt's calendar feed.")
        case .anticipated:
            return EmptyMonth(heading: "Nothing anticipated this month", message: "None of Trakt's most-anticipated upcoming releases land in this month. Try a different month.")
        case .anime:
            return EmptyMonth(heading: "Nothing airing this month", message: "AniList has no anime episodes scheduled to air this month. Try a different month.")
        case .all:
            if watchlistOnly { return EmptyMonth(heading: "Nothing this month", message: "Nothing from your library lands this month. Toggle Watchlist off to see all releases.") }
            if filter == "all" { return EmptyMonth(heading: "Nothing this month", message: "TMDB has no notable releases for this month and region.") }
            return EmptyMonth(heading: "Nothing this month", message: "No {kind} releases this month. Try a different filter.", variables: ["kind": filter == "movie" ? "movies" : "TV"])
        }
    }

    /// A stable sort by day, as Desktop's `localeCompare` of ISO dates.
    static func byDate(_ items: [CalendarItem]) -> [CalendarItem] {
        items.enumerated().sorted { ($0.element.releaseDate, $0.offset) < ($1.element.releaseDate, $1.offset) }.map(\.element)
    }
}

/// Runs the sources. Every network call is a closure so a case can stand in for the service.
struct CalendarFetcher: Sendable {
    static let maxForwardMonths = 6
    static let animePages = 10
    static let animeConcurrency = 3

    var json: @Sendable (URL) async -> JSONValue? = { try? await HTTPClient().json($0.absoluteString, timeout: 15) }
    var trakt: @Sendable (String, [(String, String)]) async -> JSONValue? = { path, query in
        guard let request = TraktCommentsService.request(path, query: query), let reply = try? await HTTPClient().traktReply(request) else { return nil }
        return try? reply.value()
    }
    /// Trakt's calendar for the signed-in account; nil when Trakt is not connected.
    var mine: @Sendable (TraktHomeEndpoint) async -> JSONValue? = { _ in nil }
    var aniList: @Sendable (String, [String: JSONValue]) async throws -> JSONValue = { query, variables in
        try await AniListClient(transport: AniListHTTPTransport()).request(query, variables: variables, token: nil)
    }
    var cinemeta: @Sendable (String, String) async -> Media? = { kind, id in
        guard id.range(of: "^tt[0-9]+$", options: .regularExpression) != nil,
              let value = try? await HTTPClient().json("https://v3-cinemeta.strem.io/meta/\(kind)/\(id).json") else { return nil }
        return Media.parse(value["meta"], kind: kind)
    }
    var calendar: Calendar = .current

    private func results(_ url: URL?) async -> [JSONValue] {
        guard let url, let value = await json(url) else { return [] }
        return value["results"].array
    }

    /// All upcoming: every release of the month from TMDB, which needs the person's TMDB key.
    func allUpcoming(key: String, region: String, year: Int, month: Int) async -> [CalendarItem] {
        guard !key.isEmpty, let range = CalendarTime.monthRange(year: year, month: month, calendar: calendar) else { return [] }
        async let first = results(CalendarSources.discoverMovies(key: key, start: range.start, end: range.end, region: region, page: 1))
        async let second = results(CalendarSources.discoverMovies(key: key, start: range.start, end: range.end, region: region, page: 2))
        async let upcoming = results(CalendarSources.upcomingMovies(key: key, region: region, page: 1))
        async let shows = results(CalendarSources.discoverShows(key: key, start: range.start, end: range.end, page: 1))
        async let moreShows = results(CalendarSources.discoverShows(key: key, start: range.start, end: range.end, page: 2))
        let (a, b, c, d, e) = await (first, second, upcoming, shows, moreShows)
        let upcomingInRange = c.filter { CalendarSources.inRange($0, start: range.start, end: range.end) }
        return CalendarSources.tmdbItems(movies: a + b + upcomingInRange, shows: d + e)
    }

    /// Posters and genres for a few titles at a time.
    private func metas(_ entries: [TraktCalendarEntry]) async -> [String: Media] {
        var wanted: [(kind: String, id: String)] = []
        var seen = Set<String>()
        for entry in entries { if let imdb = entry.imdb, seen.insert(imdb).inserted { wanted.append((entry.isMovie ? "movie" : "series", imdb)) } }
        let lookup = cinemeta
        return await withTaskGroup(of: (String, Media?).self) { group in
            var output: [String: Media] = [:], next = 0
            func enqueue() {
                guard next < wanted.count else { return }
                let item = wanted[next]; next += 1
                group.addTask { (item.id, await lookup(item.kind, item.id)) }
            }
            for _ in 0..<min(4, wanted.count) { enqueue() }
            for await (id, media) in group { if let media { output[id] = media }; enqueue() }
            return output
        }
    }

    /// My Trakt: the account's upcoming episodes and movies, up to six months ahead.
    func myTrakt(year: Int, month: Int, now: Date = Date()) async -> [CalendarItem] {
        let today = calendar.dateComponents([.year, .month], from: now)
        guard let thisYear = today.year, let thisMonth = today.month else { return [] }
        let ahead = (year - thisYear) * 12 + (month - thisMonth)
        guard ahead >= 0, ahead <= Self.maxForwardMonths else { return [] }
        let days = max(31, (ahead + 1) * 31), day = TraktHomeEndpoint.utcDay(now)
        async let shows = mine(.calendarShows(day, days))
        async let movies = mine(.calendarMovies(day, days))
        let (showRows, movieRows) = await (shows, movies)
        let entries = (CalendarSources.traktEpisodes(showRows, calendar: calendar) + CalendarSources.traktMovies(movieRows, calendar: calendar))
            .filter { CalendarTime.inMonth($0.date, year: year, month: month) }
        return CalendarSources.traktItems(entries, year: year, month: month, metas: await metas(entries))
    }

    /// Trakt anticipated: the most anticipated shows and movies dated in the month.
    func anticipated(year: Int, month: Int) async -> [CalendarItem] {
        async let shows = trakt("/shows/anticipated", [("extended", "full"), ("limit", "100")])
        async let movies = trakt("/movies/anticipated", [("extended", "full"), ("limit", "100")])
        let (showRows, movieRows) = await (shows, movies)
        let entries = (CalendarSources.anticipatedEntries(showRows, movies: false) + CalendarSources.anticipatedEntries(movieRows, movies: true))
            .filter { CalendarTime.inMonth($0.date, year: year, month: month) }
        return CalendarSources.anticipatedItems(entries, year: year, month: month, metas: await metas(entries))
    }

    /// Anime: what AniList schedules to air in the month, a few pages at a time.
    func animeAiring(year: Int, month: Int) async -> [CalendarItem] {
        guard let first = calendar.date(from: DateComponents(year: year, month: month, day: 1)),
              let end = calendar.date(byAdding: .month, value: 1, to: first) else { return [] }
        let variables: [String: JSONValue] = ["start": .integer(Int64(first.timeIntervalSince1970)), "end": .integer(Int64(end.timeIntervalSince1970))]
        let request = aniList
        var pages: [Int: [JSONValue]] = [:]
        var next = 1, pastLast = false
        while !pastLast && next <= Self.animePages {
            let batch = Array(next..<min(next + Self.animeConcurrency, Self.animePages + 1)); next += batch.count
            await withTaskGroup(of: (Int, [JSONValue]?, Bool).self) { group in
                for page in batch {
                    group.addTask {
                        var withPage = variables; withPage["page"] = .integer(Int64(page))
                        guard let data = try? await request(CalendarSources.airingQuery, withPage) else { return (page, nil, false) }
                        let nodes = data["Page"]["airingSchedules"].array
                        if case .bool(let more) = data["Page"]["pageInfo"]["hasNextPage"] { return (page, nodes, more) }
                        return (page, nodes, nodes.count >= 50)
                    }
                }
                for await (page, nodes, more) in group {
                    if let nodes { pages[page] = nodes }
                    if !more { pastLast = true }
                }
            }
        }
        var nodes: [JSONValue] = []
        for page in 1...Self.animePages { guard let found = pages[page] else { break }; nodes += found }
        return CalendarSources.airingItems(nodes, calendar: calendar)
    }
}

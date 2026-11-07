import Foundation

/// Desktop's Simkl home rails as pure rules: `lib/simkl/home-rails.ts`, `home-rails/up-next.ts`, `home-rails/cdn.ts`
/// and `lib/simkl/calendar-data.ts`. Network and artwork hydration stay in `SimklHomeModel`.
enum SimklHomeRails {
    /// Desktop's `PER_RAIL`: titles per rail page.
    static let perRail = 24
    /// Desktop's Up Next window, in days from now.
    static let upNextDays = 30
    /// Desktop's trending rail is hidden below this many artworks.
    static let trendingMinimum = 4

    /// Desktop's `simklHomeRailsEnabled`, `simklUpNextRailEnabled`, `simklTrendingRailEnabled`,
    /// `simklGranularFilters` and `simklAnimeTitleLanguage` setting keys.
    enum Keys {
        static let homeRails = "simklHomeRailsEnabled"
        static let upNext = "simklUpNextRailEnabled"
        static let trending = "simklTrendingRailEnabled"
        static let animeTitleLanguage = "simklAnimeTitleLanguage"
        static let moviesPlanToWatch = "simklGranularFilters.movies.plantowatch"
        static let showsWatching = "simklGranularFilters.shows.watching"
        static let showsPlanToWatch = "simklGranularFilters.shows.plantowatch"
        static let all: [String] = [
            "simklHomeRailsEnabled", "simklUpNextRailEnabled", "simklTrendingRailEnabled", "simklAnimeTitleLanguage",
            "simklGranularFilters.movies.plantowatch", "simklGranularFilters.shows.watching", "simklGranularFilters.shows.plantowatch",
        ]
    }

    /// Desktop's `simklAnimeTitleLanguage` values.
    enum AnimeTitleLanguage: String, CaseIterable, Identifiable, Sendable {
        case english, romaji, native
        var id: String { rawValue }
    }

    /// The Desktop settings that shape the rails. Defaults match Desktop's `defaults.ts` and `simkl-panel.tsx`.
    struct Settings: Equatable, Sendable {
        var homeRails = false
        var upNext = false
        var trending = false
        var moviesPlanToWatch = true
        var showsWatching = true
        var showsPlanToWatch = true
        var animeTitleLanguage = AnimeTitleLanguage.english

        /// The values that change the rows. The anime title language is not in it: no rail uses it yet.
        var signature: String {
            [homeRails, upNext, trending, moviesPlanToWatch, showsWatching, showsPlanToWatch].map { String($0) }.joined(separator: ",")
        }
    }

    /// Desktop's row keys, in Desktop's order on Home.
    enum Key: String, CaseIterable, Sendable {
        case watchingShows = "simkl-watching-shows"
        case planMovies = "simkl-plantowatch-movies"
        case planShows = "simkl-plantowatch-shows"
        case upNext = "simkl-upcoming"
        case trending = "simkl-trending"
    }

    /// Desktop's row names.
    static func title(_ key: Key) -> String {
        switch key {
        case .watchingShows: DesktopInterfaceText.value("Watching TV Shows on Simkl")
        case .planMovies: DesktopInterfaceText.value("Plan to Watch Movies on Simkl")
        case .planShows: DesktopInterfaceText.value("Plan to Watch TV Shows on Simkl")
        case .upNext: DesktopInterfaceText.value("Up Next on Simkl")
        case .trending: DesktopInterfaceText.value("Simkl Trending Today")
        }
    }

    /// One rail before hydration: its ordered titles and Desktop's kind ("series" or "movie").
    struct Source: Equatable, Sendable {
        let key: Key
        let kind: String
        let items: [TraktLibraryItem]
        var hasMore: Bool { items.count > SimklHomeRails.perRail }
    }

    /// One entry of Simkl's `discover/trending/today_100.json`.
    struct Trending: Equatable, Sendable {
        let isMovie: Bool
        let title: String
        let year: Int?
        let ids: SimklIdentifiers
    }

    /// One airing of the Simkl calendar, joined to its title's ids (`parseSimklCalendar`).
    struct Airing: Equatable, Sendable {
        let date: Date
        let ids: SimklIdentifiers
    }

    // MARK: Library rows

    /// Desktop's `isAnimeType`: anime is identified by a MyAnimeList, AniDB or Kitsu id, not by the list bucket.
    static func isAnime(_ ids: SimklIdentifiers) -> Bool {
        ids.values["mal"] != nil || ids.values["anidb"] != nil || ids.values["kitsu"] != nil
    }

    /// Only the imdb and tmdb ids reach the hydrator (Desktop's `toHydratable`).
    static func hydratable(_ ids: SimklIdentifiers, type: TraktLibraryTarget.Kind, title: String, year: Int?) -> TraktLibraryItem {
        var keep: [String: JSONValue] = [:]
        if let imdb = ids.values["imdb"] { keep["imdb"] = imdb }
        if let tmdb = ids.values["tmdb"] { keep["tmdb"] = tmdb }
        return TraktLibraryItem(type: type, title: title, year: year, ids: TrackerShowIDs(.object(keep)))
    }

    /// Most recently added first. The snapshot is a dictionary, so this replaces Simkl's server order with a stable one.
    static func ordered(_ items: [SimklListItem]) -> [SimklListItem] {
        items.sorted { lhs, rhs in
            let left = lhs.addedAt ?? "", right = rhs.addedAt ?? ""
            if left != right { return left > right }
            return lhs.id < rhs.id
        }
    }

    // MARK: Rows

    /// Desktop's `buildSimklHomeRows` order: watching shows, plan to watch movies, plan to watch shows, Up Next, trending.
    /// Anime rows are not built here (see the port report). A row with no items is dropped.
    static func sources(library: [SimklListItem], airings: [Airing], trending: [Trending], settings: Settings, now: Date, calendar: Calendar) -> [Source] {
        guard settings.homeRails else { return [] }
        let plain = ordered(library).filter { !isAnime($0.ids) }
        var out: [Source] = []
        if settings.showsWatching {
            out.append(source(.watchingShows, "series", plain.filter { $0.status == .watching && $0.kind != .movie }))
        }
        if settings.moviesPlanToWatch {
            out.append(source(.planMovies, "movie", plain.filter { $0.status == .plantowatch && $0.kind == .movie }))
        }
        if settings.showsPlanToWatch {
            out.append(source(.planShows, "series", plain.filter { $0.status == .plantowatch && $0.kind != .movie }))
        }
        if settings.upNext {
            let items = upNext(airings: airings, library: ordered(library), now: now, calendar: calendar)
            out.append(source(.upNext, "series", items))
        }
        if settings.trending, let first = trending.first {
            let items = trending.map { hydratable($0.ids, type: $0.isMovie ? .movie : .show, title: $0.title, year: $0.year) }
            out.append(Source(key: .trending, kind: first.isMovie ? "movie" : "series", items: items))
        }
        return out.filter { !$0.items.isEmpty }
    }

    private static func source(_ key: Key, _ kind: String, _ items: [SimklListItem]) -> Source {
        Source(key: key, kind: kind, items: items.map { hydratable($0.ids, type: $0.kind == .movie ? .movie : .show, title: $0.title, year: $0.year) })
    }

    /// Desktop's `computeUpNextShows`: airings from today until the window end, in date order. Each airing matches a
    /// library show or anime that is watching or plan to watch, once per title.
    static func upNext(airings: [Airing], library: [SimklListItem], now: Date, calendar: Calendar) -> [TraktLibraryItem] {
        let today = calendar.startOfDay(for: now)
        guard let limit = calendar.date(byAdding: .day, value: upNextDays, to: now) else { return [] }
        let sortedAirings = airings.enumerated().sorted { lhs, rhs in
            if lhs.element.date != rhs.element.date { return lhs.element.date < rhs.element.date }
            return lhs.offset < rhs.offset
        }.map { $0.element }
        var seen = Set<String>()
        var out: [TraktLibraryItem] = []
        for airing in sortedAirings {
            guard airing.date >= today, airing.date <= limit else { continue }
            guard let hit = match(airing, in: library) else { continue }
            guard hit.kind != .movie, hit.status == .watching || hit.status == .plantowatch else { continue }
            guard seen.insert(hit.id).inserted else { continue }
            var values = hit.ids.values
            for key in ["imdb", "tmdb"] where values[key] == nil { values[key] = airing.ids.values[key] }
            out.append(hydratable(SimklIdentifiers(.object(values)), type: .show, title: hit.title, year: hit.year))
        }
        return out
    }

    /// Desktop's lookup order: Simkl id, then imdb, tmdb, MyAnimeList, Kitsu.
    static func match(_ airing: Airing, in library: [SimklListItem]) -> SimklListItem? {
        for key in ["simkl", "imdb", "tmdb", "mal", "kitsu"] {
            guard let wanted = airing.ids.values[key] else { continue }
            if let hit = library.first(where: { $0.ids.values[key] == wanted }) { return hit }
        }
        return nil
    }

    /// Desktop's rail gate after hydration: at least one artwork, four for trending.
    static func rail(_ source: Source, metas: [Media]) -> DiscoveryRail? {
        let minimum = source.key == .trending ? trendingMinimum : 1
        guard metas.count >= minimum else { return nil }
        return DiscoveryRail(id: source.key.rawValue, title: title(source.key), kind: source.kind, path: "simkl:" + source.key.rawValue, metas: metas)
    }

    // MARK: Parsing

    /// Desktop's `parseSimklCalendar` (V2): each airing needs a positive simkl id with metadata that has a title and a date.
    static func parseAirings(_ value: JSONValue) -> [Airing] {
        let metadata = value["metadata"].objectValue
        var out: [Airing] = []
        for entry in value["calendar"].array {
            guard let id = entry["simkl_id"].integer, id > 0 else { continue }
            let show = metadata[String(id)] ?? .null
            guard let title = show["title"].string, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            guard let text = entry["date"].string, let date = parseDate(text) else { continue }
            var ids = show["ids"].objectValue
            ids["simkl"] = .integer(Int64(id))
            out.append(Airing(date: date, ids: SimklIdentifiers(.object(ids))))
        }
        return out
    }

    /// Desktop's `discover/trending/today_100.json` reading: tv, movies and anime interleaved by index.
    static func parseTrending(_ value: JSONValue) -> [Trending] {
        let tv = value["tv"].array, movies = value["movies"].array, anime = value["anime"].array
        let count = max(tv.count, max(movies.count, anime.count))
        var out: [Trending] = []
        for index in 0..<count {
            if index < tv.count { out.append(trendingEntry(tv[index], isMovie: false)) }
            if index < movies.count { out.append(trendingEntry(movies[index], isMovie: true)) }
            if index < anime.count { out.append(trendingEntry(anime[index], isMovie: anime[index]["anime_type"].string == "movie")) }
        }
        return out
    }

    private static func trendingEntry(_ raw: JSONValue, isMovie: Bool) -> Trending {
        let ids = raw["ids"]
        let values: [String: JSONValue] = [
            "simkl": ids["simkl_id"], "imdb": ids["imdb"], "tmdb": ids["tmdb"], "mal": ids["mal"],
            "kitsu": ids["kitsu"], "anidb": ids["anidb"], "tvdb": ids["tvdb"],
        ]
        return Trending(isMovie: isMovie, title: raw["title"].string ?? "", year: releaseYear(raw["release_date"].string),
            ids: SimklIdentifiers(.object(values)))
    }

    /// Desktop reads the year as `parseInt` of the last `/` segment, so "2026-01-02" gives 2026 and "" gives nothing.
    static func releaseYear(_ text: String?) -> Int? {
        guard let text = text, let last = text.split(separator: "/", omittingEmptySubsequences: false).last else { return nil }
        guard let year = Int(last.prefix(while: { $0 >= "0" && $0 <= "9" })), year > 0 else { return nil }
        return year
    }

    static func parseDate(_ text: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: text) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: text)
    }
}

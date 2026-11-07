import Foundation

/// The calendar's sources (Desktop's `calendarSource` setting, same values). My Simkl and Games are not offered yet.
enum CalendarSource: String, CaseIterable, Sendable {
    case library, all, trakt, anticipated
    case simklAnticipated = "simkl-anticipated"
    case anime, custom

    /// Desktop's label, a translation key.
    var label: String {
        switch self {
        case .library: "My library"
        case .all: "All upcoming"
        case .trakt: "My Trakt"
        case .anticipated: "Trakt anticipated"
        case .simklAnticipated: "Simkl premieres"
        case .anime: "Anime"
        case .custom: "Custom"
        }
    }
    var hint: String {
        switch self {
        case .library: "Upcoming episodes and movies from your saved shows"
        case .all: "Everything releasing this month from TMDB"
        case .trakt: "Upcoming episodes and movies from your Trakt watchlist"
        case .anticipated: "The most anticipated upcoming releases on Trakt"
        case .simklAnticipated: "New shows and anime premiering this month, from Simkl"
        case .anime: "Anime episodes airing this month, sub or dub"
        case .custom: "Build your own feed from actors, directors, and Trakt lists"
        }
    }
    var icon: String {
        switch self {
        case .library: "nav-library"
        case .all: "nav-explore"
        case .trakt, .anticipated: "tracker-trakt"
        case .simklAnticipated: "tracker-simkl"
        case .anime: "nav-anime"
        case .custom: "desktop-star"
        }
    }
    /// Desktop hides "My Trakt" until Trakt is connected, and the Simkl source until Simkl is.
    static func offered(traktConnected: Bool, simklConnected: Bool = false) -> [CalendarSource] {
        allCases.filter { ($0 != .trakt || traktConnected) && ($0 != .simklAnticipated || simklConnected) }
    }
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

    // MARK: Simkl premieres (data.simkl.in)

    /// The public application identity Desktop ships, not a personal token.
    static let simklClientID = "9609ef0a6051b6fdcf3290fd962fd65e0f8e969c942555410cffd37afca91997"

    /// One airing of Simkl's calendar joined with its title's shared metadata.
    struct SimklCdnItem: Equatable, Sendable {
        var title: String
        var poster: String?
        var date: String
        var rating: Double?
        var imdb: String?
        var tmdb: String?
        var mal: String?
        var simklID: Int
        var season: Int?
        var episode: Int?
    }

    /// The catalogs of Desktop's `fetchSimklCdnArchive`: tv, anime and movie.
    static func simklURL(year: Int, month: Int, catalog: String) -> URL? {
        guard ["tv", "anime", "movie"].contains(catalog) else { return nil }
        var parts = URLComponents(string: "https://data.simkl.in/calendar/v2/\(year)/\(month)/\(catalog == "movie" ? "movie_release" : catalog).json")
        parts?.queryItems = [URLQueryItem(name: "client_id", value: simklClientID), URLQueryItem(name: "app-name", value: "harbor"), URLQueryItem(name: "app-version", value: "0.9.132")]
        return parts?.url
    }

    /// An id Simkl sent as a number or a string; zero and empty mean none.
    private static func simklID(_ value: JSONValue) -> String? {
        switch value {
        case .string(let text): return text.isEmpty ? nil : text
        case .integer(let number): return number == 0 ? nil : String(number)
        case .number(let number): return number == 0 || !number.isFinite ? nil : String(Int(number))
        default: return nil
        }
    }

    /// Desktop's `parseSimklCalendar`: the v2 file stores each title once and joins every airing by its Simkl id.
    static func simklCalendar(_ json: JSONValue?) -> [SimklCdnItem] {
        guard let json, case .array(let calendar) = json["calendar"], case .object(let metadata) = json["metadata"] else { return [] }
        var items: [SimklCdnItem] = []
        for entry in calendar {
            guard let id = entry["simkl_id"].integer, id > 0, case .object(let show) = metadata[String(id)] ?? .null,
                  let title = show["title"]?.string, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  let date = entry["date"].string, CalendarTime.instant(date) != nil || date.range(of: "^[0-9]{4}-[0-9]{2}-[0-9]{2}$", options: .regularExpression) != nil else { continue }
            let ids = show["ids"] ?? .null
            var imdb: String?
            if let text = ids["imdb"].string, !text.isEmpty { imdb = text }
            items.append(SimklCdnItem(title: title, poster: show["poster"]?.string, date: date, rating: show["ratings"]?["simkl"]["rating"].numericValue, imdb: imdb,
                                      tmdb: simklID(ids["tmdb"]), mal: simklID(ids["mal"]), simklID: id,
                                      season: entry["episode"]["season"].integer, episode: entry["episode"]["episode"].integer))
        }
        return items
    }

    /// Desktop's `mapCdnItem`. A title Simkl knows only by its MAL id opens through that id.
    static func simklItems(_ rows: [SimklCdnItem], movie: Bool, anime: Bool) -> [CalendarItem] {
        rows.map { row -> CalendarItem in
            let id: String
            if let imdb = row.imdb { id = imdb }
            else if let tmdb = row.tmdb { id = "tmdb:\(movie ? "movie" : "tv"):\(tmdb)" }
            else if anime, let mal = row.mal { id = "mal:\(mal)" }
            else { id = "simkl:\(row.simklID)" }
            var name = row.title
            if !movie, let season = row.season, let episode = row.episode { name = "\(row.title) S\(pad(season))E\(pad(episode))" }
            let poster = row.poster.flatMap { $0.isEmpty ? nil : "https://wsrv.nl/?url=https://simkl.in/posters/\($0)_m.webp&q=90" }
            return CalendarItem(id: id, imdbID: row.imdb, isMovie: movie, name: name, poster: poster, background: nil, releaseDate: String(row.date.prefix(10)),
                                isAnime: anime, overview: "", voteAverage: row.rating ?? 0)
        }
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

    // MARK: Anime dub schedule (AniSchedule)

    /// Desktop's `mapDubFeedToCalendar`: the dub schedule's episodes of the month, one item per episode.
    static func dubItems(_ entries: [JSONValue], year: Int, month: Int, calendar: Calendar = .current) -> [CalendarItem] {
        func clean(_ value: JSONValue) -> String { value.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "" }
        var items: [CalendarItem] = []
        var seen = Set<String>()
        for entry in entries {
            let media = entry["media"]["media"]
            guard media != .null, media["isAdult"] != .bool(true), media["format"].string != "MOVIE", let episode = entry["episodeNumber"].integer else { continue }
            let when = CalendarTime.parse(entry["episodeDate"].string, calendar: calendar)
            guard CalendarTime.inMonth(when.date, year: year, month: month) else { continue }
            let candidates = [clean(media["title"]["english"]), clean(media["title"]["romaji"]), clean(entry["english"]), clean(entry["romaji"])]
            let title = candidates.first { !$0.isEmpty } ?? "Untitled"
            let base: String
            if let mal = media["idMal"].integer { base = "mal:\(mal)" }
            else if let id = media["id"].integer { base = "anilist:\(id)" }
            else { continue }
            let id = "\(base):1:\(episode)"
            guard seen.insert(id).inserted else { continue }
            items.append(CalendarItem(id: id, imdbID: nil, isMovie: false, name: "\(title) S1E\(pad(episode))",
                                      poster: media["coverImage"]["extraLarge"].string ?? media["coverImage"]["medium"].string, background: media["bannerImage"].string,
                                      releaseDate: when.date, releaseTime: when.time, releaseAtMs: when.atMs, isAnime: true, overview: "", voteAverage: 0))
        }
        return byDate(items)
    }

    // MARK: Custom (people, genres, providers and countries)

    /// Desktop's `discoverFiltered`: a month of TMDB discover narrowed by genre, provider and origin country. No filter, no request.
    static func discoverFiltered(key: String, start: String, end: String, region: String, kind: String, genreIDs: [Int], providerIDs: [Int], countries: [String]) -> URL? {
        guard !(genreIDs.isEmpty && providerIDs.isEmpty && countries.isEmpty), kind == "movie" || kind == "tv" else { return nil }
        var query: [(String, String)] = []
        if kind == "movie" {
            query += [("primary_release_date.gte", start), ("primary_release_date.lte", end)]
            if !region.isEmpty { query.append(("region", region)) }
            query.append(("with_runtime.gte", "30"))
        } else {
            query += [("first_air_date.gte", start), ("first_air_date.lte", end)]
        }
        query += [("sort_by", "popularity.desc"), ("include_adult", "false")]
        if !genreIDs.isEmpty { query.append(("with_genres", genreIDs.map(String.init).joined(separator: ","))) }
        if !providerIDs.isEmpty {
            query.append(("with_watch_providers", providerIDs.map(String.init).joined(separator: "|")))
            query.append(("watch_region", region.isEmpty ? "US" : region))
        }
        if !countries.isEmpty { query.append(("with_origin_country", countries.joined(separator: "|"))) }
        return tmdbURL("/discover/\(kind)", key: key, query)
    }
    static func personCreditsURL(key: String, personID: Int, kind: String) -> URL? {
        guard personID > 0, kind == "movie" || kind == "tv" else { return nil }
        return tmdbURL("/person/\(personID)/\(kind)_credits", key: key, [])
    }
    static func searchPeopleURL(key: String, query: String) -> URL? {
        tmdbURL("/search/person", key: key, [("query", query), ("include_adult", "false")])
    }

    private static func firstText(_ values: JSONValue...) -> String {
        values.compactMap { $0.string }.first { !$0.isEmpty } ?? "Untitled"
    }

    /// A TMDB movie or show row as an item, with Desktop's name fallbacks (title, original title, "Untitled").
    static func tmdbRowItem(_ row: JSONValue, movie: Bool) -> CalendarItem? {
        guard let id = row["id"].integer else { return nil }
        func picture(_ field: String, _ size: String) -> String? {
            guard let path = row[field].string, !path.isEmpty else { return nil }
            return "\(image)/\(size)\(path)"
        }
        let date = row[movie ? "release_date" : "first_air_date"].string ?? ""
        return CalendarItem(id: "tmdb:\(movie ? "movie" : "tv"):\(id)", imdbID: nil, isMovie: movie,
                            name: movie ? firstText(row["title"], row["original_title"]) : firstText(row["name"], row["original_name"]),
                            poster: picture("poster_path", "w342"), background: picture("backdrop_path", "w780"), releaseDate: String(date.prefix(10)),
                            isAnime: isAnimeRow(row), overview: row["overview"].string ?? "", voteAverage: row["vote_average"].numericValue ?? 0)
    }

    /// Desktop's `discoverFiltered` mapping.
    static func discoverItems(_ rows: [JSONValue], movie: Bool) -> [CalendarItem] { rows.compactMap { tmdbRowItem($0, movie: movie) } }

    /// Desktop's `fetchPersonUpcoming` mapping: a person's cast and crew credits dated inside the window, once per title.
    static func personItems(movies: [JSONValue], shows: [JSONValue], start: String, end: String) -> [CalendarItem] {
        func inWindow(_ date: String?) -> Bool {
            guard let date, !date.isEmpty else { return false }
            let day = String(date.prefix(10))
            return day >= start && day <= end
        }
        var items: [CalendarItem] = []
        var seen = Set<String>()
        for row in movies where inWindow(row["release_date"].string) {
            if let item = tmdbRowItem(row, movie: true), seen.insert(item.id).inserted { items.append(item) }
        }
        for row in shows where inWindow(row["first_air_date"].string) {
            if let item = tmdbRowItem(row, movie: false), seen.insert(item.id).inserted { items.append(item) }
        }
        return items
    }

    /// Desktop's `fetchCustomCalendar` merge: the extra sources first, then the people and discover batches; only the
    /// media types the person wants (anime has its own switch), one item per title, by day.
    static func customItems(batches: [[CalendarItem]], extra: [CalendarItem], mediaTypes: CustomCalendar.MediaTypes) -> [CalendarItem] {
        var seen = Set<String>()
        var kept: [CalendarItem] = []
        for item in extra + batches.flatMap({ $0 }) {
            let wanted = item.isAnime ? mediaTypes.anime : (item.isMovie ? mediaTypes.movie : mediaTypes.tv)
            guard wanted, seen.insert(item.id).inserted else { continue }
            kept.append(item)
        }
        return byDate(kept)
    }

    struct PersonResult: Equatable, Sendable, Identifiable {
        let id: Int
        let name: String
        let profile: String?
        let knownFor: String
    }

    /// People from a TMDB person search, as Desktop's search lists them: what they are known for, else their department.
    static func people(from json: JSONValue?, limit: Int = 8) -> [PersonResult] {
        guard let json else { return [] }
        return json["results"].array.compactMap { row -> PersonResult? in
            guard let id = row["id"].integer, let name = row["name"].string, !name.isEmpty else { return nil }
            let known = row["known_for"].array.map { $0["title"].string ?? $0["name"].string ?? "" }.filter { !$0.isEmpty }.prefix(2).joined(separator: ", ")
            let profile = row["profile_path"].string.flatMap { $0.isEmpty ? nil : $0 }
            return PersonResult(id: id, name: name, profile: profile, knownFor: known.isEmpty ? (row["known_for_department"].string ?? "Cast") : known)
        }.prefix(limit).map { $0 }
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
    static func emptyMonth(source: CalendarSource, filter: String, watchlistOnly: Bool, animeDub: Bool = false) -> EmptyMonth {
        switch source {
        case .library:
            return EmptyMonth(heading: "Nothing from your library this month", message: "Your saved shows have no episodes scheduled for this month. Switch to All upcoming to browse the full release calendar.")
        case .trakt:
            return EmptyMonth(heading: "Nothing on Trakt this month", message: "Trakt has no upcoming releases for your watchlist this month. Past months and dates more than six months out aren't covered by Trakt's calendar feed.")
        case .anticipated:
            return EmptyMonth(heading: "Nothing anticipated this month", message: "None of Trakt's most-anticipated upcoming releases land in this month. Try a different month.")
        case .simklAnticipated:
            return EmptyMonth(heading: "No Simkl premieres this month", message: "Simkl lists no new shows or anime premiering this month. Try a different month.")
        case .anime:
            if animeDub { return EmptyMonth(heading: "No dubbed episodes this month", message: "The dub schedule has no episodes releasing this month. Try a different month.") }
            return EmptyMonth(heading: "Nothing airing this month", message: "AniList has no anime episodes scheduled to air this month. Try a different month.")
        case .all, .custom:
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

/// The AniSchedule dub feed, kept for half an hour (Desktop's `fetchDubSchedule`); a failed read answers the last good one.
actor AnimeDubFeed {
    static let shared = AnimeDubFeed()
    static let url = URL(string: "https://raw.githubusercontent.com/RockinChaos/AniSchedule/master/raw/dub-schedule.json")!
    static let staleAfter: TimeInterval = 30 * 60
    private var cache: (entries: [JSONValue], at: Date)?

    func entries(now: Date = Date(), fetch: @Sendable (URL) async -> JSONValue?) async -> [JSONValue] {
        if let cache, now.timeIntervalSince(cache.at) < Self.staleAfter { return cache.entries }
        guard let value = await fetch(Self.url), case .array(let rows) = value else { return cache?.entries ?? [] }
        cache = (rows, now)
        return rows
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
    var dubFeed: AnimeDubFeed = .shared

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

    private func simklCatalog(_ catalog: String, year: Int, month: Int) async -> [CalendarItem] {
        guard let url = CalendarSources.simklURL(year: year, month: month, catalog: catalog), let data = await json(url) else { return [] }
        return CalendarSources.simklItems(CalendarSources.simklCalendar(data), movie: catalog == "movie", anime: catalog == "anime")
    }

    /// Simkl premieres: the new shows, anime and movies of the month from Simkl's public calendar files.
    func simklPremieres(year: Int, month: Int) async -> [CalendarItem] {
        async let shows = simklCatalog("tv", year: year, month: month)
        async let anime = simklCatalog("anime", year: year, month: month)
        async let movies = simklCatalog("movie", year: year, month: month)
        let (a, b, c) = await (shows, anime, movies)
        return CalendarSources.byDate(a + b + c)
    }

    private func credits(_ url: URL?) async -> [JSONValue] {
        guard let url, let data = await json(url) else { return [] }
        return data["cast"].array + data["crew"].array
    }

    private func discover(_ url: URL?, movie: Bool) async -> [CalendarItem] { CalendarSources.discoverItems(await results(url), movie: movie) }

    /// Custom: the people followed, the discover queries their genres, providers and countries make, and any extra sources,
    /// kept to the media types wanted. Needs the TMDB key.
    func customCalendar(key: String, region: String, filters: CustomCalendar, year: Int, month: Int, extra: [CalendarItem] = []) async -> [CalendarItem] {
        guard !key.isEmpty, let range = CalendarTime.monthRange(year: year, month: month, calendar: calendar) else { return [] }
        let movieGenres = filters.genres.filter { $0.mediaType == "movie" }.map(\.id)
        let tvGenres = filters.genres.filter { $0.mediaType == "tv" }.map(\.id)
        let providers = filters.watchProviders.map(\.id)
        let wantsMovies = filters.mediaTypes.movie || filters.mediaTypes.anime
        let wantsShows = filters.mediaTypes.tv || filters.mediaTypes.anime
        var jobs: [@Sendable () async -> [CalendarItem]] = []
        for person in filters.trackedPeople {
            jobs.append { @Sendable in
                async let movies = self.credits(CalendarSources.personCreditsURL(key: key, personID: person.id, kind: "movie"))
                async let shows = self.credits(CalendarSources.personCreditsURL(key: key, personID: person.id, kind: "tv"))
                let (m, s) = await (movies, shows)
                return CalendarSources.personItems(movies: m, shows: s, start: range.start, end: range.end)
            }
        }
        if wantsMovies {
            let url = CalendarSources.discoverFiltered(key: key, start: range.start, end: range.end, region: region, kind: "movie", genreIDs: movieGenres, providerIDs: providers, countries: filters.originCountries)
            jobs.append { @Sendable in await self.discover(url, movie: true) }
        }
        if wantsShows {
            let url = CalendarSources.discoverFiltered(key: key, start: range.start, end: range.end, region: region, kind: "tv", genreIDs: tvGenres, providerIDs: providers, countries: filters.originCountries)
            jobs.append { @Sendable in await self.discover(url, movie: false) }
        }
        let batches = await withTaskGroup(of: (Int, [CalendarItem]).self) { group -> [[CalendarItem]] in
            for (index, job) in jobs.enumerated() { group.addTask { (index, await job()) } }
            var found: [Int: [CalendarItem]] = [:]
            for await (index, items) in group { found[index] = items }
            return jobs.indices.map { found[$0] ?? [] }
        }
        return CalendarSources.customItems(batches: batches, extra: extra, mediaTypes: filters.mediaTypes)
    }

    /// A person search for the Custom source's "Track people" field.
    func searchPeople(key: String, query: String) async -> [CalendarSources.PersonResult] {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, !text.isEmpty, let url = CalendarSources.searchPeopleURL(key: key, query: text) else { return [] }
        return CalendarSources.people(from: await json(url))
    }

    /// Anime (Dub): the dub schedule's episodes of the month.
    func animeDub(year: Int, month: Int, now: Date = Date()) async -> [CalendarItem] {
        let rows = await dubFeed.entries(now: now, fetch: json)
        return CalendarSources.dubItems(rows, year: year, month: month, calendar: calendar)
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

import XCTest
@testable import Harbor

private final class StringLog: @unchecked Sendable {
    private let lock = NSLock()
    private var seen: [String] = []
    var entries: [String] { lock.withLock { seen } }
    func add(_ entry: String) { lock.withLock { seen.append(entry) } }
}

private func jsonInts(_ values: [Int]) -> JSONValue { .array(values.map { JSONValue.integer(Int64($0)) }) }

private func movieRow(_ id: Int, _ title: String, _ date: String, genres: [Int] = [], language: String = "en") -> JSONValue {
    .object(["id": .integer(Int64(id)), "title": .string(title), "release_date": .string(date), "overview": .string("About \(title)"), "poster_path": .string("/p\(id).jpg"),
             "backdrop_path": .string("/b\(id).jpg"), "vote_average": .number(7.5), "genre_ids": jsonInts(genres), "original_language": .string(language)])
}

private func showRow(_ id: Int, _ name: String, _ date: String, genres: [Int] = [], country: [String] = []) -> JSONValue {
    .object(["id": .integer(Int64(id)), "name": .string(name), "first_air_date": .string(date), "overview": .string("About \(name)"), "poster_path": .string("/p\(id).jpg"),
             "backdrop_path": .null, "vote_average": .number(8), "genre_ids": jsonInts(genres), "origin_country": .array(country.map { JSONValue.string($0) })])
}

private func airing(_ id: Int, mal: Int?, episode: Int?, at: Double, type: String = "ANIME", adult: Bool = false, format: String = "TV", english: String = "", romaji: String = "Romaji") -> JSONValue {
    var title: [String: JSONValue] = [:]
    title["english"] = .string(english); title["romaji"] = .string(romaji)
    var cover: [String: JSONValue] = [:]
    cover["extraLarge"] = .string("x.jpg"); cover["large"] = .string("l.jpg")
    var media: [String: JSONValue] = [:]
    media["id"] = .integer(Int64(id)); media["type"] = .string(type); media["isAdult"] = .bool(adult); media["format"] = .string(format)
    media["idMal"] = mal.map { JSONValue.integer(Int64($0)) } ?? JSONValue.null
    media["title"] = .object(title); media["coverImage"] = .object(cover); media["bannerImage"] = .string("b.jpg")
    media["averageScore"] = .integer(82); media["description"] = .string("Plot<br>line <i>two</i>")
    var node: [String: JSONValue] = [:]
    node["airingAt"] = .integer(Int64(at)); node["media"] = .object(media)
    node["episode"] = episode.map { JSONValue.integer(Int64($0)) } ?? JSONValue.null
    return .object(node)
}

private func simklEntry(_ id: Int, _ date: String, season: Int? = nil, episode: Int? = nil) -> JSONValue {
    var entry: [String: JSONValue] = ["simkl_id": .integer(Int64(id)), "date": .string(date)]
    if let season, let episode { entry["episode"] = .object(["season": .integer(Int64(season)), "episode": .integer(Int64(episode))]) }
    return .object(entry)
}

private func simklShow(_ title: String, poster: String? = nil, rating: Double? = nil, ids: [String: JSONValue] = [:]) -> JSONValue {
    var show: [String: JSONValue] = ["title": .string(title), "ids": .object(ids)]
    if let poster { show["poster"] = .string(poster) }
    if let rating { show["ratings"] = .object(["simkl": .object(["rating": .number(rating)])]) }
    return .object(show)
}

private func simklPayload(_ entries: [JSONValue], _ metadata: [String: JSONValue]) -> JSONValue {
    .object(["calendar": .array(entries), "metadata": .object(metadata)])
}

/// Desktop's calendar sources (`lib/calendar.ts`, `calendar-sources.ts`, `trakt/calendar.ts`, `anilist/airing.ts`).
final class CalendarSourcesTests: XCTestCase {
    private let utc: Calendar = { var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "UTC")!; return calendar }()
    private let newYork: Calendar = { var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "America/New_York")!; return calendar }()

    private func epoch(_ iso: String) -> Double { ISO8601DateFormatter().date(from: iso)!.timeIntervalSince1970 }
    private func query(_ url: URL?) -> [String: String] {
        Dictionary(uniqueKeysWithValues: (URLComponents(url: url!, resolvingAgainstBaseURL: false)?.queryItems ?? []).map { ($0.name, $0.value ?? "") })
    }
    func testTimesBecomeLocalDaysAndHoursLikeDesktop() throws {
        let utcParts = CalendarTime.parse("2026-11-07T01:00:00.000Z", calendar: utc)
        XCTAssertEqual(utcParts.date, "2026-11-07"); XCTAssertEqual(utcParts.time, "1:00 AM"); XCTAssertEqual(try XCTUnwrap(utcParts.atMs), epoch("2026-11-07T01:00:00Z") * 1_000)
        let local = CalendarTime.parse("2026-11-07T01:00:00Z", calendar: newYork)
        XCTAssertEqual(local.date, "2026-11-06", "01:00 UTC is the evening before in New York"); XCTAssertEqual(local.time, "8:00 PM")
        let plain = CalendarTime.parse("2026-11-07", calendar: newYork)
        XCTAssertEqual(plain.date, "2026-11-07"); XCTAssertNil(plain.time); XCTAssertNil(plain.atMs)
        XCTAssertEqual(CalendarTime.parse("2026-11-07Tnonsense", calendar: utc).date, "2026-11-07")
        XCTAssertEqual(CalendarTime.parse(nil).date, ""); XCTAssertEqual(CalendarTime.parse("").date, "")

        for (hour, minute, label) in [(0, 5, "12:05 AM"), (12, 0, "12:00 PM"), (13, 9, "1:09 PM"), (23, 59, "11:59 PM")] {
            XCTAssertEqual(CalendarTime.timeLabel(utc.date(from: DateComponents(year: 2026, month: 11, day: 7, hour: hour, minute: minute))!, calendar: utc), label)
        }
        let range = try XCTUnwrap(CalendarTime.monthRange(year: 2028, month: 2, calendar: utc))
        XCTAssertEqual(range.start, "2028-02-01"); XCTAssertEqual(range.end, "2028-02-29")
        XCTAssertEqual(try XCTUnwrap(CalendarTime.monthRange(year: 2026, month: 12, calendar: utc)).end, "2026-12-31")
        XCTAssertTrue(CalendarTime.inMonth("2026-11-30", year: 2026, month: 11)); XCTAssertFalse(CalendarTime.inMonth("2026-12-01", year: 2026, month: 11))
        XCTAssertFalse(CalendarTime.inMonth("", year: 2026, month: 11))
        XCTAssertEqual(CalendarTime.startOfDay("2026-11-07", calendar: utc), utc.date(from: DateComponents(year: 2026, month: 11, day: 7)))
    }

    func testAnItemOpensItsTitleAndKeepsTheEpisodeItCameFrom() {
        let episode = CalendarItem(id: "tmdb:tv:55:1:12", imdbID: nil, isMovie: false, name: "Beta S01E12: Finale", poster: "p", background: "b", releaseDate: "2026-11-09", isAnime: false, overview: "Plot", voteAverage: 7)
        XCTAssertEqual(episode.baseID, "tmdb:tv:55"); XCTAssertEqual(episode.baseName, "Beta")
        XCTAssertEqual(episode.episodeHint?.season, 1); XCTAssertEqual(episode.episodeHint?.episode, 12)
        let media = episode.media
        XCTAssertEqual(media.id, "tmdb:tv:55"); XCTAssertEqual(media.type, "series"); XCTAssertEqual(media.name, "Beta")
        XCTAssertEqual(media.poster, "p"); XCTAssertEqual(media.background, "b"); XCTAssertEqual(media.description, "Plot"); XCTAssertEqual(media.releaseInfo, "2026"); XCTAssertEqual(media.released, "2026-11-09")
        let premiere = CalendarItem(id: "tt300:premiere", imdbID: "tt300", isMovie: false, name: "Show One (premiere)", releaseDate: "2026-11-14", isAnime: false, overview: "", voteAverage: 0)
        XCTAssertEqual(premiere.baseID, "tt300"); XCTAssertEqual(premiere.baseName, "Show One"); XCTAssertNil(premiere.episodeHint); XCTAssertNil(premiere.media.description)
        let movie = CalendarItem(id: "tt200", imdbID: "tt200", isMovie: true, name: "Film", releaseDate: "2026-11-20", isAnime: false, overview: "", voteAverage: 0)
        XCTAssertEqual(movie.media.type, "movie"); XCTAssertEqual(movie.media.imdbID, "tt200"); XCTAssertEqual(movie.baseID, "tt200")
        XCTAssertEqual(CalendarItem(id: "mal:100:1:5", imdbID: nil, isMovie: false, name: "A S1E05", releaseDate: "", isAnime: true, overview: "", voteAverage: 0).baseID, "mal:100")
    }

    func testTMDBRequestsCarryTheKeyRegionAndPaging() {
        let movies = query(CalendarSources.discoverMovies(key: "k", start: "2026-11-01", end: "2026-11-30", region: "ES", page: 2))
        XCTAssertEqual(movies, ["api_key": "k", "primary_release_date.gte": "2026-11-01", "primary_release_date.lte": "2026-11-30", "region": "ES", "sort_by": "popularity.desc",
                                "include_adult": "false", "with_runtime.gte": "30", "page": "2"])
        XCTAssertEqual(CalendarSources.discoverMovies(key: "k", start: "a", end: "b", region: "", page: 1)?.path, "/3/discover/movie")
        XCTAssertNil(query(CalendarSources.discoverMovies(key: "k", start: "a", end: "b", region: "", page: 1))["region"], "No region sends none")
        XCTAssertEqual(query(CalendarSources.discoverShows(key: "k", start: "2026-11-01", end: "2026-11-30", page: 1)),
                       ["api_key": "k", "first_air_date.gte": "2026-11-01", "first_air_date.lte": "2026-11-30", "sort_by": "popularity.desc", "include_adult": "false", "page": "1"])
        XCTAssertEqual(CalendarSources.upcomingMovies(key: "k", region: "US", page: 1)?.path, "/3/movie/upcoming")
        XCTAssertEqual(query(CalendarSources.upcomingMovies(key: "k", region: "US", page: 1)), ["api_key": "k", "region": "US", "page": "1"])
    }

    func testTMDBRowsBecomeOneItemPerTitleByDate() {
        let items = CalendarSources.tmdbItems(
            movies: [movieRow(1, "Late", "2026-11-20", genres: [28]), movieRow(2, "Anime Film", "2026-11-05", genres: [16, 12], language: "ja"), movieRow(3, "", "2026-11-06"),
                     movieRow(4, "No date", ""), movieRow(1, "Late", "2026-11-20")],
            shows: [showRow(10, "Show A", "2026-11-05", genres: [16], country: ["JP"]), showRow(11, "Show B", "2026-11-01"), showRow(12, "Cartoon", "2026-11-09", genres: [16], country: ["US"])])
        XCTAssertEqual(items.map(\.id), ["tmdb:tv:11", "tmdb:movie:2", "tmdb:tv:10", "tmdb:tv:12", "tmdb:movie:1"], "A title without a name or date is skipped, a repeat is dropped and a day keeps its order")
        XCTAssertEqual(items.map(\.isAnime), [false, true, true, false, false], "Animation that is Japanese counts as anime")
        let late = items[4]
        XCTAssertEqual(late.name, "Late"); XCTAssertEqual(late.poster, "https://image.tmdb.org/t/p/w342/p1.jpg"); XCTAssertEqual(late.background, "https://image.tmdb.org/t/p/w780/b1.jpg")
        XCTAssertEqual(late.releaseDate, "2026-11-20"); XCTAssertEqual(late.overview, "About Late"); XCTAssertEqual(late.voteAverage, 7.5); XCTAssertTrue(late.isMovie)
        XCTAssertNil(items[0].background, "A null backdrop stays empty"); XCTAssertFalse(items[0].isMovie)
        XCTAssertTrue(CalendarSources.inRange(movieRow(9, "x", "2026-11-30"), start: "2026-11-01", end: "2026-11-30"))
        XCTAssertFalse(CalendarSources.inRange(movieRow(9, "x", "2026-12-01"), start: "2026-11-01", end: "2026-11-30"))
        XCTAssertFalse(CalendarSources.inRange(movieRow(9, "x", ""), start: "2026-11-01", end: "2026-11-30"))
    }

    func testAllUpcomingAsksTMDBFiveTimesAndKeepsUpcomingMoviesInTheMonth() async {
        let log = StringLog()
        let fetcher = CalendarFetcher(json: { url in
            let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            let page = items.first { $0.name == "page" }?.value ?? "", region = items.first { $0.name == "region" }?.value ?? "-"
            log.add("\(url.path)|\(page)|\(region)")
            func rows(_ values: [JSONValue]) -> JSONValue { .object(["results": .array(values)]) }
            switch (url.path, page) {
            case ("/3/discover/movie", "1"): return rows([movieRow(1, "Late", "2026-11-20")])
            case ("/3/discover/movie", "2"): return rows([movieRow(2, "Early", "2026-11-05")])
            case ("/3/movie/upcoming", _): return rows([movieRow(5, "Inside", "2026-11-15"), movieRow(6, "Next month", "2026-12-02")])
            case ("/3/discover/tv", "1"): return rows([showRow(10, "Show A", "2026-11-12")])
            default: return rows([showRow(11, "Show B", "2026-11-03")])
            }
        }, calendar: utc)
        let items = await fetcher.allUpcoming(key: "k", region: "ES", year: 2026, month: 11)
        XCTAssertEqual(items.map(\.id), ["tmdb:tv:11", "tmdb:movie:2", "tmdb:tv:10", "tmdb:movie:5", "tmdb:movie:1"])
        XCTAssertEqual(Set(log.entries), ["/3/discover/movie|1|ES", "/3/discover/movie|2|ES", "/3/movie/upcoming|1|ES", "/3/discover/tv|1|-", "/3/discover/tv|2|-"])
        XCTAssertEqual(log.entries.count, 5)

        let noKey = StringLog()
        let silent = CalendarFetcher(json: { url in noKey.add(url.path); return nil }, calendar: utc)
        let none = await silent.allUpcoming(key: "", region: "ES", year: 2026, month: 11)
        XCTAssertTrue(none.isEmpty); XCTAssertTrue(noKey.entries.isEmpty, "Without a TMDB key nothing is asked")
        let failed = await silent.allUpcoming(key: "k", region: "ES", year: 2026, month: 11)
        XCTAssertTrue(failed.isEmpty, "Answers that fail leave an empty month")
    }

    private func meta(_ id: String, kind: String, poster: String?, genres: [String] = [], rating: String? = nil, description: String? = nil, videos: [Episode] = []) -> Media {
        var media = Media(id: id, type: kind, name: id)
        media.poster = poster; media.background = poster.map { $0 + ".bg" }; media.genres = genres; media.imdbRating = rating; media.description = description; media.videos = videos
        return media
    }

    func testMyTraktJoinsEpisodesAndMoviesWithPostersForTheMonth() async throws {
        let shows = JSONValue.array([
            .object(["first_aired": .string("2026-11-09T01:00:00.000Z"), "show": .object(["title": .string("Alpha"), "ids": .object(["imdb": .string("tt100"), "tmdb": .integer(1)])]),
                     "episode": .object(["season": .integer(2), "number": .integer(3), "title": .string("Pilot")])]),
            .object(["first_aired": .string("2026-11-09T03:00:00.000Z"), "show": .object(["title": .string("Beta"), "ids": .object(["tmdb": .integer(55)])]),
                     "episode": .object(["season": .integer(1), "number": .integer(1), "title": .string("")])]),
            .object(["first_aired": .string("2026-12-01T00:00:00.000Z"), "show": .object(["title": .string("Gamma"), "ids": .object(["imdb": .string("tt999")])]),
                     "episode": .object(["season": .integer(1), "number": .integer(1)])])])
        let movies = JSONValue.array([.object(["released": .string("2026-11-20"), "movie": .object(["title": .string("Film"), "ids": .object(["imdb": .string("tt200")])])])])
        let thumb = Episode(id: "tt100:2:3", season: 2, episode: 3, name: nil, title: nil, thumbnail: "thumb.jpg", overview: nil, released: nil, imdbID: nil, imdbSeason: nil, imdbEpisode: nil)
        let metas = ["tt100": meta("tt100", kind: "series", poster: "https://p/alpha.jpg", genres: ["Animation", "Drama"], rating: "8.5", description: "Alpha plot", videos: [thumb]),
                     "tt200": meta("tt200", kind: "movie", poster: "https://p/film.jpg", genres: ["Action"])]
        let calls = StringLog(), lookups = StringLog()
        let fetcher = CalendarFetcher(mine: { endpoint in
            calls.add(endpoint.path)
            switch endpoint {
            case .calendarShows: return shows
            case .calendarMovies: return movies
            default: return nil
            }
        }, cinemeta: { kind, id in lookups.add("\(kind):\(id)"); return metas[id] }, calendar: utc)
        let now = Date(timeIntervalSince1970: epoch("2026-11-07T12:00:00Z"))
        let items = await fetcher.myTrakt(year: 2026, month: 11, now: now)
        XCTAssertEqual(Set(calls.entries), ["/calendars/my/shows/2026-11-07/31", "/calendars/my/movies/2026-11-07/31"])
        XCTAssertEqual(Set(lookups.entries), ["series:tt100", "movie:tt200"], "Only titles of the month with an IMDb id are looked up")
        XCTAssertEqual(items.map(\.id), ["tt100:2:3", "tmdb:tv:55:1:1", "tt200"])
        let alpha = items[0]
        XCTAssertEqual(alpha.name, "Alpha S02E03: Pilot"); XCTAssertEqual(alpha.poster, "https://p/alpha.jpg"); XCTAssertTrue(alpha.isAnime, "Animation counts as anime")
        XCTAssertEqual(alpha.voteAverage, 8.5); XCTAssertEqual(alpha.overview, "Alpha plot"); XCTAssertEqual(alpha.imdbID, "tt100")
        XCTAssertEqual(alpha.releaseDate, "2026-11-09"); XCTAssertEqual(alpha.releaseTime, "1:00 AM"); XCTAssertEqual(try XCTUnwrap(alpha.releaseAtMs), epoch("2026-11-09T01:00:00Z") * 1_000)
        let beta = items[1]
        XCTAssertEqual(beta.name, "Beta S01E01", "An empty episode title adds nothing"); XCTAssertNil(beta.poster); XCTAssertFalse(beta.isAnime); XCTAssertEqual(beta.baseID, "tmdb:tv:55")
        XCTAssertEqual(beta.releaseTime, "3:00 AM")
        let film = items[2]
        XCTAssertTrue(film.isMovie); XCTAssertEqual(film.poster, "https://p/film.jpg"); XCTAssertEqual(film.releaseDate, "2026-11-20"); XCTAssertNil(film.releaseTime, "A plain day has no hour")

        // A poster missing from the title falls back to the episode's picture.
        let bare = ["tt100": meta("tt100", kind: "series", poster: nil, videos: [thumb])]
        let fallback = CalendarSources.traktItems(CalendarSources.traktEpisodes(shows, calendar: utc), year: 2026, month: 11, metas: bare)
        XCTAssertEqual(fallback.first?.poster, "thumb.jpg")
    }

    func testMyTraktLooksAtMostSixMonthsAheadAndNeverBack() async {
        let calls = StringLog()
        let fetcher = CalendarFetcher(mine: { endpoint in calls.add(endpoint.path); return .array([]) }, calendar: utc)
        let now = Date(timeIntervalSince1970: epoch("2026-11-07T12:00:00Z"))
        let past = await fetcher.myTrakt(year: 2026, month: 10, now: now)
        let far = await fetcher.myTrakt(year: 2027, month: 6, now: now)
        XCTAssertTrue(past.isEmpty); XCTAssertTrue(far.isEmpty); XCTAssertTrue(calls.entries.isEmpty, "Past months and dates beyond six months send nothing")
        _ = await fetcher.myTrakt(year: 2027, month: 5, now: now)
        XCTAssertEqual(Set(calls.entries), ["/calendars/my/shows/2026-11-07/217", "/calendars/my/movies/2026-11-07/217"], "Six months ahead asks for 7 x 31 days")
    }

    func testTraktEndpointsAreCheckedBeforeTheyAreSent() throws {
        XCTAssertEqual(TraktHomeEndpoint.calendarShows("2026-11-07", 31).path, "/calendars/my/shows/2026-11-07/31")
        XCTAssertEqual(TraktHomeEndpoint.calendarMovies("2026-11-07", 217).path, "/calendars/my/movies/2026-11-07/217")
        let request = try TraktEndpoint.home(.calendarShows("2026-11-07", 31)).request(token: "owned-access")
        XCTAssertEqual(request.url?.absoluteString, "https://api.trakt.tv/calendars/my/shows/2026-11-07/31")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer owned-access")
        XCTAssertThrowsError(try TraktEndpoint.home(.calendarMovies("2026-11-07/../x", 31)).request(token: "owned-access"))
        XCTAssertThrowsError(try TraktEndpoint.home(.calendarShows("2026-11-07", 0)).request(token: "owned-access"))
        XCTAssertThrowsError(try TraktEndpoint.home(.calendarShows("2026-11-07", 401)).request(token: "owned-access"))
        XCTAssertThrowsError(try TraktEndpoint.home(.calendarShows("2026-11-07", 31)).request(), "The account's calendar needs a token")
    }

    func testAnticipatedListsTitlesDatedInTheMonthWithPremieresFirst() async {
        let calls = StringLog()
        let shows = JSONValue.array([
            .object(["show": .object(["title": .string("Show One"), "first_aired": .string("2026-11-14T00:00:00.000Z"), "overview": .string("Plot"), "ids": .object(["imdb": .string("tt300")])])]),
            .object(["show": .object(["title": .string("Undated"), "ids": .object(["imdb": .string("tt301")])])]),
            .object(["show": .object(["title": .string("Last month"), "first_aired": .string("2026-10-30T00:00:00.000Z"), "ids": .object(["imdb": .string("tt302")])])])])
        let movies = JSONValue.array([.object(["movie": .object(["title": .string("Movie One"), "released": .string("2026-11-14"), "overview": .string("M plot"), "ids": .object(["tmdb": .integer(77)])])])])
        let metas = ["tt300": meta("tt300", kind: "series", poster: "https://p/one.jpg", rating: "7.1", description: "Meta plot")]
        let fetcher = CalendarFetcher(trakt: { path, query in
            calls.add(path + "?" + query.map { "\($0.0)=\($0.1)" }.joined(separator: "&"))
            return path.hasPrefix("/shows") ? shows : movies
        }, cinemeta: { _, id in metas[id] }, calendar: utc)
        let items = await fetcher.anticipated(year: 2026, month: 11)
        XCTAssertEqual(Set(calls.entries), ["/shows/anticipated?extended=full&limit=100", "/movies/anticipated?extended=full&limit=100"])
        XCTAssertEqual(items.map(\.id), ["tt300:premiere", "tmdb:movie:77"])
        XCTAssertEqual(items[0].name, "Show One (premiere)"); XCTAssertEqual(items[0].baseName, "Show One"); XCTAssertEqual(items[0].poster, "https://p/one.jpg")
        XCTAssertEqual(items[0].overview, "Meta plot", "Cinemeta's description wins over Trakt's"); XCTAssertEqual(items[0].voteAverage, 7.1); XCTAssertFalse(items[0].isAnime)
        XCTAssertEqual(items[1].name, "Movie One"); XCTAssertEqual(items[1].overview, "M plot", "Without Cinemeta the Trakt overview stays"); XCTAssertTrue(items[1].isMovie)
        XCTAssertNil(items[1].releaseTime)
    }

    func testAiringEpisodesBecomeAnimeItemsAndSkipWhatDesktopSkips() {
        let at = epoch("2026-11-10T15:30:00Z")
        let items = CalendarSources.airingItems([
            airing(1, mal: 100, episode: 5, at: at, english: " Show A "),
            airing(2, mal: nil, episode: 1, at: at + 60),
            airing(3, mal: 300, episode: 2, at: at, adult: true),
            airing(4, mal: 400, episode: 2, at: at, format: "MOVIE"),
            airing(5, mal: 500, episode: nil, at: at),
            airing(6, mal: 600, episode: 1, at: at, type: "MANGA"),
            airing(1, mal: 100, episode: 5, at: at + 5, english: "Show A"),
            .object(["airingAt": .integer(Int64(at)), "episode": .integer(1), "media": .null])], calendar: utc)
        XCTAssertEqual(items.map(\.id), ["mal:100:1:5", "anilist:2:1:1"])
        let first = items[0]
        XCTAssertEqual(first.name, "Show A S1E05"); XCTAssertEqual(first.poster, "l.jpg"); XCTAssertEqual(first.background, "b.jpg"); XCTAssertTrue(first.isAnime); XCTAssertFalse(first.isMovie)
        XCTAssertEqual(first.overview, "Plot line two"); XCTAssertEqual(first.voteAverage, 8.2, accuracy: 0.0001)
        XCTAssertEqual(first.releaseDate, "2026-11-10"); XCTAssertEqual(first.releaseTime, "3:30 PM"); XCTAssertEqual(first.releaseAtMs, at * 1_000)
        XCTAssertEqual(items[1].name, "Romaji S1E01", "Without an English title the romaji one is used")
        XCTAssertEqual(first.baseID, "mal:100"); XCTAssertEqual(CalendarSources.stripHTML("A<br/>B  <b>C</b>"), "A B C")
    }

    func testAnimeScheduleIsReadThreePagesAtATimeUpToTenPages() async {
        let start = Int64(utc.date(from: DateComponents(year: 2026, month: 11, day: 1))!.timeIntervalSince1970)
        let end = Int64(utc.date(from: DateComponents(year: 2026, month: 12, day: 1))!.timeIntervalSince1970)
        let at = epoch("2026-11-10T15:30:00Z")
        func page(_ number: Int, more: Bool?) -> JSONValue {
            var info: [String: JSONValue] = [:]
            if let more { info["hasNextPage"] = .bool(more) }
            return .object(["Page": .object(["airingSchedules": .array([airing(number, mal: number, episode: number, at: at)]), "pageInfo": .object(info)])])
        }

        let short = StringLog()
        let stopsEarly = CalendarFetcher(aniList: { query, variables in
            XCTAssertEqual(query, CalendarSources.airingQuery); XCTAssertEqual(variables["start"], JSONValue.integer(start)); XCTAssertEqual(variables["end"], JSONValue.integer(end))
            let number = variables["page"]?.integer ?? 0
            short.add(String(number))
            return page(number, more: number != 2)
        }, calendar: utc)
        let found = await stopsEarly.animeAiring(year: 2026, month: 11)
        XCTAssertEqual(Set(short.entries), ["1", "2", "3"], "The first three pages go out together and nothing after the page that says it is the last")
        XCTAssertEqual(found.map(\.id), ["mal:1:1:1", "mal:2:1:2", "mal:3:1:3"])

        let endless = StringLog()
        let capped = CalendarFetcher(aniList: { _, variables in
            let number = variables["page"]?.integer ?? 0
            endless.add(String(number))
            return page(number, more: true)
        }, calendar: utc)
        let many = await capped.animeAiring(year: 2026, month: 11)
        XCTAssertEqual(Set(endless.entries), Set((1...10).map(String.init)), "Ten pages at most"); XCTAssertEqual(endless.entries.count, 10); XCTAssertEqual(many.count, 10)

        let guessed = StringLog()
        let silent = CalendarFetcher(aniList: { _, variables in
            let number = variables["page"]?.integer ?? 0
            guessed.add(String(number))
            return page(number, more: nil)
        }, calendar: utc)
        let guess = await silent.animeAiring(year: 2026, month: 11)
        XCTAssertEqual(Set(guessed.entries), ["1", "2", "3"], "A reply without paging info counts as the last page when it holds fewer than 50 rows"); XCTAssertEqual(guess.count, 3)

        let failing = CalendarFetcher(aniList: { _, _ in throw HarborError(code: "network") }, calendar: utc)
        let nothing = await failing.animeAiring(year: 2026, month: 11)
        XCTAssertTrue(nothing.isEmpty)
    }

    func testSimklCalendarJoinsEachAiringWithItsTitleAndSkipsRowsDesktopSkips() {
        let metadata: [String: JSONValue] = [
            "10": simklShow("Show X", poster: "ab/cd", rating: 7.9, ids: ["imdb": .string("tt1"), "tmdb": .string("55"), "mal": .integer(7)]),
            "11": simklShow("Film", ids: ["tmdb": .integer(99)]),
            "12": simklShow("Anime Y", ids: ["mal": .integer(321)]),
            "13": simklShow("   "),
            "14": simklShow("No date"),
            "15": simklShow("Zero ids", ids: ["tmdb": .integer(0), "imdb": .string("")])]
        let entries = [simklEntry(10, "2026-11-12T14:00:00Z", season: 1, episode: 3), simklEntry(11, "2026-11-20"), simklEntry(12, "2026-11-05T00:00:00Z", season: 2, episode: 11),
                       simklEntry(13, "2026-11-06"), simklEntry(14, "not a date"), simklEntry(99, "2026-11-07"), simklEntry(0, "2026-11-07"),
                       simklEntry(10, "2026-11-30T00:00:00Z", season: 1, episode: 4), simklEntry(15, "2026-11-08")]
        let rows = CalendarSources.simklCalendar(simklPayload(entries, metadata))
        XCTAssertEqual(rows.map(\.title), ["Show X", "Film", "Anime Y", "Show X", "Zero ids"], "A blank title, a bad date, a missing title and a zero id are skipped; one title may air twice")
        XCTAssertEqual(rows[0].tmdb, "55"); XCTAssertEqual(rows[1].tmdb, "99", "A numeric TMDB id is read like a text one"); XCTAssertEqual(rows[0].mal, "7"); XCTAssertEqual(rows[0].rating, 7.9)
        XCTAssertNil(rows[4].tmdb, "A zero id is none"); XCTAssertNil(rows[4].imdb, "An empty IMDb id is none")
        XCTAssertTrue(CalendarSources.simklCalendar(.object(["calendar": .array(entries)])).isEmpty, "A file without metadata is empty")
        XCTAssertTrue(CalendarSources.simklCalendar(nil).isEmpty); XCTAssertTrue(CalendarSources.simklCalendar(.array([])).isEmpty)

        let shows = CalendarSources.simklItems([rows[0], rows[4]], movie: false, anime: false)
        XCTAssertEqual(shows[0].id, "tt1"); XCTAssertEqual(shows[0].name, "Show X S01E03"); XCTAssertEqual(shows[0].poster, "https://wsrv.nl/?url=https://simkl.in/posters/ab/cd_m.webp&q=90")
        XCTAssertEqual(shows[0].voteAverage, 7.9); XCTAssertEqual(shows[0].releaseDate, "2026-11-12"); XCTAssertEqual(shows[0].imdbID, "tt1"); XCTAssertFalse(shows[0].isAnime); XCTAssertFalse(shows[0].isMovie)
        XCTAssertEqual(shows[1].id, "simkl:15", "Without any known id the title keeps Simkl's own"); XCTAssertEqual(shows[1].name, "Zero ids"); XCTAssertNil(shows[1].poster)
        let film = CalendarSources.simklItems([rows[1]], movie: true, anime: false)[0]
        XCTAssertEqual(film.id, "tmdb:movie:99"); XCTAssertTrue(film.isMovie); XCTAssertEqual(film.name, "Film")
        let anime = CalendarSources.simklItems([rows[2]], movie: false, anime: true)[0]
        XCTAssertEqual(anime.id, "mal:321", "An anime Simkl knows only by MAL opens through it"); XCTAssertEqual(anime.name, "Anime Y S02E11"); XCTAssertTrue(anime.isAnime)
        XCTAssertEqual(CalendarSources.simklItems([rows[2]], movie: false, anime: false)[0].id, "simkl:12", "Only anime use the MAL id")
    }

    func testSimklPremieresAskThreeCatalogsForTheMonthAndCombineThemByDate() async throws {
        let log = StringLog()
        let tvPayload = simklPayload([simklEntry(1, "2026-11-12T10:00:00Z", season: 1, episode: 1)], ["1": simklShow("Show", ids: ["imdb": .string("tt1")])])
        let animePayload = simklPayload([simklEntry(2, "2026-11-03T10:00:00Z", season: 1, episode: 2)], ["2": simklShow("Anime", ids: ["mal": .integer(9)])])
        let moviePayload = simklPayload([simklEntry(3, "2026-11-20")], ["3": simklShow("Film", ids: ["tmdb": .string("77")])])
        let fetcher = CalendarFetcher(json: { url in
            log.add(url.path)
            switch url.lastPathComponent {
            case "tv.json": return tvPayload
            case "anime.json": return animePayload
            case "movie_release.json": return moviePayload
            default: return nil
            }
        }, calendar: utc)
        let items = await fetcher.simklPremieres(year: 2026, month: 11)
        XCTAssertEqual(Set(log.entries), ["/calendar/v2/2026/11/tv.json", "/calendar/v2/2026/11/anime.json", "/calendar/v2/2026/11/movie_release.json"])
        XCTAssertEqual(items.map(\.id), ["mal:9", "tt1", "tmdb:movie:77"], "Sorted by day across the three catalogs")
        XCTAssertEqual(items.map(\.isAnime), [true, false, false]); XCTAssertEqual(items.map(\.isMovie), [false, false, true])
        let url = try XCTUnwrap(CalendarSources.simklURL(year: 2026, month: 11, catalog: "tv"))
        XCTAssertEqual(Dictionary(uniqueKeysWithValues: (URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []).map { ($0.name, $0.value ?? "") }),
                       ["client_id": CalendarSources.simklClientID, "app-name": "harbor", "app-version": "0.9.132"])
        XCTAssertEqual(url.host, "data.simkl.in"); XCTAssertNil(CalendarSources.simklURL(year: 2026, month: 11, catalog: "../x"))

        let down = CalendarFetcher(json: { _ in nil }, calendar: utc)
        let none = await down.simklPremieres(year: 2026, month: 11)
        XCTAssertTrue(none.isEmpty, "A catalog that cannot be read leaves its part empty")
    }

    func testTheDubScheduleListsDubbedEpisodesOfTheMonthAndKeepsTheLastGoodFeed() async {
        let at = "2026-11-10T15:30:00.000Z"
        func entry(_ id: Int, mal: Int?, episode: Int?, date: String, english: String = "", romaji: String = "", feedEnglish: String = "", adult: Bool = false, format: String = "TV") -> JSONValue {
            var title: [String: JSONValue] = [:]
            title["english"] = .string(english); title["romaji"] = .string(romaji)
            var cover: [String: JSONValue] = [:]
            cover["extraLarge"] = .string("x.jpg"); cover["medium"] = .string("m.jpg")
            var media: [String: JSONValue] = [:]
            media["id"] = .integer(Int64(id)); media["idMal"] = mal.map { JSONValue.integer(Int64($0)) } ?? JSONValue.null
            media["isAdult"] = .bool(adult); media["format"] = .string(format); media["title"] = .object(title); media["coverImage"] = .object(cover); media["bannerImage"] = .string("b.jpg")
            var row: [String: JSONValue] = [:]
            row["media"] = .object(["media": .object(media)]); row["episodeDate"] = .string(date); row["english"] = .string(feedEnglish)
            row["episodeNumber"] = episode.map { JSONValue.integer(Int64($0)) } ?? JSONValue.null
            return .object(row)
        }
        let rows = [entry(1, mal: 100, episode: 5, date: at, english: " Show A "), entry(2, mal: nil, episode: 1, date: "2026-11-02T10:00:00Z", romaji: "Romaji B"),
                    entry(3, mal: 300, episode: 2, date: at, adult: true), entry(4, mal: 400, episode: 2, date: at, format: "MOVIE"), entry(5, mal: 500, episode: nil, date: at),
                    entry(6, mal: 600, episode: 1, date: "2026-12-01T00:00:00Z"), entry(7, mal: 700, episode: 3, date: at, feedEnglish: "Feed title"),
                    entry(1, mal: 100, episode: 5, date: at, english: "Show A"), entry(8, mal: 800, episode: 1, date: at)]
        let items = CalendarSources.dubItems(rows, year: 2026, month: 11, calendar: utc)
        XCTAssertEqual(items.map(\.id), ["anilist:2:1:1", "mal:100:1:5", "mal:700:1:3", "mal:800:1:1"], "By day, a day keeping the feed order; adult, movies, undated, other months and repeats are left out")
        XCTAssertEqual(items.map(\.name), ["Romaji B S1E01", "Show A S1E05", "Feed title S1E03", "Untitled S1E01"])
        XCTAssertEqual(items[1].poster, "x.jpg", "The dub feed prefers the extra large cover"); XCTAssertEqual(items[1].background, "b.jpg"); XCTAssertTrue(items[1].isAnime)
        XCTAssertEqual(items[1].releaseTime, "3:30 PM"); XCTAssertEqual(items[1].releaseDate, "2026-11-10")

        let log = StringLog()
        let feed = AnimeDubFeed()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let first = await feed.entries(now: now) { url in log.add(url.absoluteString); return JSONValue.array(rows) }
        XCTAssertEqual(first.count, rows.count); XCTAssertEqual(log.entries, [AnimeDubFeed.url.absoluteString])
        _ = await feed.entries(now: now.addingTimeInterval(29 * 60)) { url in log.add(url.absoluteString); return JSONValue.array([]) }
        XCTAssertEqual(log.entries.count, 1, "The feed is kept for half an hour")
        let stale = await feed.entries(now: now.addingTimeInterval(31 * 60)) { url in log.add(url.absoluteString); return nil }
        XCTAssertEqual(stale.count, rows.count, "A failed read answers the last good feed"); XCTAssertEqual(log.entries.count, 2)
        let none = await AnimeDubFeed().entries(now: now) { _ in nil }
        XCTAssertTrue(none.isEmpty)

        let fetcher = CalendarFetcher(json: { _ in JSONValue.array(rows) }, calendar: utc, dubFeed: AnimeDubFeed())
        let viaFetcher = await fetcher.animeDub(year: 2026, month: 11, now: now)
        XCTAssertEqual(viaFetcher.count, 4)
        XCTAssertEqual(CalendarSources.emptyMonth(source: .anime, filter: "all", watchlistOnly: false, animeDub: true).heading, "No dubbed episodes this month")
        XCTAssertEqual(CalendarSources.emptyMonth(source: .anime, filter: "all", watchlistOnly: false, animeDub: true).message, "The dub schedule has no episodes releasing this month. Try a different month.")
    }

    func testSourcesFollowDesktopsSettingAndEmptyMonthTexts() {
        XCTAssertEqual(CalendarSource.allCases.map(\.rawValue), ["library", "all", "trakt", "anticipated", "simkl-anticipated", "anime"])
        XCTAssertEqual(CalendarSource.offered(traktConnected: true).map(\.rawValue), ["library", "all", "trakt", "anticipated", "anime"])
        XCTAssertEqual(CalendarSource.offered(traktConnected: false).map(\.rawValue), ["library", "all", "anticipated", "anime"], "My Trakt waits for a Trakt account")
        XCTAssertEqual(CalendarSource.offered(traktConnected: true, simklConnected: true).map(\.rawValue), ["library", "all", "trakt", "anticipated", "simkl-anticipated", "anime"], "Simkl premieres wait for a Simkl account")
        XCTAssertEqual(CalendarSource.simklAnticipated.label, "Simkl premieres")
        XCTAssertEqual(CalendarSources.emptyMonth(source: .simklAnticipated, filter: "all", watchlistOnly: false).heading, "No Simkl premieres this month")
        XCTAssertEqual(CalendarSource.all.label, "All upcoming"); XCTAssertEqual(CalendarSource.anticipated.hint, "The most anticipated upcoming releases on Trakt")

        XCTAssertEqual(CalendarSources.emptyMonth(source: .trakt, filter: "all", watchlistOnly: false).heading, "Nothing on Trakt this month")
        XCTAssertEqual(CalendarSources.emptyMonth(source: .anime, filter: "all", watchlistOnly: false).heading, "Nothing airing this month")
        XCTAssertEqual(CalendarSources.emptyMonth(source: .all, filter: "all", watchlistOnly: false).message, "TMDB has no notable releases for this month and region.")
        XCTAssertEqual(CalendarSources.emptyMonth(source: .all, filter: "movie", watchlistOnly: false).variables, ["kind": "movies"])
        XCTAssertEqual(CalendarSources.emptyMonth(source: .all, filter: "series", watchlistOnly: false).variables, ["kind": "TV"])
        XCTAssertEqual(CalendarSources.emptyMonth(source: .all, filter: "movie", watchlistOnly: true).message, "Nothing from your library lands this month. Toggle Watchlist off to see all releases.")

        XCTAssertEqual(CalendarSources.normalizeName("Marvel’s Agent's  Carter!"), "marvels agents carter")
        XCTAssertEqual(CalendarSources.libraryKey(name: "The Office", isSeries: true), "the office::tv"); XCTAssertEqual(CalendarSources.libraryKey(name: "The Office", isSeries: false), "the office::movie")
    }

    func testReleaseEventsTellTheirKindForTheTypeFilters() {
        let date = Date(timeIntervalSince1970: 0)
        XCTAssertEqual(ReleaseEvent(media: Media(id: "tt1", type: "movie", name: "M"), episode: nil, date: date).kind, "movie")
        XCTAssertEqual(ReleaseEvent(media: Media(id: "tt2", type: "series", name: "S"), episode: nil, date: date).kind, "series")
        XCTAssertEqual(ReleaseEvent(media: Media(id: "kitsu:1", type: "anime", name: "A"), episode: nil, date: date).kind, "anime")
        XCTAssertEqual(ReleaseEvent(media: Media(id: "tt3", type: "series", name: "Cartoon"), episode: nil, date: date, isAnime: true).kind, "anime")
        let first = ReleaseEvent(media: Media(id: "tt4", type: "series", name: "S"), episode: nil, date: date, label: "S S01E01")
        let second = ReleaseEvent(media: Media(id: "tt4", type: "series", name: "S"), episode: nil, date: date, label: "S S01E02")
        XCTAssertNotEqual(first.id, second.id, "Two episodes of one show on a day stay apart")
    }
}

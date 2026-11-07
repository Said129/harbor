import XCTest
@testable import Harbor

/// Desktop's Simkl home rails (`lib/simkl/home-rails.ts`, `home-rails/up-next.ts`, `home-rails/cdn.ts`, `calendar-data.ts`):
/// grouping, gating, Up Next window and matching, trending parsing and settings defaults. Canned JSON only; no request is sent.
final class SimklHomeRailsTests: XCTestCase {
    private func json(_ text: String) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))
    }

    private func listItem(_ text: String, kind: SimklMediaKind) throws -> SimklListItem {
        try XCTUnwrap(SimklListItem.parse(try json(text), kind: kind))
    }

    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    /// 2026-11-07 12:00 UTC: today is 2026-11-07, and Up Next runs until 2026-12-07.
    private var now: Date { SimklHomeRails.parseDate("2026-11-07T12:00:00Z")! }

    private var library: [SimklListItem] {
        get throws {
            [
                try listItem(#"{"status":"watching","added_to_watchlist_at":"2026-10-01T00:00:00Z","show":{"title":"Severance","year":2022,"ids":{"simkl":1,"imdb":"tt11280740","tmdb":95396}}}"#, kind: .show),
                try listItem(#"{"status":"plantowatch","added_to_watchlist_at":"2026-10-03T00:00:00Z","show":{"title":"The Bear","year":2022,"ids":{"simkl":2,"imdb":"tt14452776","tmdb":136315}}}"#, kind: .show),
                try listItem(#"{"status":"plantowatch","added_to_watchlist_at":"2026-10-02T00:00:00Z","movie":{"title":"Dune","year":2021,"ids":{"simkl":10,"imdb":"tt1160419","tmdb":438631}}}"#, kind: .movie),
                try listItem(#"{"status":"watching","anime":{"title":"Frieren","year":2023,"ids":{"simkl":20,"mal":52991,"anidb":17617}}}"#, kind: .anime),
                try listItem(#"{"status":"completed","show":{"title":"Old Show","year":2010,"ids":{"simkl":3,"imdb":"tt0000003"}}}"#, kind: .show),
            ]
        }
    }

    private func settings(homeRails: Bool = true, upNext: Bool = false, trending: Bool = false) -> SimklHomeRails.Settings {
        var value = SimklHomeRails.Settings()
        value.homeRails = homeRails
        value.upNext = upNext
        value.trending = trending
        return value
    }

    // MARK: Settings

    func testSettingsDefaultsMatchDesktopWhenNothingIsStored() {
        let suite = "SimklHomeRailsTests.defaults." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let value = SimklHomeRails.Settings(defaults: defaults)
        XCTAssertFalse(value.homeRails)
        XCTAssertFalse(value.upNext)
        XCTAssertFalse(value.trending)
        XCTAssertTrue(value.moviesPlanToWatch)
        XCTAssertTrue(value.showsWatching)
        XCTAssertTrue(value.showsPlanToWatch)
        XCTAssertEqual(value.animeTitleLanguage, .english)
    }

    func testStoredSettingsAreReadAndInvalidLanguageFallsBack() {
        let suite = "SimklHomeRailsTests.stored." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: SimklHomeRails.Keys.homeRails)
        defaults.set(false, forKey: SimklHomeRails.Keys.showsWatching)
        defaults.set("romaji", forKey: SimklHomeRails.Keys.animeTitleLanguage)
        var value = SimklHomeRails.Settings(defaults: defaults)
        XCTAssertTrue(value.homeRails)
        XCTAssertFalse(value.showsWatching)
        XCTAssertEqual(value.animeTitleLanguage, .romaji)
        defaults.set("klingon", forKey: SimklHomeRails.Keys.animeTitleLanguage)
        value = SimklHomeRails.Settings(defaults: defaults)
        XCTAssertEqual(value.animeTitleLanguage, .english)
    }

    func testRowKeysAndKeyNamesFollowDesktop() {
        XCTAssertEqual(SimklHomeRails.Key.allCases.map(\.rawValue), [
            "simkl-watching-shows", "simkl-plantowatch-movies", "simkl-plantowatch-shows", "simkl-upcoming", "simkl-trending",
        ])
        XCTAssertEqual(SimklHomeRails.Keys.homeRails, "simklHomeRailsEnabled")
        XCTAssertEqual(SimklHomeRails.Keys.animeTitleLanguage, "simklAnimeTitleLanguage")
        XCTAssertEqual(SimklHomeRails.title(.upNext), DesktopInterfaceText.value("Up Next on Simkl"))
    }

    // MARK: Library rows

    func testLibraryRowsGroupLikeDesktopAndDropAnimeAndFinishedTitles() throws {
        let sources = SimklHomeRails.sources(library: try library, airings: [], trending: [], settings: settings(), now: now, calendar: utc)
        XCTAssertEqual(sources.map(\.key), [.watchingShows, .planMovies, .planShows])
        XCTAssertEqual(sources.map(\.kind), ["series", "movie", "series"])
        XCTAssertEqual(sources[0].items.map(\.title), ["Severance"])
        XCTAssertEqual(sources[1].items.map(\.title), ["Dune"])
        XCTAssertEqual(sources[2].items.map(\.title), ["The Bear"])
        XCTAssertEqual(sources[0].items[0].ids.json["imdb"], .string("tt11280740"))
    }

    func testMasterSwitchOffProducesNoRows() throws {
        let off = settings(homeRails: false, upNext: true, trending: true)
        let sources = SimklHomeRails.sources(library: try library, airings: [], trending: [], settings: off, now: now, calendar: utc)
        XCTAssertTrue(sources.isEmpty)
    }

    func testGranularTogglesGateTheirRows() throws {
        var value = settings()
        value.showsWatching = false
        value.moviesPlanToWatch = false
        let sources = SimklHomeRails.sources(library: try library, airings: [], trending: [], settings: value, now: now, calendar: utc)
        XCTAssertEqual(sources.map(\.key), [.planShows])
    }

    func testRowWithMoreThanOnePageReportsHasMore() throws {
        let many = try (1...25).map { try listItem(#"{"status":"watching","show":{"title":"Show \#($0)","ids":{"simkl":\#($0),"tmdb":\#($0)}}}"#, kind: .show) }
        let sources = SimklHomeRails.sources(library: many, airings: [], trending: [], settings: settings(), now: now, calendar: utc)
        let watching = try XCTUnwrap(sources.first { $0.key == .watchingShows })
        XCTAssertEqual(watching.items.count, 25)
        XCTAssertTrue(watching.hasMore)
        XCTAssertEqual(Array(watching.items.prefix(SimklHomeRails.perRail)).count, 24)
    }

    func testAnimeIsIdentifiedByMalAniDBOrKitsuIds() {
        XCTAssertTrue(SimklHomeRails.isAnime(SimklIdentifiers(.object(["mal": .integer(1)]))))
        XCTAssertTrue(SimklHomeRails.isAnime(SimklIdentifiers(.object(["anidb": .integer(2)]))))
        XCTAssertTrue(SimklHomeRails.isAnime(SimklIdentifiers(.object(["kitsu": .integer(3)]))))
        XCTAssertFalse(SimklHomeRails.isAnime(SimklIdentifiers(.object(["imdb": .string("tt0000001")]))))
    }

    func testHydratableKeepsOnlyImdbAndTmdb() {
        let item = SimklHomeRails.hydratable(SimklIdentifiers(.object(["mal": .integer(5), "tmdb": .integer(7)])), type: .show, title: "X", year: nil)
        XCTAssertEqual(item.ids.json, .object(["tmdb": .integer(7)]))
    }

    // MARK: Up Next

    private var calendarJSON: JSONValue {
        get throws {
            try json(#"""
            {
              "calendar": [
                {"simkl_id": 1, "date": "2026-11-08T20:00:00Z"},
                {"simkl_id": 2, "date": "2026-11-06T20:00:00Z"},
                {"simkl_id": 1, "date": "2026-11-15T20:00:00Z"},
                {"simkl_id": 2, "date": "2026-11-09T20:00:00Z"},
                {"simkl_id": 3, "date": "2026-11-10T20:00:00Z"},
                {"simkl_id": 99, "date": "2026-11-10T20:00:00Z"},
                {"simkl_id": 2, "date": "2026-12-20T20:00:00Z"}
              ],
              "metadata": {
                "1": {"title": "Severance", "ids": {"imdb": "tt11280740", "tmdb": "95396"}},
                "2": {"title": "The Bear", "ids": {"imdb": "tt14452776", "tmdb": "136315"}},
                "3": {"title": "Old Show", "ids": {"imdb": "tt0000003"}}
              }
            }
            """#)
        }
    }

    func testCalendarParserJoinsMetadataAndSkipsUnknownTitles() throws {
        let airings = SimklHomeRails.parseAirings(try calendarJSON)
        XCTAssertEqual(airings.count, 6)
        XCTAssertEqual(airings[0].ids.values["simkl"], .integer(1))
        XCTAssertEqual(airings[0].ids.values["imdb"], .string("tt11280740"))
    }

    func testUpNextKeepsWindowOrderAndOncePerWatchingTitle() throws {
        let airings = SimklHomeRails.parseAirings(try calendarJSON)
        let items = SimklHomeRails.upNext(airings: airings, library: try library, now: now, calendar: utc)
        // Severance (Nov 8) then The Bear (Nov 9). The Nov 15 repeat, the Nov 6 past airing, the Dec 20 airing,
        // the completed Old Show and the unknown id 99 are all dropped.
        XCTAssertEqual(items.map(\.title), ["Severance", "The Bear"])
        XCTAssertEqual(items.map(\.type), [.show, .show])
    }

    // MARK: Trending

    private var trendingJSON: JSONValue {
        get throws {
            try json(#"""
            {
              "tv": [
                {"title": "Show A", "release_date": "2026-01-02", "ids": {"simkl_id": 101, "imdb": "tt0000101", "tmdb": "5001"}},
                {"title": "Show B", "release_date": "03/04/2025", "ids": {"simkl_id": 102, "imdb": "tt0000102", "tmdb": 5002}}
              ],
              "movies": [
                {"title": "Movie A", "release_date": "01/02/2026", "ids": {"simkl_id": 201, "imdb": "tt0000201", "tmdb": 6001}}
              ],
              "anime": [
                {"title": "Anime A", "anime_type": "movie", "release_date": "", "ids": {"simkl_id": 301, "mal": 40001, "kitsu": "1234"}},
                {"title": "Anime B", "anime_type": "tv", "release_date": "2024-05-01", "ids": {"simkl_id": 302, "mal": 40002}}
              ]
            }
            """#)
        }
    }

    func testTrendingInterleavesBucketsAndReadsYearsAndKinds() throws {
        let entries = SimklHomeRails.parseTrending(try trendingJSON)
        XCTAssertEqual(entries.map(\.title), ["Show A", "Movie A", "Anime A", "Show B", "Anime B"])
        XCTAssertEqual(entries.map(\.isMovie), [false, true, true, false, false])
        // Desktop reads the last "/" segment, so the ISO date gives its leading year.
        XCTAssertEqual(entries.map(\.year), [2026, 2026, nil, 2025, 2024])
        XCTAssertEqual(entries[0].ids.values["tmdb"], .integer(5001))
        XCTAssertEqual(entries[2].ids.values["kitsu"], .integer(1234))
    }

    func testTrendingRailNeedsFourArtworksAndTakesKindFromFirstEntry() throws {
        let entries = SimklHomeRails.parseTrending(try trendingJSON)
        let sources = SimklHomeRails.sources(library: [], airings: [], trending: entries, settings: settings(trending: true), now: now, calendar: utc)
        let source = try XCTUnwrap(sources.first)
        XCTAssertEqual(source.key, .trending)
        XCTAssertEqual(source.kind, "series")
        XCTAssertEqual(source.items.count, 5)
        XCTAssertNil(SimklHomeRails.rail(source, metas: Self.media(3)))
        let rail = try XCTUnwrap(SimklHomeRails.rail(source, metas: Self.media(4)))
        XCTAssertEqual(rail.id, "simkl-trending")
        XCTAssertEqual(rail.title, DesktopInterfaceText.value("Simkl Trending Today"))

        let movieFirst = [SimklHomeRails.Trending(isMovie: true, title: "M", year: nil, ids: SimklIdentifiers(.object(["simkl": .integer(9)])))]
        let movieSource = SimklHomeRails.sources(library: [], airings: [], trending: movieFirst, settings: settings(trending: true), now: now, calendar: utc)
        XCTAssertEqual(movieSource.first?.kind, "movie")
    }

    func testOrdinaryRowNeedsOneArtwork() throws {
        let sources = SimklHomeRails.sources(library: try library, airings: [], trending: [], settings: settings(), now: now, calendar: utc)
        let watching = try XCTUnwrap(sources.first { $0.key == .watchingShows })
        XCTAssertNil(SimklHomeRails.rail(watching, metas: []))
        XCTAssertEqual(SimklHomeRails.rail(watching, metas: Self.media(1))?.kind, "series")
    }

    private static func media(_ count: Int) -> [Media] {
        (0..<count).map { Media(id: "tt\($0)", type: "series", name: "Title \($0)") }
    }
}

import XCTest
@testable import Harbor

@MainActor private final class DiscoverProfileSettingsMemory: ProfileSettingsPersistence {
    var state: ProfileSettingsState?
    func readProfileSettings() throws -> ProfileSettingsState? { state }
    func writeProfileSettings(_ value: ProfileSettingsState) throws { state = value }
}

/// The Discover helpers ported from Desktop 0.9.132 (seeded rows, genre rules, affinity ranking, premiere rail), checked without the network.
final class R24DiscoverTests: XCTestCase {
    func testMulberryMatchesDesktopKnownValues() {
        var generator = DiscoveryFeedRandom.Mulberry32(seed: 1)
        XCTAssertEqual(generator.next(), 0.6270739405881613, accuracy: 1e-12)
        XCTAssertEqual(generator.next(), 0.0027357211802154779, accuracy: 1e-12)
    }

    func testSeedMixingMatchesDesktop() {
        XCTAssertEqual(DiscoveryFeedRandom.hash("genre"), 1_986_820_544)
        XCTAssertEqual(DiscoveryFeedRandom.mixSeed(20_000, DiscoveryFeedRandom.hash("genre")), 611_294_688)
        var generator = DiscoveryFeedRandom.generator(base: 20_000, salt: "genre")
        XCTAssertEqual(generator.next(), 0.11564359022304416, accuracy: 1e-12)
    }

    func testDayIndexCountsUTCDays() {
        XCTAssertEqual(DiscoveryFeedRandom.dayIndex(Date(timeIntervalSince1970: 86_400 * 20_000 + 5)), 20_000)
        XCTAssertEqual(DiscoveryFeedRandom.dayIndex(Date(timeIntervalSince1970: 86_400 * 20_000 - 1)), 19_999)
    }

    func testNormalizedAffinityScalesByLargestAbsoluteWeight() {
        let weights = ["Drama": 4.0, "Horror": -2.0]
        XCTAssertEqual(DiscoveryDailyRows.normalizedAffinity(weights, key: "Drama"), 1, accuracy: 1e-12)
        XCTAssertEqual(DiscoveryDailyRows.normalizedAffinity(weights, key: "Horror"), 0)
        XCTAssertEqual(DiscoveryDailyRows.normalizedAffinity(weights, key: "Comedy"), 0)
        XCTAssertEqual(DiscoveryDailyRows.normalizedAffinity([:], key: "Drama"), 0)
    }

    func testWeightedPickDrawsEachValueOnce() {
        var generator = DiscoveryFeedRandom.Mulberry32(seed: 7)
        let picked = DiscoveryDailyRows.weightedPick(["a", "b", "c"], weight: { _ in 1 }, rng: &generator, count: 5)
        XCTAssertEqual(picked.count, 3)
        XCTAssertEqual(Set(picked), ["a", "b", "c"])
    }

    func testShuffleKeepsEveryValue() {
        var generator = DiscoveryFeedRandom.Mulberry32(seed: 99)
        let shuffled = DiscoveryDailyRows.shuffle(Array(1...10), rng: &generator)
        XCTAssertEqual(shuffled.sorted(), Array(1...10))
    }

    func testDailyOrderPinsAnchorsAndClosesWithARotatingAnchor() {
        let keys = ["row-a:x", "trending:_", "cult:_", "animated:_", "critically_loved:_", "row-b:x", "award_winning:_",
                    "documentaries:_", "hidden_gems_anchor:_", "row-c:x", "row-d:x"]
        let ordered = DiscoveryDailyRows.order(keys, key: { $0 }, base: 20_000, count: 14, recent: [])
        XCTAssertEqual(Array(ordered.prefix(3)), ["trending:_", "critically_loved:_", "award_winning:_"])
        XCTAssertTrue(DiscoveryDailyRows.rotatingAnchors.contains { ordered.last?.hasPrefix($0 + ":") == true })
        XCTAssertEqual(ordered.count, keys.count)
        XCTAssertEqual(Set(ordered), Set(keys))
    }

    func testDailyOrderIsStableForTheSameDay() {
        let keys = (1...12).map { "row-\($0):x" }
        let first = DiscoveryDailyRows.order(keys, key: { $0 }, base: 20_001, count: 8, recent: [])
        let second = DiscoveryDailyRows.order(keys, key: { $0 }, base: 20_001, count: 8, recent: [])
        XCTAssertEqual(first, second)
    }

    func testRecentlyShownRowsComeAfterFreshRows() {
        let keys = ["trending:_", "critically_loved:_", "row-a:x", "row-b:x", "row-c:x"]
        let ordered = DiscoveryDailyRows.order(keys, key: { $0 }, base: 20_000, count: 14, recent: ["row-a:x"])
        XCTAssertEqual(ordered.count, 5)
        XCTAssertEqual(ordered.last, "row-a:x")
        XCTAssertEqual(Array(ordered.prefix(2)), ["trending:_", "critically_loved:_"])
    }

    func testGenreTilesMatchDesktopOrderAndMovieGenres() {
        let names = DiscoveryGenreRules.tileNames
        XCTAssertEqual(names.count, 18)
        XCTAssertEqual(names.first, "Action")
        XCTAssertEqual(names.last, "Music")
        let movieNames = Set(CustomCalendar.movieGenres.map { $0.0 })
        XCTAssertTrue(names.allSatisfy { movieNames.contains($0) })
        XCTAssertEqual(Set(names).count, names.count)
    }

    func testEveryGenreTileHasAFilteredTMDBRouteAndCollagePalette() throws {
        for (name, id) in CustomCalendar.movieGenres {
            let rail = try XCTUnwrap(DiscoveryGenreRules.tmdbGenreRail(name))
            XCTAssertEqual(rail.path, "discover/movie")
            XCTAssertEqual(rail.kind, "movie")
            XCTAssertEqual(rail.parameters["with_genres"], String(id))
            XCTAssertNotNil(DiscoveryGenreRules.tilePalette[name])
        }
        XCTAssertNil(DiscoveryGenreRules.tmdbGenreRail("Unknown"))
    }

    func testMovieFloorKeepsRuntimeFloorUnlessOverridden() {
        let plain = DiscoveryGenreRules.movieFloor(genreID: 28, floor: ["sort_by": "popularity.desc"])
        XCTAssertEqual(plain["with_genres"], "28")
        XCTAssertEqual(plain["with_runtime.gte"], "70")
        XCTAssertEqual(plain["sort_by"], "popularity.desc")
        let overridden = DiscoveryGenreRules.movieFloor(genreID: 28, floor: ["with_runtime.gte": "40"])
        XCTAssertEqual(overridden["with_runtime.gte"], "40")
    }

    func testRelaxLoosensVotesAndAverage() {
        let relaxed = DiscoveryGenreRules.relax(["vote_count.gte": "1000", "vote_average.gte": "7.2"])
        XCTAssertEqual(relaxed["vote_count.gte"], "600")
        XCTAssertEqual(relaxed["vote_average.gte"], "6.8")
        XCTAssertEqual(DiscoveryGenreRules.relax(["vote_count.gte": "30"])["vote_count.gte"], "20")
        XCTAssertEqual(DiscoveryGenreRules.relax(["sort_by": "popularity.desc"]), ["sort_by": "popularity.desc"])
    }

    func testWeightedGenresReturnsDistinctMovieGenres() {
        var generator = DiscoveryFeedRandom.generator(base: 20_000, salt: "genre")
        let names = DiscoveryGenreRules.weightedGenres(affinity: ["Horror": 3], rng: &generator, count: 4)
        XCTAssertEqual(names.count, 4)
        XCTAssertEqual(Set(names).count, 4)
    }

    func testAffinityRankingOrdersByGenreAndDecade() {
        var affinity = DiscoveryPreferences.Affinity()
        affinity.genres = ["Drama": 2, "Horror": 1]
        affinity.decades = ["1990s": 1]
        var horror = Media(id: "tmdb:movie:1", type: "movie", name: "Horror")
        horror.genres = ["Horror"]; horror.releaseInfo = "2019"
        var drama = Media(id: "tmdb:movie:2", type: "movie", name: "Drama")
        drama.genres = ["Drama"]; drama.releaseInfo = "1995"
        var comedy = Media(id: "tmdb:movie:3", type: "movie", name: "Comedy")
        comedy.genres = ["Comedy"]; comedy.releaseInfo = "2020"
        var other = Media(id: "tmdb:movie:4", type: "movie", name: "Other")
        other.genres = ["Comedy"]; other.releaseInfo = "2021"
        let ranked = DiscoveryAffinityRules.ranked([comedy, horror, drama, other], affinity: affinity)
        XCTAssertEqual(ranked.map(\.name), ["Drama", "Horror", "Comedy", "Other"])
    }

    func testAffinityRankingKeepsOrderWithoutTaste() {
        var first = Media(id: "tmdb:movie:5", type: "movie", name: "First")
        first.genres = ["Drama"]
        var second = Media(id: "tmdb:movie:6", type: "movie", name: "Second")
        second.genres = ["Horror"]
        let ranked = DiscoveryAffinityRules.ranked([first, second], affinity: DiscoveryPreferences.Affinity())
        XCTAssertEqual(ranked.map(\.name), ["First", "Second"])
    }

    func testDecadeKeyFromReleaseYear() {
        XCTAssertEqual(DiscoveryAffinityRules.decadeKey(year: "1995"), "1990s")
        XCTAssertEqual(DiscoveryAffinityRules.decadeKey(year: "2008-06-01"), "2000s")
        XCTAssertNil(DiscoveryAffinityRules.decadeKey(year: nil))
        XCTAssertNil(DiscoveryAffinityRules.decadeKey(year: ""))
    }

    func testLocaleBiasUsesDesktopPreferredLanguageFallbackOrder() {
        let preferred = DiscoveryAffinityRules.localeBias(preferredLanguages: ["eng", "jpn"], metadataLanguage: "es-ES", region: "MX")
        XCTAssertEqual(preferred.codes, Set(["en", "ja", "es"]))
        XCTAssertEqual(preferred.penalty, 3)

        let metadata = DiscoveryAffinityRules.localeBias(preferredLanguages: [], metadataLanguage: "es-ES", region: "US")
        XCTAssertEqual(metadata.codes, Set(["es"]))
        let region = DiscoveryAffinityRules.localeBias(preferredLanguages: [], metadataLanguage: "", region: "BR")
        XCTAssertEqual(region.codes, Set(["pt"]))
        let variants = DiscoveryAffinityRules.localeBias(preferredLanguages: ["pt-br"], metadataLanguage: "es-419", region: "US")
        XCTAssertEqual(variants.codes, Set(["pt", "es"]))
        XCTAssertEqual(DiscoveryAffinityRules.localeBias(preferredLanguages: ["eng"], metadataLanguage: "es", region: "ES", enabled: false), .disabled)
    }

    func testAffinityRankingAppliesLocalePenaltyAndLanguageAffinity() {
        var english = Media(id: "tmdb:movie:11", type: "movie", name: "English")
        english.originalLanguage = "en"
        var french = Media(id: "tmdb:movie:12", type: "movie", name: "French")
        french.originalLanguage = "fr"
        let locale = DiscoveryAffinityRules.localeBias(preferredLanguages: ["en"], metadataLanguage: "", region: "US")

        XCTAssertEqual(DiscoveryAffinityRules.ranked([french, english], affinity: .init(), locale: locale).map(\.name), ["English", "French"])
        var affinity = DiscoveryPreferences.Affinity()
        affinity.languages = ["fr": 5]
        XCTAssertEqual(DiscoveryAffinityRules.ranked([french, english], affinity: affinity, locale: locale).map(\.name), ["French", "English"])
    }

    func testSuggestionPoolsExcludeDownvotedIDsAndTitleAliases() {
        let exact = Media(id: "downvoted-id", type: "movie", name: "Another title")
        let alias = Media(id: "tmdb:movie:13", type: "movie", name: "Dune (2021)")
        let unaffected = Media(id: "tmdb:movie:14", type: "movie", name: "Dune Part Two")
        let downvotes = [
            DiscoveryAffinityRules.Downvote(id: "downvoted-id", titleKey: DiscoveryPreferences.titleKey("Unrelated name")),
            DiscoveryAffinityRules.Downvote(id: "other-provider-id", titleKey: DiscoveryPreferences.titleKey("Dune")),
        ]

        let remaining = DiscoveryAffinityRules.excludingDownvoted([exact, alias, unaffected], downvotes: downvotes)
        XCTAssertEqual(remaining.map(\.id), [unaffected.id])
    }

    @MainActor func testAffinityStoresOriginalLanguageWithinItsProfileScope() throws {
        let owner = "discover-affinity-test-" + UUID().uuidString
        let key = DiscoveryPreferences.key(owner)
        defer { try? KeychainStore().remove(key) }
        let now = Date(timeIntervalSince1970: 1_791_417_600)
        var media = Media(id: "tmdb:movie:15", type: "movie", name: "French")
        media.originalLanguage = "fr"
        let preferences = DiscoveryPreferences(owner: owner)
        XCTAssertTrue(preferences.ready)
        preferences.track(.open, media: media, now: now)
        XCTAssertEqual(preferences.affinity(now: now).languages["fr"], 1)
        XCTAssertNil(DiscoveryPreferences(owner: owner + "-other").affinity(now: now).languages["fr"])
    }

    @MainActor func testLocaleBiasToggleIsStoredPerProfile() throws {
        let suite = "discover-locale-bias-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let persistence = DiscoverProfileSettingsMemory()
        let store = ProfileSettingsStore(defaults: defaults, persistence: persistence)
        XCTAssertTrue(ProfileSettingsStore.keys.contains("feedLocaleBias"))

        try store.activate(owner: "profile-a", sharedOwner: "profile-a", migrateLegacy: false)
        defaults.set(false, forKey: "feedLocaleBias")
        XCTAssertTrue(store.saveCurrent())

        try store.activate(owner: "profile-b", sharedOwner: "profile-b", migrateLegacy: false)
        XCTAssertNil(defaults.object(forKey: "feedLocaleBias"))
        XCTAssertTrue(defaults.object(forKey: "feedLocaleBias") as? Bool ?? true)
        defaults.set(true, forKey: "feedLocaleBias")
        try store.activate(owner: "profile-a", sharedOwner: "profile-a", migrateLegacy: false)
        XCTAssertFalse(defaults.bool(forKey: "feedLocaleBias"))

        let reopened = ProfileSettingsStore(defaults: defaults, persistence: persistence)
        try reopened.activate(owner: "profile-b", sharedOwner: "profile-b", migrateLegacy: false)
        XCTAssertTrue(defaults.bool(forKey: "feedLocaleBias"))
    }

    func testDailyCatalogBuildsStableDefinitionsAndOriginalCinemetaFallback() throws {
        let now = try XCTUnwrap(Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 9, hour: 12)))
        let fallback = DiscoveryDailyFeed.rows(tmdbKey: "", affinity: .init(), region: "ES", enabledServices: [], now: now)
        XCTAssertEqual(fallback.map(\.id), [
            "fallback_cinemeta_movies", "fallback_cinemeta_series", "fallback_cinemeta_Thriller", "fallback_cinemeta_Crime",
            "fallback_cinemeta_Comedy", "fallback_cinemeta_Romance", "fallback_cinemeta_Sci-Fi",
        ])
        XCTAssertEqual(fallback.first?.endpoint, .cinemeta(kind: "movie", genre: nil))

        let rows = DiscoveryDailyFeed.rows(tmdbKey: "fixture", affinity: .init(), region: "ES", enabledServices: [], now: now)
        XCTAssertEqual(rows.prefix(3).map(\.id), ["trending:_", "critically_loved:_", "award_winning:_"])
        XCTAssertEqual(rows.prefix(3).map(\.pageBase), [1, 1, 1])
        XCTAssertEqual(Set(rows.map(\.id)).count, rows.count)
        XCTAssertTrue(rows.allSatisfy { (1...3).contains($0.pageBase) })
        let closing = try XCTUnwrap(rows.last)
        XCTAssertTrue(DiscoveryDailyRows.rotatingAnchors.contains { closing.id.hasPrefix($0 + ":") })
        let again = DiscoveryDailyFeed.rows(tmdbKey: "fixture", affinity: .init(), region: "ES", enabledServices: [], now: now)
        XCTAssertEqual(rows.map(\.id), again.map(\.id))
    }

    func testDailyCatalogLocalizesOnlyUnrestrictedMovieFloorsWhenEnabled() {
        let floor = ["vote_count.gte": "200"]
        XCTAssertEqual(DiscoveryDailyFeed.localizeFloor(floor, kind: "movie", enabled: true, localeCodes: ["es"], region: "ES")["region"], "ES")
        XCTAssertEqual(DiscoveryDailyFeed.localizeFloor(floor, kind: "movie", enabled: false, localeCodes: ["es"], region: "ES"), floor)
        XCTAssertEqual(DiscoveryDailyFeed.localizeFloor(floor, kind: "series", enabled: true, localeCodes: ["es"], region: "ES"), floor)
        let language = ["with_original_language": "ko"]
        XCTAssertEqual(DiscoveryDailyFeed.localizeFloor(language, kind: "movie", enabled: true, localeCodes: ["es"], region: "ES"), language)
    }

    func testDailyCatalogReservesPriorityRowsAndOnlyReusesProtectedTitlesLast() {
        func title(_ id: String) -> Media { Media(id: id, type: "movie", name: id, poster: "https://example.com/poster.jpg") }
        let featured = title("hero"), common = title("shared"), trend = title("trend")
        let rows = DiscoveryDailyFeed.rows(tmdbKey: "fixture", affinity: .init(), region: "US", enabledServices: [])
        let loaded = ["trending:_": [featured, common, trend], "critically_loved:_": [common, title("critics")],
                      "award_winning:_": [common, title("award")]]
        let first = DiscoveryDailyFeed.deduplicatedRows(rows: rows, loaded: loaded, featuredIDs: [featured.id], minimum: 1)
        XCTAssertEqual(first["trending:_"]?.map(\.id), ["trend"])
        XCTAssertEqual(first["critically_loved:_"]?.map(\.id), ["shared", "critics"])
        XCTAssertEqual(first["award_winning:_"]?.map(\.id), ["award"])
        let filled = DiscoveryDailyFeed.deduplicatedRows(rows: rows, loaded: loaded, featuredIDs: [featured.id], minimum: 3)
        XCTAssertEqual(filled["trending:_"]?.map(\.id), ["trend", "shared", "hero"])
    }

    func testDailyCatalogKeepsEligibleUnseenTitlesBeforeWatchedAndVotedOnes() {
        func title(_ id: String, _ name: String, poster: String? = "https://example.com/poster.jpg") -> Media {
            Media(id: id, type: "movie", name: name, poster: poster)
        }
        let filter = DiscoveryDailyFeed.Filter(downvotes: [.init(id: "blocked", titleKey: "disliked")], upvoted: ["liked"],
            history: .init(["legacy": .init(parsedTitle: "Watched (2021)", savedAt: 1)]), affinity: .init(), locale: .disabled)
        let inputs = [title("watched", "Watched"), title("liked", "Liked"), title("missing", "Missing", poster: ""),
                      title("blocked", "Hidden"), title("alias", "Disliked"), title("fresh", "Fresh"), title("fresh", "Duplicate")]
        XCTAssertEqual(filter.eligible(inputs).map(\.id), ["fresh", "watched", "liked"])
    }

    func testShowsCatalogMatchesDesktopRailOrderAndEditorialFilters() throws {
        let date = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-11-09T17:30:00Z"))
        let rails = TMDBService().definitions("series", now: date)
        XCTAssertEqual(rails.map(\.id), ["tmdb-series-top10", "tmdb-series-current", "tmdb-tv-fresh", "tmdb-tv-network-49", "tmdb-tv-network-213",
            "tmdb-tv-network-2552", "tmdb-tv-network-174", "tmdb-tv-network-88", "tmdb-tv-network-2739", "tmdb-tv-network-1024",
            "tmdb-tv-limited", "tmdb-series-genre-18", "tmdb-series-genre-35", "tmdb-series-genre-80", "tmdb-series-genre-10765",
            "tmdb-series-genre-99", "tmdb-series-rated", "tmdb-series-long-runners", "tmdb-series-korean", "tmdb-series-british"])
        XCTAssertEqual(rails.first?.path, "trending/tv/week")
        XCTAssertTrue(rails.allSatisfy { !$0.usesRegion })
        XCTAssertEqual(rails[2].parameters["first_air_date.gte"], "2026-09-25")
        XCTAssertEqual(rails[2].parameters["first_air_date.lte"], "2026-11-09")
        XCTAssertEqual(rails[11].parameters, ["with_genres": "18", "vote_average.gte": "8.0", "vote_count.gte": "1000", "sort_by": "vote_average.desc"])
        XCTAssertEqual(rails[17].parameters["first_air_date.lte"], "2010-12-31")
        XCTAssertEqual(rails[18].parameters["with_origin_country"], "KR")
        XCTAssertEqual(rails[19].parameters["with_origin_country"], "GB")
        XCTAssertEqual(Array(ShowsCatalog.fallbackGenres.prefix(3)), ["Drama", "Comedy", "Crime"])
        XCTAssertEqual(ShowsCatalog.fallbackKey(for: "Action"), "native-series-1")
        XCTAssertEqual(ShowsCatalog.fallbackKey(for: "Crime"), "native-series-10")
    }

    func testShowsCatalogKeepsTheWeeklyTopTenAndOmitsFeaturedTitlesFromRegularRows() {
        let definitions = TMDBService().definitions("series")
        let titles = (0..<12).map { Media(id: "tt\($0)", type: "series", name: "Owned \($0)") }
        var top = definitions[0], ordinary = definitions[1], tooShort = definitions[2]
        top.metas = titles
        ordinary.metas = Array(titles.prefix(6))
        tooShort.metas = Array(titles.prefix(5))
        let visible = ShowsCatalog.visible([top, ordinary, tooShort], heroIDs: [titles[0].id, titles[1].id])
        XCTAssertEqual(visible.map(\.id), [top.id, ordinary.id])
        XCTAssertEqual(visible.first?.metas.map(\.id), titles.prefix(10).map(\.id))
        XCTAssertEqual(visible.last?.metas.map(\.id), Array(titles[2..<6]).map(\.id))
        top.metas = Array(titles.prefix(9))
        XCTAssertTrue(ShowsCatalog.visible([top], heroIDs: []).isEmpty)
    }

    func testShowsShelfPagingUsesProviderCountAndCapsDeduplicatedResults() {
        let titles = (0..<40).map { Media(id: "tmdb:tv:\($0)", type: "series", name: "Owned \($0)") }
        let short = ShowsCatalog.Paging(firstPage: Array(titles.prefix(13)))
        XCTAssertFalse(short.hasMore)
        let first = Array(titles.prefix(20))
        var paging = ShowsCatalog.Paging(firstPage: first)
        XCTAssertTrue(paging.hasMore)
        XCTAssertEqual(paging.nextPage, 2)

        let second = [titles[18], titles[19], titles[20], titles[20], titles[21]]
        let merged = paging.append(second, to: first)
        XCTAssertEqual(merged.map(\.id), titles.prefix(22).map(\.id))
        XCTAssertEqual(paging.nextPage, 3)
        XCTAssertTrue(paging.hasMore)

        let capped = paging.append(Array(titles[22...]), to: merged)
        XCTAssertEqual(capped.map(\.id), titles.prefix(30).map(\.id))
        XCTAssertFalse(paging.hasMore)
    }

    func testShowsShelfPagingStopsAtEmptyOrRepeatedProviderPage() {
        let first = (0..<14).map { Media(id: "tmdb:tv:\($0)", type: "series", name: "Owned \($0)") }
        var repeated = ShowsCatalog.Paging(firstPage: first)
        XCTAssertEqual(repeated.append(first, to: first).map(\.id), first.map(\.id))
        XCTAssertFalse(repeated.hasMore)
        var empty = ShowsCatalog.Paging(firstPage: first)
        XCTAssertEqual(empty.append([], to: first).map(\.id), first.map(\.id))
        XCTAssertFalse(empty.hasMore)
    }

    func testShowsHeroUsesPinnedRequestsPoolOrderAndRotation() throws {
        let date = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-11-09T17:30:00Z"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let requests = ShowsHero.requests(now: date)
        XCTAssertEqual(requests.count, 17)
        XCTAssertEqual(requests.prefix(4).map(\.path), ["trending/tv/week", "tv/popular", "tv/on_the_air", "tv/top_rated"])
        XCTAssertEqual(requests[11].parameters["first_air_date.gte"], "2026-08-11")
        XCTAssertEqual(requests[15].parameters["with_networks"], "213")
        let seed = ShowsHero.rotationSeed(now: date, calendar: calendar)
        XCTAssertEqual(seed, 1254)
        XCTAssertEqual(ShowsHero.rotationSeed(now: date.addingTimeInterval(5 * 3600), calendar: calendar), 1255)
        XCTAssertEqual(ShowsHero.mast(now: date, calendar: calendar).kicker, "Tonight's Slate")
        let titles = "abcdefghij".map { name -> Media in
            var media = Media(id: String(name), type: "series", name: String(name))
            media.background = "https://example.test/backdrop.png"
            return media
        }
        XCTAssertEqual(ShowsHero.slides(titles, seed: seed).map(\.id), ["f", "d", "h", "c", "b", "a"])
        var noArt = titles[2]; noArt.background = nil
        XCTAssertEqual(ShowsHero.pool([[titles[0], noArt, titles[3]], [titles[1], titles[0], titles[2]]]).map(\.id), ["a", "b", "d", "c"])
        XCTAssertEqual(ShowsHero.fallback([noArt] + titles).map(\.id), ["a", "b", "c", "d", "e", "f"])
    }

    func testPremiereRailAndNetworkRailsMatchDesktopSpecs() {
        let rails = TMDBService().definitions("series")
        func parameters(_ id: String) -> [String: String]? { rails.first { $0.id == id }?.parameters }
        let fresh = parameters("tmdb-tv-fresh")
        XCTAssertEqual(fresh?["vote_count.gte"], "20")
        XCTAssertEqual(fresh?["sort_by"], "popularity.desc")
        XCTAssertNotNil(fresh?["first_air_date.gte"])
        XCTAssertNotNil(fresh?["first_air_date.lte"])
        let expected: [(String, String, String)] = [
            ("49", "200", "popularity.desc"), ("213", "300", "popularity.desc"), ("2552", "100", "popularity.desc"),
            ("174", "200", "popularity.desc"), ("88", "200", "popularity.desc"), ("2739", "100", "popularity.desc"),
            ("1024", "200", "popularity.desc"),
        ]
        // The Quick Watches rail belongs to the movie list, not the series list.
        let quick = TMDBService().definitions("movie").first { $0.id == "tmdb-quick" }?.parameters
        XCTAssertEqual(quick?["with_runtime.lte"], "90")
        XCTAssertEqual(quick?["with_runtime.gte"], "70")
        XCTAssertEqual(quick?["vote_average.gte"], "7.0")
        XCTAssertEqual(quick?["vote_count.gte"], "300")
        XCTAssertEqual(quick?["sort_by"], "vote_average.desc")
        for (network, minimum, sort) in expected {
            let found = parameters("tmdb-tv-network-" + network)
            XCTAssertEqual(found?["with_networks"], network)
            XCTAssertEqual(found?["vote_count.gte"], minimum)
            XCTAssertEqual(found?["sort_by"], sort)
        }
    }
}

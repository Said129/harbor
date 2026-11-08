import XCTest
@testable import Harbor

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
        let quick = rails.first { $0.id == "tmdb-quick" }?.parameters
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

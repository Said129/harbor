import XCTest
@testable import Harbor

/// Desktop anime picks and anime row rules: origins from AniList, daily pages, taste seeds, franchise keys and the
/// per-pool dedupe. Fake titles only: no network, no UI.
@MainActor final class F2AnimePicksTests: XCTestCase {
    func testDailyPageStaysWithinThreePagesAndIsFixedForTheDay() {
        for day in 0..<40 {
            let page = AnimePicksPolicy.dailyPage(seedKey: "g10", day: day)
            XCTAssertTrue((1...3).contains(page))
            XCTAssertEqual(page, AnimePicksPolicy.dailyPage(seedKey: "g10", day: day))
        }
    }

    func testTasteGenreNamesKeepPositiveWeightsHeaviestFirst() {
        let weights: [String: Double] = ["Drama": 2.0, "Action": 5.0, "Horror": 0, "Comedy": -1.0, "Romance": 2.0]
        XCTAssertEqual(AnimePicksPolicy.tasteGenreNames(weights), ["Action", "Drama", "Romance"])
    }

    func testTasteGenreNamesStopAtEight() {
        var weights: [String: Double] = [:]
        for index in 0..<10 { weights["G" + String(index)] = Double(index + 1) }
        let names = AnimePicksPolicy.tasteGenreNames(weights)
        XCTAssertEqual(names.count, 8)
        XCTAssertEqual(names.first, "G9")
    }

    func testTasteSeedsComeBeforeFavourites() {
        let names = AnimePicksPolicy.tasteGenreNames(["Action": 3, "Romance": 2])
        XCTAssertEqual(AnimePicksPolicy.seedGenreIDs(favorites: [8, 1], tasteGenres: names), [1, 22, 8])
    }

    func testMalIDOnlyForMalTitles() {
        XCTAssertEqual(AnimePicksPolicy.malID("mal:21"), 21)
        XCTAssertNil(AnimePicksPolicy.malID("kitsu:21"))
        XCTAssertNil(AnimePicksPolicy.malID("anilist:21"))
    }

    func testCountriesReadsOnlyEntriesWithAMalIdAndATwoLetterCode() {
        let media: [JSONValue] = [
            .object(["idMal": .integer(21), "countryOfOrigin": .string("JP")]),
            .object(["idMal": .integer(5), "countryOfOrigin": .null]),
            .object(["countryOfOrigin": .string("KR")]),
            .object(["idMal": .integer(7), "countryOfOrigin": .string("Japan")]),
        ]
        XCTAssertEqual(AnimePicksPolicy.countries(from: media), [21: "JP"])
    }

    func testWithCountriesFillsOnlyMissingOrigins() {
        var known = Media(id: "mal:3", type: "series", name: "Known")
        known.country = "CN"
        let items = [Media(id: "mal:21", type: "series", name: "Fresh"), known, Media(id: "anilist:21", type: "series", name: "Other")]
        let out = AnimePicksPolicy.withCountries(items, countries: [21: "JP", 3: "JP"])
        let expected: [String?] = ["JP", "CN", nil]
        XCTAssertEqual(out.map(\.country), expected)
    }

    func testEnrichedOriginHidesThePick() {
        let options = AnimePicksPolicy.Options(favoriteGenres: [], excludeOrigins: ["CN"], hideWatched: false)
        let items = AnimePicksPolicy.withCountries([Media(id: "mal:9", type: "series", name: "Donghua")], countries: [9: "CN"])
        XCTAssertEqual(AnimePicksPolicy.filtered(items, options: options, isWatched: { _ in false }).count, 0)
    }

    func testFranchiseKeyIgnoresSeasonPartNumeralAndYear() {
        XCTAssertEqual(AnimePicksPolicy.franchiseKey("Attack on Titan Season 2"), AnimePicksPolicy.franchiseKey("Attack on Titan"))
        XCTAssertEqual(AnimePicksPolicy.franchiseKey("Mob Psycho 100 II"), "mob psycho 100")
        XCTAssertEqual(AnimePicksPolicy.franchiseKey("Fullmetal Alchemist (2009)"), "fullmetal alchemist")
        XCTAssertNotEqual(AnimePicksPolicy.franchiseKey("Naruto"), AnimePicksPolicy.franchiseKey("Naruto Shippuden"))
    }

    func testPooledRowsShowEachFranchiseOncePerPoolAfterTheSeeds() {
        let seed = Media(id: "mal:1", type: "series", name: "Frieren")
        let general = [
            Media(id: "mal:2", type: "series", name: "Frieren Season 2"),
            Media(id: "mal:3", type: "series", name: "Dandadan"),
            Media(id: "mal:4", type: "series", name: "Dandadan Season 2"),
        ]
        let genre = [
            Media(id: "mal:3", type: "series", name: "Dandadan"),
            Media(id: "mal:1", type: "series", name: "Frieren"),
        ]
        let out = AnimePicksPolicy.pooledRows([(pool: "general", metas: general), (pool: "genre", metas: genre)], seeds: [seed])
        XCTAssertEqual(out[0].map(\.id), ["mal:3"])
        XCTAssertEqual(out[1].map(\.id), ["mal:3"])
    }

    func testPooledRowsKeepStrippedNames() {
        let rows = [(pool: "general", metas: [Media(id: "mal:5", type: "series", name: "Sousou no Frieren Season 2")])]
        let out = AnimePicksPolicy.pooledRows(rows, seeds: [])
        XCTAssertEqual(out[0].first?.name, "Sousou no Frieren")
    }
}

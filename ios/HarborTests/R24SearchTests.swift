import XCTest
@testable import Harbor

final class R24SearchTests: XCTestCase {
    private let movieGenres: [(String, Int)] = [("Sci-Fi", 878), ("Animation", 16), ("Action", 28)]
    private let tvGenres: [(String, Int)] = [("Sci-Fi & Fantasy", 10765), ("Animation", 16)]

    private func media(_ id: String, type: String = "movie", name: String, year: String? = nil, imdb: String? = nil) -> Media {
        var item = Media(id: id, type: type, name: name)
        item.releaseInfo = year
        item.imdbID = imdb
        return item
    }

    func testTheTopMatchIsTheMostPopularTitleAndATieKeepsTheEarlierOne() {
        XCTAssertEqual(SearchRanking.topMatchIndex(popularities: [3.5, 80.2, 80.2, 1]), 1)
        XCTAssertEqual(SearchRanking.topMatchIndex(popularities: [0, 0]), 0)
        XCTAssertNil(SearchRanking.topMatchIndex(popularities: []))
    }

    func testAYearQueryIsAYearIntentAndOtherYearsAreNot() {
        XCTAssertEqual(SearchRanking.intent("2019", movieGenres: movieGenres, tvGenres: tvGenres), .year(2019))
        XCTAssertEqual(SearchRanking.intent(" 1999 ", movieGenres: movieGenres, tvGenres: tvGenres), .year(1999))
        XCTAssertNil(SearchRanking.intent("1899", movieGenres: movieGenres, tvGenres: tvGenres))
        XCTAssertNil(SearchRanking.intent("2019x", movieGenres: movieGenres, tvGenres: tvGenres))
    }

    func testAGenreNameWithOrWithoutTheMoviesOrShowsSuffixIsAGenreIntent() {
        XCTAssertEqual(SearchRanking.intent("sci-fi", movieGenres: movieGenres, tvGenres: tvGenres), .genre(name: "Sci-Fi", isSeries: false))
        XCTAssertEqual(SearchRanking.intent("Action movies", movieGenres: movieGenres, tvGenres: tvGenres), .genre(name: "Action", isSeries: false))
        XCTAssertEqual(SearchRanking.intent("Sci-Fi & Fantasy shows", movieGenres: movieGenres, tvGenres: tvGenres), .genre(name: "Sci-Fi & Fantasy", isSeries: true))
        XCTAssertNil(SearchRanking.intent("Action shows", movieGenres: movieGenres, tvGenres: tvGenres))
        XCTAssertNil(SearchRanking.intent("Dune", movieGenres: movieGenres, tvGenres: tvGenres))
    }

    func testAGenreInBothTablesIsAMovieGenreFirst() {
        XCTAssertEqual(SearchRanking.intent("Animation", movieGenres: movieGenres, tvGenres: tvGenres), .genre(name: "Animation", isSeries: false))
    }

    func testATMDBTitleAndAnAddonTitleWithTheSameNameAndYearAreOneTitle() {
        let addon = [media("tt1160419", name: "Dune", year: "2021")]
        let tmdb = [media("tmdb:movie:1", name: "Dune", year: "2021"), media("tmdb:movie:2", name: "Dune", year: "1984")]
        XCTAssertEqual(SearchRanking.dropDuplicates(tmdb, against: addon).map(\.id), ["tmdb:movie:2"])
    }

    func testAnImdbIdMatchesEvenWhenTheNamesDiffer() {
        let addon = [media("tt1160419", name: "Dune", year: "2021")]
        let tmdb = [media("tmdb:movie:1", name: "Dune: Part One", year: "2021", imdb: "tt1160419")]
        XCTAssertTrue(SearchRanking.dropDuplicates(tmdb, against: addon).isEmpty)
    }

    func testNamesIgnoreAccentsCaseAndPunctuationButTypeAndYearStillSeparateTitles() {
        let addon = [media("tt0211915", name: "Amelie", year: "2001")]
        XCTAssertTrue(SearchRanking.dropDuplicates([media("tmdb:movie:3", name: "Amélie", year: "2001")], against: addon).isEmpty)
        XCTAssertEqual(SearchRanking.dropDuplicates([media("tmdb:tv:4", type: "series", name: "Amélie", year: "2001")], against: addon).count, 1)
        XCTAssertEqual(SearchRanking.dropDuplicates([media("tmdb:movie:5", name: "Spider-Man!", year: "2002")], against: [media("tt1", name: "Spider Man", year: "2002")]).count, 0)
    }

    func testDuplicatesInsideTheTMDBListAreKeptOnce() {
        let items = [media("tmdb:movie:1", name: "Heat", year: "1995"), media("tmdb:movie:2", name: "Heat", year: "1995")]
        XCTAssertEqual(SearchRanking.dropDuplicates(items, against: []).map(\.id), ["tmdb:movie:1"])
    }

    func testTheAnimeMergeKeepsSourceOrderAndSkipsRepeatedIdsNamesAndUntitled() {
        let anilist = [AnimeSearchCandidate(malId: 1, name: "Cowboy Bebop")]
        let jikan = [
            AnimeSearchCandidate(malId: 1, name: "Cowboy Bebop (TV)"),
            AnimeSearchCandidate(malId: 2, name: "Cowboy Bebop"),
            AnimeSearchCandidate(malId: 3, name: "Untitled"),
            AnimeSearchCandidate(malId: 4, name: "  "),
        ]
        let kitsu = [AnimeSearchCandidate(malId: 0, name: "Cowboy bebop"), AnimeSearchCandidate(malId: 0, name: "Ghost in the Shell")]
        XCTAssertEqual(SearchRanking.mergeAnime([anilist, jikan, kitsu]).map(\.name), ["Cowboy Bebop", "Ghost in the Shell"])
    }

    func testTheAnimeMergeKeepsAtMostEightTitles() {
        let many = (1...10).map { AnimeSearchCandidate(malId: $0, name: "Show \($0)") }
        let merged = SearchRanking.mergeAnime([many])
        XCTAssertEqual(merged.count, 8)
        XCTAssertEqual(merged.first?.name, "Show 1")
        XCTAssertEqual(merged.last?.name, "Show 8")
    }

    func testWithoutATMDBKeyThereAreNoTMDBRows() async {
        let configuration = MetadataConfiguration(tmdbKey: "", region: "US", language: "en-US", translateTitles: false)
        let matches = await SearchTMDBSource.load(query: "Dune", configuration: configuration)
        XCTAssertTrue(SearchTMDBSource.rows(for: matches.titles, addonRows: []).isEmpty)
        XCTAssertNil(matches.topMatch)
    }

    func testTopMatchUsesOriginalTMDBOrderAndIgnoresPeopleAndMissingPosters() {
        let configuration = MetadataConfiguration(tmdbKey: "fixture", region: "US", language: "en-US", translateTitles: false)
        func hit(_ id: Int64, _ kind: String, _ popularity: Double, poster: JSONValue = .string("/poster.jpg")) -> JSONValue {
            .object(["id": .integer(id), "media_type": .string(kind), "title": .string("Film \(id)"),
                     "name": .string("Show \(id)"), "poster_path": poster, "popularity": .number(popularity)])
        }
        let response: JSONValue = .object(["results": .array([
            hit(1, "person", 500), hit(2, "movie", 200, poster: .null),
            hit(3, "tv", 70), hit(4, "movie", 70), hit(5, "movie", 15),
        ])])
        let matches = CustomListSearchResults.matches(response, configuration: configuration)
        XCTAssertEqual(matches.topMatch?.id, "tmdb:tv:3")
        XCTAssertEqual(matches.titles.map(\.id), ["tmdb:movie:4", "tmdb:movie:5", "tmdb:tv:3"])
    }

    func testMatchingAddonTakesPriorityWhenOpeningTopMatch() {
        let addon = Addon(manifest: .object(["id": .string("fixture"), "name": .string("Fixture")]),
                          transportUrl: "https://example.com", enabled: true)
        let plan = RequestPlan(key: "fixture-search", url: "https://example.com", title: "Search", kind: "movie",
                               addon: addon, addonPriority: 0, timeoutMs: 1_000, catalog: nil)
        let correct = media("tt1160419", name: "Dune", year: "2021")
        let other = media("tt0087182", name: "Dune", year: "1984")
        let match = media("tmdb:movie:1", name: "Dune", year: "2021")
        let rows = [CatalogRow(plan: plan, metas: [other, correct])]
        XCTAssertEqual(SearchTMDBSource.destination(for: match, addonRows: rows).id, correct.id)
        XCTAssertTrue(SearchTMDBSource.rows(for: [match], addonRows: rows).isEmpty)
        XCTAssertEqual(SearchTMDBSource.destination(for: match, addonRows: []).id, match.id)
    }
}

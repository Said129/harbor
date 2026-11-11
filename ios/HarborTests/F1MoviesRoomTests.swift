import XCTest
@testable import Harbor

/// Desktop 0.9.132 Movies rows (`views/movies.tsx`): hero and Top 10 exclusion, cross-row dedupe, the four-title floor and the Top 10 gate.
final class F1MoviesRoomTests: XCTestCase {
    private func media(_ number: Int) -> Media {
        Media(id: "tt\(number)", type: "movie", name: "Title \(number)")
    }

    private func medias(_ numbers: ClosedRange<Int>) -> [Media] {
        numbers.map { media($0) }
    }

    private func rail(_ id: String, _ numbers: ClosedRange<Int>) -> PageRail {
        .discovery(DiscoveryRail(id: id, title: id, kind: "movie", path: "movie/test", metas: medias(numbers)))
    }

    private func ids(_ rails: [PageRail], _ id: String) -> [String]? {
        rails.first(where: { $0.id == "discovery-" + id })?.metas.map(\.id)
    }

    func testHeroTitlesAreRemovedFromLaterRows() {
        let rails = [rail("tmdb-movie-current", 1...6)]
        let result = MoviesCatalog.visible(rails, heroIDs: ["tt1", "tt2"])
        XCTAssertEqual(ids(result, "tmdb-movie-current"), ["tt3", "tt4", "tt5", "tt6"])
    }

    func testTitlesAreShownOnlyInTheFirstRowThatClaimsThem() {
        let rails = [rail("tmdb-movie-current", 1...5), rail("tmdb-movie-rated", 3...10)]
        let result = MoviesCatalog.visible(rails, heroIDs: [])
        XCTAssertEqual(ids(result, "tmdb-movie-current"), ["tt1", "tt2", "tt3", "tt4", "tt5"])
        XCTAssertEqual(ids(result, "tmdb-movie-rated"), ["tt6", "tt7", "tt8", "tt9", "tt10"])
    }

    func testRowsLeftWithFewerThanFourTitlesAreDropped() {
        let rails = [rail("tmdb-movie-current", 1...5), rail("tmdb-movie-rated", 1...5), rail("tmdb-movie-popular", 20...21)]
        let result = MoviesCatalog.visible(rails, heroIDs: [])
        XCTAssertNotNil(ids(result, "tmdb-movie-current"))
        XCTAssertNil(ids(result, "tmdb-movie-rated"))
        XCTAssertNil(ids(result, "tmdb-movie-popular"))
    }

    func testTopTenRowTakesTenTitlesAndHidesTheTrendingRow() {
        let rails = [
            rail("tmdb-movie-top10", 1...12),
            rail("tmdb-movie-trending", 1...12),
            rail("tmdb-movie-rated", 9...14)
        ]
        let result = MoviesCatalog.visible(rails, heroIDs: ["tt30"])
        XCTAssertEqual(ids(result, "tmdb-movie-top10")?.count, 10)
        XCTAssertNil(ids(result, "tmdb-movie-trending"))
        XCTAssertEqual(ids(result, "tmdb-movie-rated"), ["tt11", "tt12", "tt13", "tt14"])
    }

    func testTopTenRowBelowTenTitlesIsHiddenAndTrendingRowStays() {
        let rails = [rail("tmdb-movie-top10", 1...9), rail("tmdb-movie-trending", 1...12)]
        let result = MoviesCatalog.visible(rails, heroIDs: [])
        XCTAssertNil(ids(result, "tmdb-movie-top10"))
        XCTAssertEqual(ids(result, "tmdb-movie-trending")?.count, 12)
    }

    func testTopTenTitlesAreExcludedFromLaterRowsWhenTheRowRenders() {
        let short = [rail("tmdb-movie-top10", 1...10), rail("tmdb-movie-rated", 5...12)]
        XCTAssertNil(ids(MoviesCatalog.visible(short, heroIDs: []), "tmdb-movie-rated"))
        let long = [rail("tmdb-movie-top10", 1...10), rail("tmdb-movie-rated", 5...14)]
        XCTAssertEqual(ids(MoviesCatalog.visible(long, heroIDs: []), "tmdb-movie-rated"), ["tt11", "tt12", "tt13", "tt14"])
    }
}

import XCTest
@testable import Harbor

final class R22SearchTests: XCTestCase {
    private func title(_ index: Int, poster: String? = "https://image.tmdb.org/t/p/w500/poster.jpg") -> Media {
        var item = Media(id: "tmdb:movie:\(index)", type: "movie", name: "Title \(index)")
        item.poster = poster
        return item
    }

    func testOnlyMovieSeriesAndTVRowsGetTheTitleRules() {
        XCTAssertTrue(SearchTitleRules.isTitleRow("movie"))
        XCTAssertTrue(SearchTitleRules.isTitleRow("series"))
        XCTAssertTrue(SearchTitleRules.isTitleRow("tv"))
        XCTAssertFalse(SearchTitleRules.isTitleRow("anime"))
        XCTAssertFalse(SearchTitleRules.isTitleRow("channel"))
    }

    func testTitlesWithoutAPosterAreDropped() {
        let metas = [title(1), title(2, poster: nil), title(3, poster: "")]
        XCTAssertEqual(SearchTitleRules.limited(metas).map(\.name), ["Title 1"])
    }

    func testAtMostTwelveTitlesAreKeptInOrder() {
        let metas = (1...20).map { title($0) }
        let kept = SearchTitleRules.limited(metas)
        XCTAssertEqual(kept.count, 12)
        XCTAssertEqual(kept.first?.name, "Title 1")
        XCTAssertEqual(kept.last?.name, "Title 12")
    }

    func testThePosterFilterRunsBeforeTheCap() {
        let metas = (1...15).map { title($0, poster: $0 <= 3 ? nil : "https://image.tmdb.org/t/p/w500/poster.jpg") }
        let kept = SearchTitleRules.limited(metas)
        XCTAssertEqual(kept.count, 12)
        XCTAssertEqual(kept.first?.name, "Title 4")
        XCTAssertEqual(kept.last?.name, "Title 15")
    }
}

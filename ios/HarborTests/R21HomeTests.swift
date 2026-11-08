import XCTest
@testable import Harbor

/// Desktop 0.9.132 Home and movie/series rules ported as pure helpers: Continue Watching names and cap,
/// inline catalog paging, the cinema hero timer, and the daily hero pick.
final class R21HomeTests: XCTestCase {
    private func media(_ id: String) -> Media {
        Media(id: id, type: "movie", name: id)
    }

    private func record(_ id: String, name: String?, type: String = "movie", lastWatched: Int64 = 0) -> LibraryRecord {
        var fields: [String: JSONValue] = ["_id": .string(id), "type": .string(type), "state": .object(["lastWatched": .integer(lastWatched)])]
        if let name { fields["name"] = .string(name) }
        return LibraryRecord(raw: .object(fields))
    }

    func testContinueWatchingNameKeyKeepsLettersAndDigits() {
        XCTAssertEqual(HomeContinueWatchingRules.nameKey("Dr. Who (2005)"), "drwho2005")
        XCTAssertNil(HomeContinueWatchingRules.nameKey(""))
        XCTAssertNil(HomeContinueWatchingRules.nameKey(nil))
    }

    func testContinueWatchingKeepsOnlyTheNewestCopyOfAName() {
        let older = record("tt1", name: "Same Title", lastWatched: 100)
        let newer = record("tt2", name: "same title!", lastWatched: 200)
        XCTAssertEqual(HomeContinueWatchingRules.cards([older, newer]).map(\.id), ["tt2"])
        XCTAssertEqual(HomeContinueWatchingRules.cards([newer, older]).map(\.id), ["tt2"])
    }

    func testContinueWatchingNameRuleIsPerType() {
        let movie = record("tt1", name: "Same Title", lastWatched: 100)
        let series = record("tt3", name: "Same Title", type: "series", lastWatched: 50)
        XCTAssertEqual(HomeContinueWatchingRules.cards([movie, series]).map(\.id), ["tt1", "tt3"])
    }

    func testContinueWatchingKeepsRecordsWithoutANameAndCapsAtOneHundred() {
        let unnamed = [record("x1", name: nil), record("x2", name: nil)]
        XCTAssertEqual(HomeContinueWatchingRules.cards(unnamed).map(\.id), ["x1", "x2"])
        let many = (0..<105).map { record("id\($0)", name: "Title \($0)", lastWatched: Int64($0)) }
        let capped = HomeContinueWatchingRules.cards(many)
        XCTAssertEqual(capped.count, HomeContinueWatchingRules.maximumCards)
        XCTAssertEqual(capped.last?.id, "id99")
    }

    func testCatalogRowPagingStartsOnlyForAFullFirstPage() {
        XCTAssertFalse(CatalogRowPaging.initialHasMore(count: 13))
        XCTAssertTrue(CatalogRowPaging.initialHasMore(count: 14))
        XCTAssertFalse(CatalogRowPaging.initialHasMore(count: 30))
    }

    func testCatalogRowPagingRequestsOnlyWhenIdleAndUnderTheCap() {
        XCTAssertTrue(CatalogRowPaging.shouldRequest(hasMore: true, loading: false, count: 20))
        XCTAssertFalse(CatalogRowPaging.shouldRequest(hasMore: false, loading: false, count: 20))
        XCTAssertFalse(CatalogRowPaging.shouldRequest(hasMore: true, loading: true, count: 20))
        XCTAssertFalse(CatalogRowPaging.shouldRequest(hasMore: true, loading: false, count: 30))
    }

    func testCatalogRowPagingSkipsKnownTitlesAndStopsAtTheCap() {
        let merged = CatalogRowPaging.merge(current: [media("a"), media("b")], more: [media("b"), media("c"), media("d")], received: 3)
        XCTAssertEqual(merged.metas.map(\.id), ["a", "b", "c", "d"])
        XCTAssertTrue(merged.hasMore)

        let full = CatalogRowPaging.merge(current: (1...28).map { media("m\($0)") }, more: (29...33).map { media("m\($0)") }, received: 5)
        XCTAssertEqual(full.metas.count, CatalogRowPaging.maximumRowItems)
        XCTAssertFalse(full.hasMore)

        XCTAssertFalse(CatalogRowPaging.merge(current: [media("a")], more: [], received: 0).hasMore)
    }

    func testCinemaHeroMovesInOrderAndWrapsAroundEveryElevenSeconds() {
        XCTAssertEqual(CinemaHeroRotation.next(after: 0, count: 5), 1)
        XCTAssertEqual(CinemaHeroRotation.next(after: 4, count: 5), 0)
        XCTAssertEqual(CinemaHeroRotation.next(after: 0, count: 0), 0)
        XCTAssertEqual(CinemaHeroRotation.interval, .seconds(11))
    }

    func testDailyHeroPickFollowsDesktopOrder() {
        let pool = ["a", "b", "c", "d", "e", "f"]
        XCTAssertEqual(DailyHeroRotation.pick(pool, count: 5, day: 0), ["a", "f", "e", "d", "c"])
        XCTAssertEqual(DailyHeroRotation.pick(["x"], count: 5, day: 3), ["x"])
        XCTAssertEqual(DailyHeroRotation.pick([String](), count: 5, day: 3), [])
    }
}

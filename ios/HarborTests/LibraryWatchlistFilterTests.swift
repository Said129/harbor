import XCTest
@testable import Harbor

final class LibraryWatchlistFilterTests: XCTestCase {
    private func record(_ id: String, removed: Bool = false, temp: Bool = false, offset: Int64 = 0) -> LibraryRecord {
        LibraryRecord(raw: .object([
            "_id": .string(id), "type": .string("movie"), "name": .string(id),
            "removed": .bool(removed), "temp": .bool(temp),
            "state": .object(["timeOffset": .integer(offset), "duration": .integer(7_200_000)])
        ]))
    }

    private func mixed() -> [LibraryRecord] {
        [
            record("saved"),
            record("savedInProgress", offset: 60_000),
            record("temp", temp: true),
            record("tempInProgress", temp: true, offset: 60_000),
            record("removed", removed: true),
            record("removedTemp", removed: true, temp: true)
        ]
    }

    func testBookmarkedOnlyKeepsOnlySavedTitles() {
        let ids = LibraryWatchlistFilter.filter(mixed(), bookmarkedOnly: true).map(\.id)
        XCTAssertEqual(ids, ["saved", "savedInProgress"])
        XCTAssertEqual(ids, mixed().filter(\.bookmarked).map(\.id), "On must match the saved list the Watchlist already used")
    }

    func testBookmarkedOffAlsoListsUnstartedAutoAddedTitles() {
        let ids = LibraryWatchlistFilter.filter(mixed(), bookmarkedOnly: false).map(\.id)
        XCTAssertEqual(ids, ["saved", "savedInProgress", "temp"], "Off adds unstarted temp entries and never removed ones")
    }

    func testBookmarkedOffDropsStartedAutoAddedTitles() {
        let ids = LibraryWatchlistFilter.filter(mixed(), bookmarkedOnly: false).map(\.id)
        XCTAssertFalse(ids.contains("tempInProgress"), "A temp entry already in progress is not a watchlist entry")
    }
}

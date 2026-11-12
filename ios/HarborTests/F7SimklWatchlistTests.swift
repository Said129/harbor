import XCTest
@testable import Harbor

@MainActor final class F7SimklWatchlistTests: XCTestCase {
    func testSavingAddsToPlanToWatchAndRemovingSendsDesktopRemoval() throws {
        let target = try XCTUnwrap(SimklTarget.direct(Media(id: "tt0000001", type: "movie", name: "Sample")))
        let add = SimklWatchlistWrite.endpoint(saved: true, target: target)
        XCTAssertEqual(add.path, "/sync/add-to-list")
        XCTAssertEqual(add.method, "POST")
        let remove = SimklWatchlistWrite.endpoint(saved: false, target: target)
        XCTAssertEqual(remove.path, "/sync/history/remove")
        XCTAssertEqual(remove.method, "POST")
    }
}

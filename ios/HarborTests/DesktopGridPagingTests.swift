import XCTest
@testable import Harbor

final class DesktopGridPagingTests: XCTestCase {
    func testDuplicateOnlyProviderPagesAdvanceTheRawOffsetAndDoNotFinishTheGrid() {
        var paging = DesktopGridPaging()
        paging.received(20)
        XCTAssertEqual(paging.loaded, 20); XCTAssertEqual(paging.nextPage, 2)
        // The second response may contain twenty already visible titles.
        paging.received(20)
        XCTAssertEqual(paging.loaded, 40); XCTAssertEqual(paging.nextPage, 3); XCTAssertFalse(paging.finished)
        paging.received(1)
        XCTAssertEqual(paging.loaded, 41); XCTAssertFalse(paging.finished)
        paging.received(0)
        XCTAssertEqual(paging.loaded, 41); XCTAssertTrue(paging.finished)
    }
    func testTheFortyPageLimitIncludesAnInitialCompletePageAndNeverChangesAfterFinishing() {
        var paging = DesktopGridPaging(initialCount: 13)
        XCTAssertEqual(paging.page, 1); XCTAssertEqual(paging.loaded, 13)
        for _ in 2...40 { paging.received(13) }
        XCTAssertEqual(paging.page, 40); XCTAssertEqual(paging.loaded, 520); XCTAssertTrue(paging.finished)
        let finished = paging; paging.received(13); XCTAssertEqual(paging, finished)
        var empty = DesktopGridPaging(); empty.received(0)
        XCTAssertTrue(empty.finished); XCTAssertEqual(empty.page, 1)
    }
}

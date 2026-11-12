import XCTest
@testable import Harbor

final class F7TrackerProgressTests: XCTestCase {
    func testLoadIsFreshOnlyWithinTheLifetime() {
        let start = Date(timeIntervalSince1970: 1_000)
        XCTAssertFalse(TrackerListProgressRefresh.isFresh(last: nil, now: start))
        XCTAssertTrue(TrackerListProgressRefresh.isFresh(last: start, now: start.addingTimeInterval(119)))
        XCTAssertFalse(TrackerListProgressRefresh.isFresh(last: start, now: start.addingTimeInterval(120)))
    }

    func testKitsuNumberAcceptsOnlyPlainKitsuIds() {
        XCTAssertEqual(TrackerListProgressRefresh.kitsuNumber("kitsu:4321"), 4321)
        XCTAssertNil(TrackerListProgressRefresh.kitsuNumber("kitsu:"))
        XCTAssertNil(TrackerListProgressRefresh.kitsuNumber("kitsu:12:3"))
        XCTAssertNil(TrackerListProgressRefresh.kitsuNumber("kitsu:0"))
        XCTAssertNil(TrackerListProgressRefresh.kitsuNumber("mal:4321"))
        XCTAssertNil(TrackerListProgressRefresh.kitsuNumber("tt1234567"))
    }

    func testKitsuTitlePrefersTheAniListEntry() {
        let progress = TrackerListWatched.Progress(completed: false, progress: 3, total: 12)
        let other = TrackerListWatched.Progress(completed: true, progress: 12, total: 12)
        let entries: [String: TrackerListWatched.Progress] = ["anilist:77": progress, "mal:88": other]
        let copied = TrackerListProgressRefresh.aliasEntries(entries, kitsu: 9, anilistID: 77, malID: 88)
        XCTAssertEqual(copied, ["kitsu:9": progress])
    }

    func testKitsuTitleFallsBackToTheMyAnimeListEntry() {
        let progress = TrackerListWatched.Progress(completed: false, progress: 5, total: nil)
        let entries: [String: TrackerListWatched.Progress] = ["mal:88": progress]
        let copied = TrackerListProgressRefresh.aliasEntries(entries, kitsu: 9, anilistID: 77, malID: 88)
        XCTAssertEqual(copied, ["kitsu:9": progress])
    }

    func testKitsuTitleWithoutAnyListEntryCopiesNothing() {
        let progress = TrackerListWatched.Progress(completed: false, progress: 5, total: nil)
        let entries: [String: TrackerListWatched.Progress] = ["anilist:500": progress]
        XCTAssertTrue(TrackerListProgressRefresh.aliasEntries(entries, kitsu: 9, anilistID: nil, malID: nil).isEmpty)
        XCTAssertTrue(TrackerListProgressRefresh.aliasEntries(entries, kitsu: 9, anilistID: 77, malID: 88).isEmpty)
    }
}

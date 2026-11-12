import XCTest
@testable import Harbor

final class F7TrackerEditTests: XCTestCase {
    func testAniListChoicesCoverEveryStatusOnce() {
        let statuses = TrackerListEdit.aniListChoices.map { $0.status }
        XCTAssertEqual(statuses.count, AniListListStatus.allCases.count)
        XCTAssertEqual(Set(statuses), Set(AniListListStatus.allCases))
    }

    func testMyAnimeListChoicesCoverEveryStatusOnce() {
        let statuses = TrackerListEdit.malChoices.map { $0.status }
        XCTAssertEqual(statuses.count, MALListStatus.allCases.count)
        XCTAssertEqual(Set(statuses), Set(MALListStatus.allCases))
    }

    func testMyAnimeListStatusValuesAreTheApiNames() {
        XCTAssertEqual(MALListStatus.onHold.rawValue, "on_hold")
        XCTAssertEqual(MALListStatus.planToWatch.rawValue, "plan_to_watch")
    }

    func testAniListMutationsNameTheirOperation() {
        XCTAssertTrue(TrackerListEdit.aniListSaveQuery.contains("SaveMediaListEntry(mediaId: $mediaId, status: $status)"))
        XCTAssertTrue(TrackerListEdit.aniListProgressQuery.contains("progress: $progress"))
        XCTAssertTrue(TrackerListEdit.aniListDeleteQuery.contains("DeleteMediaListEntry(id: $id)"))
    }

    func testNextEpisodeStopsAtTheKnownTotal() {
        XCTAssertEqual(TrackerListEdit.nextProgress(3, total: 12), 4)
        XCTAssertEqual(TrackerListEdit.nextProgress(11, total: 12), 12)
        XCTAssertNil(TrackerListEdit.nextProgress(12, total: 12))
    }

    func testNextEpisodeWithoutATotalAddsOne() {
        XCTAssertEqual(TrackerListEdit.nextProgress(0, total: nil), 1)
        XCTAssertEqual(TrackerListEdit.nextProgress(5, total: 0), 6)
    }
}

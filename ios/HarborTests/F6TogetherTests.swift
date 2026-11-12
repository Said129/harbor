import XCTest
@testable import Harbor

/// The host's summon options (`context-menu.tsx`, `VIEW_LABELS`) and what a summon with a view opens (`together-summon-toast.tsx`).
final class F6TogetherTests: XCTestCase {
    func testTheHostCanCallGuestsToTheFiveScreensInDesktopOrder() {
        XCTAssertEqual(TogetherToastRules.summonViews.map { $0.view }, ["home", "discover", "anime", "queue", "addons"])
        XCTAssertEqual(TogetherToastRules.summonViews.map { $0.label }, ["Home", "Discover", "Anime", "My Library", "Addons"])
    }

    func testASummonToAViewCarriesTheSenderLabelAsItsHeadline() {
        let target = TogetherSummonTarget(view: "queue", label: "My Library")
        XCTAssertNotNil(TogetherToastRules.destination(target))
        XCTAssertEqual(TogetherToastRules.headline(target), "My Library")
    }
}

import XCTest
@testable import Harbor

final class DetailSettingsRulesTests: XCTestCase {
    func testCinemetaIsMatchedCaseInsensitively() {
        XCTAssertTrue(DetailSettingsRules.isCinemeta("com.linvo.cinemeta"))
        XCTAssertTrue(DetailSettingsRules.isCinemeta("Cinemeta"))
        XCTAssertFalse(DetailSettingsRules.isCinemeta("org.example.meta"))
        XCTAssertFalse(DetailSettingsRules.isCinemeta(nil))
    }

    func testMetaOrderIsUnchangedWhenPreferCustomIsOff() {
        let ids: [String?] = ["com.linvo.cinemeta", "org.a", nil, "org.b"]
        XCTAssertEqual(DetailSettingsRules.metaPlanOrder(addonIDs: ids, preferCustom: false), [0, 1, 2, 3])
    }

    func testPreferCustomMovesCinemetaLastAndKeepsEachGroupOrder() {
        let ids: [String?] = ["com.linvo.cinemeta", "org.a", nil, "org.b"]
        XCTAssertEqual(DetailSettingsRules.metaPlanOrder(addonIDs: ids, preferCustom: true), [1, 2, 3, 0])
    }

    func testPreferCustomWithoutCinemetaKeepsOrder() {
        let ids: [String?] = ["org.a", "org.b"]
        XCTAssertEqual(DetailSettingsRules.metaPlanOrder(addonIDs: ids, preferCustom: true), [0, 1])
    }

    func testPreferCustomWithOnlyCinemetaKeepsOrder() {
        let ids: [String?] = ["com.linvo.cinemeta"]
        XCTAssertEqual(DetailSettingsRules.metaPlanOrder(addonIDs: ids, preferCustom: true), [0])
    }

    func testEmptyPlanListGivesEmptyOrder() {
        XCTAssertEqual(DetailSettingsRules.metaPlanOrder(addonIDs: [], preferCustom: true), [])
    }

    func testRestoreReturnsKnownSectionWhenEnabled() {
        XCTAssertEqual(DetailSettingsRules.restoredDetailSection(saved: "detail-overview", enabled: true), "detail-overview")
    }

    func testRestoreIsNilWhenDisabled() {
        XCTAssertNil(DetailSettingsRules.restoredDetailSection(saved: "detail-overview", enabled: false))
    }

    func testRestoreIsNilForUnknownOrMissingSection() {
        XCTAssertNil(DetailSettingsRules.restoredDetailSection(saved: "detail-episodes-old", enabled: true))
        XCTAssertNil(DetailSettingsRules.restoredDetailSection(saved: nil, enabled: true))
    }

    @MainActor
    func testScrollMemoryRemembersPerTitle() {
        DetailScrollMemory.remember("detail-metadata", for: "tt-test-memory-a")
        DetailScrollMemory.remember("detail-hero", for: "tt-test-memory-b")
        XCTAssertEqual(DetailScrollMemory.section(for: "tt-test-memory-a"), "detail-metadata")
        XCTAssertEqual(DetailScrollMemory.section(for: "tt-test-memory-b"), "detail-hero")
        XCTAssertNil(DetailScrollMemory.section(for: "tt-test-memory-missing"))
    }
}

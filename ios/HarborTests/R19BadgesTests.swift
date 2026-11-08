import XCTest
@testable import Harbor

/// Desktop 0.9.132's watched badge and ratings switches: their defaults, their profile keys, and the pure gates behind them.
@MainActor
final class R19BadgesTests: XCTestCase {
    private let keys = ["showWatchedBadge", "showDetailRatings", "simklShowCommunityRatings"]

    func testDefaultsAreOn() {
        let saved = keys.map { UserDefaults.standard.object(forKey: $0) }
        defer {
            for (key, value) in zip(keys, saved) { UserDefaults.standard.set(value, forKey: key) }
            InterfacePreferences.shared.reloadPreferences()
        }
        keys.forEach { UserDefaults.standard.removeObject(forKey: $0) }
        InterfacePreferences.shared.reloadPreferences()
        XCTAssertTrue(InterfacePreferences.shared.showWatchedBadge)
        XCTAssertTrue(InterfacePreferences.shared.showDetailRatings)
        XCTAssertTrue(InterfacePreferences.shared.simklShowCommunityRatings)
    }

    func testKeysAreInProfileSettings() {
        for key in keys {
            XCTAssertTrue(ProfileSettingsStore.keys.contains(key), key)
        }
    }

    func testSimklChipFollowsCommunitySwitch() {
        let selected: Set<CardRatingProvider> = [.imdb, .simkl, .rt]
        XCTAssertEqual(CardRatingPolicy.selectedProviders(selected, simklCommunity: true), selected)
        XCTAssertEqual(CardRatingPolicy.selectedProviders(selected, simklCommunity: false), [.imdb, .rt])
    }

    func testDetailSimklLeavesRowWhenCommunityOff() {
        let hiddenOn = DetailRatings.hiddenForCommunity(["rt"], simklCommunity: true)
        XCTAssertEqual(hiddenOn, ["rt"])
        let hiddenOff = DetailRatings.hiddenForCommunity(["rt"], simklCommunity: false)
        XCTAssertEqual(hiddenOff, ["rt", "simkl"])

        let shown = DetailRatings.items(omdb: nil, mdblist: nil, simkl: 7.5, imdbID: "tt0000001", isShow: false, hidden: hiddenOn)
        XCTAssertEqual(shown.first { $0.id == "simkl" }?.value, "7.5")
        let gone = DetailRatings.items(omdb: nil, mdblist: nil, simkl: 7.5, imdbID: "tt0000001", isShow: false, hidden: hiddenOff)
        XCTAssertNil(gone.first { $0.id == "simkl" })
    }
}

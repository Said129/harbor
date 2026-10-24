import XCTest
@testable import Harbor

final class MusicExploreInterfaceSeedTests: XCTestCase {
    @MainActor func testPrepareAnUnconfiguredGuestWithOriginalExploreFilters() throws {
        guard try KeychainStore().read("account.v1", as: JSONValue.self) == nil else { XCTFail("Refuse configured account"); return }
        let context = AppProfileContext.shared; try context.prepare()
        guard context.profiles.profiles.count == 1, context.profiles.active?.credential == nil, context.configuration?.account == nil else { XCTFail("Refuse configured profiles"); return }
        if context.configuration?.guestAddons == nil { try context.save(HouseholdSourceAccount(account: nil, guestAddons: [])) }
        UserDefaults.standard.set("en", forKey: "uiLanguage")
        UserDefaults.standard.set("explore", forKey: "harbor.music.tab")
        UserDefaults.standard.set(MusicGenreFilters().encoded, forKey: "harbor.music.genres.explore.v1")
        UserDefaults.standard.set(true, forKey: "nativeGuide.initialized.v1"); UserDefaults.standard.set(true, forKey: "nativeGuide.completed.v1")
        XCTAssertEqual(try MusicExploreAsset.read().visibleGenres.count, 158)
    }
}

import XCTest
@testable import Harbor

final class MusicCatalogInterfaceSeedTests: XCTestCase {
    @MainActor func testPrepareAnUnconfiguredGuestForTheActualPublicCatalog() throws {
        guard try KeychainStore().read("account.v1", as: JSONValue.self) == nil else { XCTFail("Refuse configured account"); return }
        let context = AppProfileContext.shared; try context.prepare()
        guard context.profiles.profiles.count == 1, context.profiles.active?.credential == nil,
              context.configuration?.account == nil else { XCTFail("Refuse configured profiles"); return }
        if context.configuration?.guestAddons == nil { try context.save(HouseholdSourceAccount(account: nil, guestAddons: [])) }
        UserDefaults.standard.set("en", forKey: "uiLanguage"); UserDefaults.standard.set("forYou", forKey: "harbor.music.tab")
        UserDefaults.standard.set(true, forKey: "nativeGuide.initialized.v1"); UserDefaults.standard.set(true, forKey: "nativeGuide.completed.v1")
    }
}

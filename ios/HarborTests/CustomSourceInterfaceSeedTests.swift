import XCTest
@testable import Harbor

final class CustomSourceInterfaceSeedTests: XCTestCase {
    @MainActor func testPrepareAnOwnedCatalogAndPosterFoldersOnAFreshGuestWithoutAnyAccount() async throws {
        try await PageContinuationInterfaceSeedTests.prepareOwnedHistory()
        let context = AppProfileContext.shared, binding = try XCTUnwrap(context.binding)
        let addon = try await HarborService().install("http://127.0.0.1:18734/manifest.json")
        let disabled = Addon(manifest: .object(["id": .string("com.linvo.cinemeta")]), transportUrl: HarborService.cinemetaManifest, enabled: false)
        try context.save(HouseholdSourceAccount(account: nil, guestAddons: [addon, disabled]))
        let settings = ProfileSettingsStore.shared
        try settings.activate(owner: binding.settingsOwner, sharedOwner: binding.sharedSettingsOwner, migrateLegacy: true, legacyTMDB: { nil })
        try settings.setTMDBKey("", expectedOwner: binding.settingsOwner)
        UserDefaults.standard.set("classic", forKey: "homeMode")
        let preferences = PageCustomization(owner: binding.settingsOwner, page: "home")
        let raw: JSONValue = .object(["id": .string("owned-posters"), "title": .string("Owned portrait folders"), "folders": .array([
            .object(["id": .string("poster"), "title": .string("Owned portrait"), "tileShape": .string("POSTER"),
                "coverImageUrl": .string("http://127.0.0.1:18734/cover.png"),
                "catalogSources": .array([.object(["addonId": .string("owned.source.catalog"), "type": .string("movie"), "catalogId": .string("owned")])])])])])
        try preferences.importSources(String(decoding: JSONEncoder().encode(raw), as: UTF8.self), expected: preferences.scope)
        XCTAssertEqual(preferences.sourceRows.count, 1); XCTAssertNil(context.configuration?.account)
    }
}

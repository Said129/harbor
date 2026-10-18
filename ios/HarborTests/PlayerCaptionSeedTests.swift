import XCTest
@testable import Harbor

final class PlayerCaptionSeedTests: XCTestCase {
    @MainActor func testPrepareOrdinaryGuestForSyntheticPlayerCaptionUI() async throws {
        let keychain = KeychainStore()
        // Never print a saved account as the value of a failed assertion.
        guard try keychain.read("account.v1", as: JSONValue.self) == nil else {
            XCTFail("Refuse to replace a configured account in a test host"); return
        }
        let context = AppProfileContext.shared
        try context.prepare()
        // Let ordinary application startup finish its first source migration.
        // Otherwise an in-flight default-addon install could replace the fixture.
        for _ in 0..<300 {
            if context.configuration?.guestAddons != nil && ProfileSettingsStore.shared.owner == context.binding?.settingsOwner { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        guard context.ready, context.configuration?.account == nil,
              let addons = context.configuration?.guestAddons,
              addons.allSatisfy({ $0.manifest["id"].string == "com.linvo.cinemeta" || $0.manifest["id"].string == "harbor.synthetic.caption" }),
              context.profiles.profiles.count == 1, context.profiles.active?.credential == nil,
              context.profiles.active?.desktop.isKid == false,
              let binding = context.binding, ProfileSettingsStore.shared.owner == binding.settingsOwner else {
            XCTFail("Refuse to replace configured, locked or unready profile data"); return
        }
        let previous = try await LibraryCache().readSnapshot(owner: binding.progressOwner)
        guard previous.records.allSatisfy({ $0["_id"].string == "tt4644488" && $0["_synthetic-caption"] == .bool(true) }) else {
            XCTFail("Refuse to replace an existing guest library"); return
        }
        let manifest: JSONValue = .object([
            "id": .string("harbor.synthetic.caption"), "version": .string("1.0.0"),
            "name": .string("Owned synthetic test clip"), "description": .string("Local player UI fixture, not an anime video"),
            "types": .array([.string("series")]), "catalogs": .array([]),
            "resources": .array([.object(["name": .string("stream"), "types": .array([.string("series")]), "idPrefixes": .array([.string("tt4644488")])])])
        ])
        let cinemeta = try await HarborService().install(HarborService.cinemetaManifest)
        let fixture = Addon(manifest: manifest, transportUrl: "http://127.0.0.1:48192/manifest.json", enabled: true)
        try context.save(HouseholdSourceAccount(account: nil, guestAddons: [cinemeta, fixture]))
        try keychain.write([cinemeta, fixture], key: "addons.v1")
        let raw: JSONValue = .object([
            "_id": .string("tt4644488"), "type": .string("series"), "name": .string("Dragon Ball Super"),
            "_synthetic-caption": .bool(true),
            "removed": .bool(false), "temp": .bool(false), "_mtime": .string(ISO8601DateFormatter().string(from: Date())),
            "state": .object(["season": .integer(5), "episode": .integer(23), "video_id": .string("tt4644488:5:23"),
                              "timeOffset": .integer(2_000), "duration": .integer(1_400_000)])
        ])
        try await LibraryCache().save([raw], owner: binding.progressOwner)
        let library = LibraryModel()
        await library.setSession(nil, personalOwner: binding.personalOwner, guestOwner: binding.progressOwner, synchronize: false)
        guard let record = library.items.first(where: { $0.id == "tt4644488" }) else { XCTFail("Ordinary guest library was not restored"); return }
        library.showContinuing(record)
        let defaults = UserDefaults.standard
        defaults.set("es", forKey: "uiLanguage")
        defaults.set(true, forKey: "nativeGuide.initialized.v1"); defaults.set(true, forKey: "nativeGuide.completed.v1")
        defaults.set(false, forKey: "interface.autoRotateBanners")
        // Use the ordinary player setting so the controls remain visible while
        // XCTest reads captions and taps next; no application test mode is used.
        PlaybackPreferences.shared.options.autoHideControls = false
        XCTAssertTrue(ProfileSettingsStore.shared.saveCurrent())
    }
}

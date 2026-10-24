import XCTest
@testable import Harbor

final class MusicCollectionInterfaceSeedTests: XCTestCase {
    @MainActor func testPrepareOneOwnedAudioFileInAnUnconfiguredFreshGuest() async throws {
        guard try KeychainStore().read("account.v1", as: JSONValue.self) == nil else { XCTFail("Refuse a configured account"); return }
        let context = AppProfileContext.shared; try context.prepare()
        guard context.profiles.profiles.count == 1, context.profiles.active?.credential == nil,
              context.configuration?.account == nil, let owner = context.binding?.personalOwner else { XCTFail("Refuse configured profiles"); return }
        if context.configuration?.guestAddons == nil { try context.save(HouseholdSourceAccount(account: nil, guestAddons: [])) }
        let library = MusicLibrary(owner: owner)
        XCTAssertTrue(library.ready); XCTAssertTrue(library.records.isEmpty)
        let file = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "owned-tone", withExtension: "wav", subdirectory: "Fixtures"))
        library.importFiles([file]); let deadline = Date(timeIntervalSinceNow: 30)
        while library.importing, Date() < deadline { try await Task.sleep(for: .milliseconds(50)) }
        XCTAssertFalse(library.importing); XCTAssertNil(library.error); XCTAssertEqual(library.records.count, 1)
        let collections = MusicCollections.shared; collections.prepare(owner: owner)
        XCTAssertEqual(collections.snapshot(owner: owner), MusicCollectionsDocument())
        UserDefaults.standard.set("en", forKey: "uiLanguage")
        UserDefaults.standard.set(true, forKey: "nativeGuide.initialized.v1")
        UserDefaults.standard.set(true, forKey: "nativeGuide.completed.v1")
    }
}

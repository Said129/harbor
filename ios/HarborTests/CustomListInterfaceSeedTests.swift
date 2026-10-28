import XCTest
@testable import Harbor

final class CustomListInterfaceSeedTests: XCTestCase {
    @MainActor func testPrepareOwnedListsForBothRealLibraryInterfacesOnAFreshGuest() async throws {
        let (binding, _) = try ContinuePrivacyInterfaceSeedTests.prepareOwnedSharedGuest()
        let existing = try await CustomListDisk.shared.read(owner: binding.settingsOwner)
        guard existing == nil else { XCTFail("Refuse an existing custom-list store"); throw HarborError(code: "owned-seed-safety") }
        let store = CustomListStore(owner: binding.settingsOwner)
        await store.load(); XCTAssertTrue(store.ready)
        await store.apply(.create("Owned weekend", "Two movies to keep close.", id: "owned-weekend"))
        for (id, title) in [("owned-list:film-a", "Owned film A"), ("owned-list:film-b", "Owned film B")] {
            await store.apply(.add("owned-weekend", .object(["id": .string(id), "type": .string("movie"), "name": .string(title)])))
        }
        await store.apply(.create("Owned rewatches", "", id: "owned-rewatches"))
        XCTAssertEqual(store.lists.count, 2); XCTAssertEqual(store.lists.first(where: { $0.id == "owned-weekend" })?.items.count, 2)
        XCTAssertNil(store.error); XCTAssertFalse(store.unsaved)
        let reopened = try await CustomListDisk.shared.read(owner: binding.settingsOwner)
        XCTAssertEqual(CustomListsDocument(try XCTUnwrap(reopened)).sorted.count, 2)
        let defaults = UserDefaults.standard
        defaults.set("poster", forKey: "rowCardStyle"); defaults.set(1.0, forKey: "posterScale")
        XCTAssertTrue(ProfileSettingsStore.shared.saveCurrent())
    }
}

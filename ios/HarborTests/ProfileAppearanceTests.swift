import XCTest
import UIKit
@testable import Harbor

@MainActor private final class AppearanceRosterMemory: HouseholdProfilePersistence {
    var value: HouseholdProfileState?
    var failWrite = false
    var writes = 0
    func readHousehold(_ key: String) throws -> HouseholdProfileState? { value }
    func writeHousehold(_ value: HouseholdProfileState, key: String) throws {
        if failWrite { throw HarborError(code: "synthetic-roster-write") }
        self.value = value; writes += 1
    }
}
@MainActor private final class AppearancePhotoMemory: ProfilePhotoPersistence {
    var values: [String: Data] = [:]
    var reads = 0
    var writes = 0
    var failWrite = false
    func readPhoto(_ digest: String) throws -> Data? { reads += 1; return values[digest] }
    func writePhoto(_ data: Data, digest: String) throws {
        if failWrite { throw HarborError(code: "synthetic-photo-write") }
        values[digest] = data; writes += 1
    }
}
@MainActor private final class AppearanceLegacyMemory: ProfileAppearancePersistence {
    var value: MobileProfile?
    var failRead = false
    var reads = 0
    var writes = 0
    func readAppearance(_ key: String) throws -> MobileProfile? {
        reads += 1; if failRead { throw HarborError(code: "synthetic-legacy-read") }; return value
    }
    func writeAppearance(_ value: MobileProfile, key: String) throws { self.value = value; writes += 1 }
}

@MainActor final class ProfileAppearanceTests: XCTestCase {
    private let scope = HouseholdProfileScope.local(owner: "synthetic-appearance")
    private func image(_ color: UIColor = .red) throws -> Data {
        try XCTUnwrap(UIGraphicsImageRenderer(size: CGSize(width: 48, height: 32)).image { context in
            color.setFill(); context.fill(CGRect(x: 0, y: 0, width: 48, height: 32))
        }.jpegData(compressionQuality: 0.85))
    }
    private func store(_ memory: AppearanceRosterMemory, photos: ProfilePhotoStore) -> HouseholdProfileStore {
        HouseholdProfileStore(scope: scope, persistence: memory, photos: photos)
    }
    private func facade(_ store: HouseholdProfileStore, row: DeviceHouseholdProfile, photos: ProfilePhotoStore, legacy: AppearanceLegacyMemory) -> ProfilePreferences {
        let value = ProfilePreferences(owner: store.appearanceOwner(row), persistence: legacy, photos: photos, didChange: { _, _ in })
        value.bindHousehold(store, id: row.id); return value
    }

    func testBothEditorsProjectOneNameColorAndStockAvatarWithoutLegacyWrites() async throws {
        let memory = AppearanceRosterMemory(), blobs = AppearancePhotoMemory(), legacy = AppearanceLegacyMemory()
        let photos = ProfilePhotoStore(persistence: blobs), profiles = store(memory, photos: photos)
        let row = try profiles.create(name: "Initial")
        let one = facade(profiles, row: row, photos: photos, legacy: legacy)
        let two = facade(profiles, row: row, photos: photos, legacy: legacy)
        let avatar = try XCTUnwrap(DesktopAvatar.catalog.first)
        var draft = HouseholdProfileDraft(profile: row)
        draft.name = "From selector"; draft.color = "#a78bfa"; draft.avatar = .string("/avatars/\(avatar.id).webp")
        _ = try await profiles.saveEditor(draft)
        XCTAssertEqual(one.value.name, "From selector"); XCTAssertEqual(two.value.avatar, avatar.id)
        one.update { $0.name = "From account"; $0.color = "34d399" }
        XCTAssertEqual(profiles.active?.desktop.name, "From account"); XCTAssertEqual(two.value.color, "34d399")
        XCTAssertEqual(legacy.writes, 0); XCTAssertEqual(blobs.reads, 0)
    }
    func testImmutableImagesLoadOnceAndRejectCorruptionAndInvalidImageBytes() throws {
        let memory = AppearancePhotoMemory(), photos = ProfilePhotoStore(persistence: memory), data = try image()
        let digest = try photos.stage(data, account: "synthetic-account")
        XCTAssertEqual(try photos.stage(data, account: "synthetic-account"), digest); XCTAssertEqual(memory.writes, 1)
        let restarted = ProfilePhotoStore(persistence: memory)
        XCTAssertEqual(try restarted.photo(digest).photo, data)
        let reads = memory.reads
        for _ in 0..<20 { XCTAssertEqual(try restarted.photo(digest).photo, data); XCTAssertNotNil(restarted.cachedPhoto(digest)) }
        XCTAssertEqual(memory.reads, reads)
        memory.values[digest] = Data("corrupt".utf8)
        XCTAssertThrowsError(try ProfilePhotoStore(persistence: memory).photo(digest))
        XCTAssertThrowsError(try photos.stage(Data("not an image".utf8), account: nil))
        XCTAssertThrowsError(try photos.photo("../bad-key"))
    }
    func testLegacyPhotoMigratesOnceAndCannotReturnAfterExplicitRemovalOrRestart() throws {
        let memory = AppearanceRosterMemory(), blobs = AppearancePhotoMemory(), legacy = AppearanceLegacyMemory()
        let photos = ProfilePhotoStore(persistence: blobs), profiles = store(memory, photos: photos), data = try image()
        var old = MobileProfile(); old.photo = data; old.photoAccountID = "synthetic-account"; legacy.value = old
        let row = try profiles.create(name: "Saved name", legacyOwner: "synthetic-old-owner")
        let appearance = facade(profiles, row: row, photos: photos, legacy: legacy)
        XCTAssertTrue(appearance.ready); XCTAssertEqual(appearance.value.photo, data)
        XCTAssertEqual(profiles.active?.desktop.name, "Saved name"); XCTAssertEqual(legacy.writes, 0)
        appearance.update { $0.photo = nil; $0.initialsAvatar = true }
        XCTAssertNil(profiles.active?.localPhotoID)
        let restarted = store(memory, photos: ProfilePhotoStore(persistence: blobs))
        let active = try XCTUnwrap(restarted.active)
        let again = facade(restarted, row: active, photos: ProfilePhotoStore(persistence: blobs), legacy: legacy)
        XCTAssertTrue(again.ready); XCTAssertNil(again.value.photo); XCTAssertTrue(again.value.initialsAvatar == true)
        XCTAssertEqual(blobs.writes, 1); XCTAssertEqual(legacy.value?.photo, data)
    }
    func testFailedMigrationRetainsTheLegacyPhotoAndCanRetryWithoutDuplicatingProfiles() throws {
        let memory = AppearanceRosterMemory(), blobs = AppearancePhotoMemory(), legacy = AppearanceLegacyMemory()
        let photos = ProfilePhotoStore(persistence: blobs), profiles = store(memory, photos: photos)
        var old = MobileProfile(); old.photo = try image(); legacy.value = old
        let row = try profiles.create(name: "Existing", legacyOwner: "synthetic-old-owner"), before = profiles.state
        blobs.failWrite = true
        let appearance = facade(profiles, row: row, photos: photos, legacy: legacy)
        XCTAssertFalse(appearance.ready); XCTAssertEqual(profiles.state, before); XCTAssertEqual(legacy.writes, 0)
        blobs.failWrite = false; appearance.reload()
        XCTAssertTrue(appearance.ready); XCTAssertEqual(profiles.profiles.count, 1); XCTAssertEqual(appearance.value.photo, old.photo)
    }
    func testFailedBlobAndRosterWritesKeepTheEntirePreviousAppearance() throws {
        let memory = AppearanceRosterMemory(), blobs = AppearancePhotoMemory(), legacy = AppearanceLegacyMemory()
        let photos = ProfilePhotoStore(persistence: blobs), profiles = store(memory, photos: photos)
        let row = try profiles.create(name: "Before"), appearance = facade(profiles, row: row, photos: photos, legacy: legacy)
        let first = try image(), second = try image(.blue)
        appearance.update { $0.photo = first }
        let before = profiles.state, writes = memory.writes
        blobs.failWrite = true
        appearance.update { $0.name = "Must not save"; $0.photo = second }
        XCTAssertEqual(profiles.state, before); XCTAssertEqual(appearance.value.photo, first)
        blobs.failWrite = false; memory.failWrite = true
        appearance.update { $0.name = "Also must not save"; $0.color = "34d399"; $0.photo = second }
        XCTAssertEqual(profiles.state, before); XCTAssertEqual(appearance.value.photo, first); XCTAssertEqual(memory.writes, writes)
        XCTAssertEqual(legacy.writes, 0)
        memory.failWrite = false; appearance.reload()
        XCTAssertTrue(appearance.ready); XCTAssertEqual(appearance.value.name, "Before")
    }
    func testMissingImageOnRestartDisablesEditingAndKeepsTheRosterReference() throws {
        let memory = AppearanceRosterMemory(), blobs = AppearancePhotoMemory(), legacy = AppearanceLegacyMemory()
        let photos = ProfilePhotoStore(persistence: blobs), profiles = store(memory, photos: photos)
        let row = try profiles.create(name: "Existing"), appearance = facade(profiles, row: row, photos: photos, legacy: legacy)
        let data = try image(); appearance.update { $0.photo = data }
        let before = profiles.state, digest = try XCTUnwrap(profiles.active?.localPhotoID)
        let payload = blobs.values.removeValue(forKey: digest)
        let restartedPhotos = ProfilePhotoStore(persistence: blobs), restarted = store(memory, photos: restartedPhotos)
        let again = facade(restarted, row: try XCTUnwrap(restarted.active), photos: restartedPhotos, legacy: legacy)
        XCTAssertFalse(again.ready); again.update { $0.name = "Cannot replace missing image" }
        XCTAssertEqual(restarted.state, before)
        blobs.values[digest] = payload; again.reload()
        XCTAssertTrue(again.ready); XCTAssertEqual(again.value.photo, data)
    }
    func testOwnerMismatchAndLateEditsCannotModifyOrExposeAnotherProfilePhoto() async throws {
        let memory = AppearanceRosterMemory(), blobs = AppearancePhotoMemory(), legacy = AppearanceLegacyMemory()
        let photos = ProfilePhotoStore(persistence: blobs), profiles = store(memory, photos: photos)
        let one = try profiles.create(name: "One"), two = try profiles.create(name: "Two")
        let appearance = facade(profiles, row: one, photos: photos, legacy: legacy)
        let data = try image(); appearance.update { $0.photo = data }
        let wrong = ProfilePreferences(owner: "wrong-owner", persistence: legacy, photos: photos, didChange: { _, _ in })
        wrong.bindHousehold(profiles, id: one.id)
        XCTAssertFalse(wrong.ready); XCTAssertNil(wrong.value.photo); XCTAssertTrue(wrong.value.name.isEmpty)
        _ = try await profiles.select(two.id); let before = profiles.state
        appearance.update { $0.name = "Late callback"; $0.photo = nil }
        XCTAssertEqual(profiles.state, before); XCTAssertEqual(profiles.active?.id, two.id)
    }
    func testManagerPhotoAndMetadataCommitTogetherAndStockChoiceClearsTheLocalPhoto() async throws {
        let memory = AppearanceRosterMemory(), blobs = AppearancePhotoMemory(), legacy = AppearanceLegacyMemory()
        let photos = ProfilePhotoStore(persistence: blobs), profiles = store(memory, photos: photos)
        let row = try profiles.create(name: "Before"), appearance = facade(profiles, row: row, photos: photos, legacy: legacy)
        var draft = HouseholdProfileDraft(profile: row)
        draft.name = "After"; draft.photo = .replace(try image(), account: nil)
        let before = profiles.state, writes = memory.writes
        memory.failWrite = true
        do { _ = try await profiles.saveEditor(draft); XCTFail("The final roster write must fail") } catch {}
        XCTAssertEqual(profiles.state, before); XCTAssertFalse(profiles.verifying)
        memory.failWrite = false
        let changed = try await profiles.saveEditor(draft)
        XCTAssertEqual(memory.writes, writes + 1); XCTAssertEqual(appearance.value.name, "After")
        XCTAssertNotNil(appearance.value.photo); XCTAssertEqual(changed.desktop.raw["avatar"], .null)
        draft = HouseholdProfileDraft(profile: changed)
        draft.avatar = .string("/avatars/harbor_animal_01.webp"); draft.photo = .remove
        _ = try await profiles.saveEditor(draft)
        XCTAssertNil(appearance.value.photo); XCTAssertNil(profiles.active?.localPhotoID)
    }
    func testDesktopNullAvatarKeepsLocalImageButAStockChoiceReplacesItWithoutChangingDeviceIdentity() throws {
        let memory = AppearanceRosterMemory(), blobs = AppearancePhotoMemory(), legacy = AppearanceLegacyMemory()
        let photos = ProfilePhotoStore(persistence: blobs), profiles = store(memory, photos: photos)
        let row = try profiles.create(name: "Before"), appearance = facade(profiles, row: row, photos: photos, legacy: legacy)
        let data = try image(); appearance.update { $0.photo = data }
        let current = try XCTUnwrap(profiles.active), digest = current.localPhotoID
        let null = try current.desktop.editing(["name": .string("Desktop"), "avatar": .null], at: 30)
        try profiles.adopt(DesktopHouseholdRoster(.object(["profiles": .array([null.portable])])), revision: 1)
        XCTAssertEqual(profiles.active?.id, row.id); XCTAssertEqual(profiles.active?.localPhotoID, digest)
        XCTAssertEqual(appearance.value.photo, data); XCTAssertEqual(appearance.value.name, "Desktop")
        let stock = try null.editing(["avatar": .string("/avatars/harbor_animal_01.webp")], at: 40)
        try profiles.adopt(DesktopHouseholdRoster(.object(["profiles": .array([stock.portable])])), revision: 2)
        XCTAssertEqual(profiles.active?.id, row.id); XCTAssertNil(appearance.value.photo); XCTAssertEqual(appearance.value.avatar, "harbor_animal_01")
    }
    func testPhotoReferencesAndAccountMarkersNeverEnterThePortableRosterAndOldDeviceRecordsStillDecode() throws {
        let memory = AppearanceRosterMemory(), blobs = AppearancePhotoMemory(), legacy = AppearanceLegacyMemory()
        let photos = ProfilePhotoStore(persistence: blobs), profiles = store(memory, photos: photos)
        let row = try profiles.create(name: "Existing"), appearance = facade(profiles, row: row, photos: photos, legacy: legacy)
        let data = try image(); appearance.update { $0.photo = data; $0.photoAccountID = "synthetic-private-account" }
        let wire = String(decoding: try JSONEncoder().encode(profiles.state.wireValue), as: UTF8.self)
        for key in ["localPhotoID", "appearanceInitialized", "synthetic-private-account", data.base64EncodedString()] { XCTAssertFalse(wire.contains(key)) }
        var old = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(profiles.state)) as? [String: Any])
        var rows = try XCTUnwrap(old["profiles"] as? [[String: Any]])
        rows[0].removeValue(forKey: "localPhotoID"); rows[0].removeValue(forKey: "appearanceInitialized"); old["profiles"] = rows
        let decoded = try JSONDecoder().decode(HouseholdProfileState.self, from: JSONSerialization.data(withJSONObject: old))
        XCTAssertNil(decoded.profiles[0].localPhotoID); XCTAssertNil(decoded.profiles[0].appearanceInitialized)
        XCTAssertEqual(try decoded.validated().profiles[0].id, row.id)
    }
    func testInitializedProfilesIgnoreAnUnreadableLegacyCopyAndRemoteAvatarsDoNotMasqueradeAsBundledAssets() throws {
        let memory = AppearanceRosterMemory(), blobs = AppearancePhotoMemory(), legacy = AppearanceLegacyMemory()
        let photos = ProfilePhotoStore(persistence: blobs), profiles = store(memory, photos: photos)
        let row = try profiles.create(name: "Authoritative"); legacy.failRead = true
        let appearance = facade(profiles, row: row, photos: photos, legacy: legacy)
        XCTAssertTrue(appearance.ready); appearance.update { $0.color = "34d399" }
        XCTAssertEqual(profiles.active?.desktop.raw["color"], .string("#34d399"))
        let url = "https://images.example.test/harbor_animal_01.webp"
        let remote = HouseholdAppearanceBinding.project(name: "Remote", color: nil, avatar: .string(url))
        XCTAssertEqual(remote.remoteAvatar, url)
        let invalid = HouseholdAppearanceBinding.project(name: "Initial", color: nil, avatar: .string("javascript:alert(1)"))
        XCTAssertTrue(invalid.initialsAvatar == true); XCTAssertNil(invalid.remoteAvatar)
    }
}

import XCTest
@testable import Harbor

@MainActor private final class OwnedSimklSettings: ProfileSettingsPersistence {
    var state: ProfileSettingsState?
    func readProfileSettings() throws -> ProfileSettingsState? { state }
    func writeProfileSettings(_ value: ProfileSettingsState) throws { state = value }
}
@MainActor final class SimklLibraryPersistenceTests: XCTestCase {
    private func snapshot() -> SimklLibrarySnapshot {
        let item = SimklListItem(kind: .movie, ids: .init(.object(["simkl": .integer(5)])), title: "Owned Movie", status: .completed, watchedEpisodes: [])
        return .init(items: [item.id: item], lastSync: "2023-01-01T00:00:00Z")
    }
    func testActualPrivateDiskPersistsPerOwnerAndTokenFingerprintWithoutWritingCredentials() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("owned-simkl-cache-" + UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let disk = SimklLibraryDisk(root: root), snapshot = snapshot(), token = "owned-private-token-" + UUID().uuidString
        let fingerprint = EBookShelf.hash(token)
        try await disk.write(snapshot, owner: "owned-first", fingerprint: fingerprint)
        let restored = try await disk.read(owner: "owned-first", fingerprint: fingerprint)
        let wrongOwner = try await disk.read(owner: "owned-second", fingerprint: fingerprint)
        let changedAccount = try await disk.read(owner: "owned-first", fingerprint: EBookShelf.hash("owned-different-token"))
        XCTAssertEqual(restored, snapshot); XCTAssertNil(wrongOwner); XCTAssertNil(changedAccount)
        let file = root.appendingPathComponent(EBookShelf.hash("owned-first") + ".json")
        let raw = try String(contentsOf: file, encoding: .utf8); XCTAssertFalse(raw.contains(token)); XCTAssertFalse(raw.contains("accessToken"))
        let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
        XCTAssertEqual(attributes[.protectionKey] as? FileProtectionType, .completeUntilFirstUserAuthentication)
        XCTAssertEqual(try root.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup, true)
        try await disk.remove(owner: "owned-first"); let removed = try await disk.read(owner: "owned-first", fingerprint: fingerprint); XCTAssertNil(removed)
    }
    func testRevisionRejectsOldRefreshAndAnAccountChangeClearsItsVisibleList() async throws {
        let store = SimklLibraryStore(owner: "owned", disk: OwnedSimklLibraryDisk())
        store.bind("owned-token"); let fingerprint = try XCTUnwrap(store.fingerprint), revision = store.revision
        try await store.commit(snapshot(), fingerprint: fingerprint, expectedRevision: revision)
        do { try await store.commit(.init(), fingerprint: fingerprint, expectedRevision: revision); XCTFail("An old full pull replaced a later mutation") } catch is CancellationError { }
        XCTAssertEqual(store.snapshot.items.count, 1)
        store.bind("owned-other-token"); XCTAssertTrue(store.snapshot.items.isEmpty); XCTAssertFalse(store.restored)
        try await store.restore(); XCTAssertTrue(store.snapshot.items.isEmpty)
        store.bind(nil); try await store.clear(); XCTAssertTrue(store.snapshot.items.isEmpty)
    }
    func testRatingPreferenceFollowsItsProfileAndThePortableDocumentCannotContainTheAccountToken() throws {
        let name = "owned-simkl-settings-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name)); defer { defaults.removePersistentDomain(forName: name) }
        let memory = OwnedSimklSettings(), store = ProfileSettingsStore(defaults: defaults, persistence: memory)
        XCTAssertTrue(ProfileSettingsStore.keys.contains("simklEnableUserRatings"))
        XCTAssertFalse(ProfileSettingsStore.keys.contains("native-simkl-session-v1"))
        try store.activate(owner: "first", sharedOwner: "first", migrateLegacy: false)
        defaults.set(false, forKey: "simklEnableUserRatings"); XCTAssertTrue(store.saveCurrent())
        try store.activate(owner: "second", sharedOwner: "first", migrateLegacy: false)
        XCTAssertNil(defaults.object(forKey: "simklEnableUserRatings")); defaults.set(true, forKey: "simklEnableUserRatings"); XCTAssertTrue(store.saveCurrent())
        try store.activate(owner: "first", sharedOwner: "first", migrateLegacy: false); XCTAssertFalse(defaults.bool(forKey: "simklEnableUserRatings"))
        let reopened = ProfileSettingsStore(defaults: defaults, persistence: memory)
        try reopened.activate(owner: "second", sharedOwner: "first", migrateLegacy: false); XCTAssertTrue(defaults.bool(forKey: "simklEnableUserRatings"))
        XCTAssertFalse(try String(decoding: JSONEncoder().encode(XCTUnwrap(memory.state)), as: UTF8.self).contains("accessToken"))
    }
}

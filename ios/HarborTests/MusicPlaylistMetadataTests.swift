import XCTest
@testable import Harbor

@MainActor final class MusicPlaylistMetadataTests: XCTestCase {
    func testMixedCatalogAndLocalRecordingsReopenWithMetadataOrderAndSharedUpdates() throws {
        let disk = OwnedMusicPlaylistPersistence(), owner = "owned-playlist-metadata"
        let store = MusicPlaylistStore(owner: owner, persistence: disk)
        let first = try XCTUnwrap(store.create("Night music")), second = try XCTUnwrap(store.create("Night music"))
        XCTAssertEqual(second.name, "Night music (1)")
        let catalog = track("itunes:track:42", connector: "catalog", explicit: true, version: "Original")
        let local = track("local:owned", connector: "local")
        let added = try XCTUnwrap(store.add([catalog, local, catalog], to: first.id))
        XCTAssertEqual(added.trackIds, [catalog.id, local.id])
        let stamp = try XCTUnwrap(added.trackAddedAt[catalog.id])
        XCTAssertNotNil(store.add([catalog], to: second.id))
        var replacement = track(catalog.id, connector: "catalog", title: "Updated recording")
        replacement.collectionOrigin = .init(id: "original-credit", connectorId: "catalog", title: "Recording credit")
        replacement.quality = .init(codec: "flac", lossless: true, sampleRateHz: 48000, bitDepth: 24, bitrateKbps: nil)
        XCTAssertNotNil(store.add([replacement], to: second.id))
        let reopened = MusicPlaylistStore(owner: owner, persistence: disk)
        let one = reopened.recordings(in: first.id), two = reopened.recordings(in: second.id)
        XCTAssertEqual(one.map(\.id), [catalog.id, local.id]); XCTAssertEqual(two.map(\.id), [catalog.id])
        XCTAssertEqual(one.first?.title, "Updated recording"); XCTAssertEqual(one.first, two.first)
        XCTAssertEqual(one.first?.explicit, true); XCTAssertEqual(one.first?.version, "Original")
        XCTAssertEqual(one.first?.collectionOrigin, replacement.collectionOrigin); XCTAssertEqual(one.first?.quality, replacement.quality)
        XCTAssertEqual(reopened.playlists.first { $0.id == first.id }?.trackAddedAt[catalog.id], stamp)
        reopened.move(local.id, in: first.id, to: 0)
        XCTAssertEqual(reopened.recordings(in: first.id).map(\.id), [local.id, catalog.id])
        reopened.remove(catalog.id, from: first.id)
        XCTAssertEqual(reopened.recordings(in: second.id).first?.title, "Updated recording")
        XCTAssertTrue(MusicPlaylistStore(owner: owner + "-other", persistence: disk).playlists.isEmpty)
    }
    func testBatchFailureDoesNotPublishPartialMembershipOrMetadataAndRetryUsesTheSameList() throws {
        let disk = OwnedMusicPlaylistPersistence(), store = MusicPlaylistStore(owner: "owned-batch", persistence: disk)
        let list = try XCTUnwrap(store.create("Saved seasonal copy"))
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let baseline = try encoder.encode(disk.documents[store.owner])
        disk.failWrite = true
        XCTAssertNil(store.add([track("catalog:one"), track("catalog:two")], to: list.id))
        XCTAssertTrue(store.playlists[0].trackIds.isEmpty); XCTAssertTrue(store.tracks.isEmpty)
        XCTAssertEqual(try encoder.encode(disk.documents[store.owner]), baseline)
        disk.failWrite = false
        XCTAssertNotNil(store.add([track("catalog:one"), track("catalog:two")], to: list.id))
        XCTAssertEqual(store.playlists.count, 1); XCTAssertEqual(store.playlists[0].id, list.id)
        XCTAssertEqual(store.recordings(in: list.id).map(\.id), ["catalog:one", "catalog:two"])
        let durable = MusicPlaylistStore(owner: store.owner, persistence: disk)
        disk.failRead = true
        let failed = MusicPlaylistStore(owner: store.owner, persistence: disk)
        XCTAssertFalse(failed.ready); XCTAssertNil(failed.create("Must not overwrite unread data"))
        XCTAssertEqual(durable.recordings(in: list.id).count, 2)
        disk.failRead = false
        XCTAssertEqual(MusicPlaylistStore(owner: store.owner, persistence: disk).recordings(in: list.id).count, 2)
    }
    func testSavedRecordingDefaultsNullableMetadataAndEphemeralURLsMatchTheOriginalDatabaseSQL() throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "music-playlist-metadata-reference", withExtension: "json", subdirectory: "Fixtures"))
        let fixture = try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: url))
        XCTAssertEqual(fixture["actual_original_upsert_and_url_sql_executed"], .bool(true))
        XCTAssertEqual(fixture["complete_original_rust_function_executed"], .bool(false))
        XCTAssertEqual(fixture["original_modules"].objectValue.count, 2); XCTAssertEqual(fixture["cases"].array.count, 8)
        let store = MusicPlaylistStore(owner: "owned-source-recordings", persistence: OwnedMusicPlaylistPersistence())
        let list = try XCTUnwrap(store.create("Source database reference"))
        for row in fixture["cases"].array {
            let input = try JSONDecoder().decode(MusicTrack.self, from: JSONEncoder().encode(row["input"]))
            XCTAssertNotNil(store.add([input], to: list.id))
            let recording = try XCTUnwrap(store.recordings(in: list.id).first { $0.id == input.id })
            let actual = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(recording))
            for (key, value) in row["expected"].objectValue { XCTAssertEqual(actual[key], value, key + " in " + input.id) }
        }
    }
    func testLegacyKeychainMembershipUpgradesOnSuccessfulWriteAndRetainsTheOriginalOnFailure() throws {
        let owner = "owned-legacy-music-" + UUID().uuidString, keychain = KeychainStore()
        let oldKey = "music-playlists-" + EBookShelf.hash(owner), newKey = "music-playlists-v2-" + EBookShelf.hash(owner)
        defer { try? keychain.remove(oldKey); try? keychain.remove(newKey) }
        let id = UUID().uuidString
        let legacy = [MusicPlaylist(id: id, name: "Existing list", createdAt: "1", updatedAt: "2", trackIds: ["old-local"], trackAddedAt: ["old-local": "1"])]
        try keychain.write(legacy, key: oldKey)
        let store = MusicPlaylistStore(owner: owner)
        XCTAssertTrue(store.ready); XCTAssertEqual(store.playlists.first?.trackIds, ["old-local"])
        XCTAssertNil(try keychain.read(newKey, as: MusicPlaylistDocument.self))
        XCTAssertNotNil(store.add([track("new-catalog")], to: id))
        XCTAssertEqual(MusicPlaylistStore(owner: owner).playlists.first?.trackIds, ["old-local", "new-catalog"])
        XCTAssertEqual(try keychain.read(oldKey, as: [MusicPlaylist].self)?.first?.trackIds, ["old-local"])
        let disk = OwnedMusicPlaylistPersistence(); disk.documents[owner] = MusicPlaylistDocument(playlists: legacy); disk.failWrite = true
        let failed = MusicPlaylistStore(owner: owner, persistence: disk)
        XCTAssertNil(failed.add([track("another")], to: id)); XCTAssertEqual(failed.playlists.first?.trackIds, ["old-local"])
        XCTAssertTrue(failed.tracks.isEmpty)
    }
    private func track(_ id: String, connector: String = "catalog", title: String = "Owned recording", explicit: Bool? = nil, version: String? = nil) -> MusicTrack {
        .init(id: id, connectorId: connector, sourceId: id, playbackUrl: nil, title: title, artist: "Owned artist", album: "Owned album",
            artwork: "https://example.org/owned-cover.jpg", durationSeconds: 182, durationLabel: "3:02", explicit: explicit, version: version, mediaKind: "audio")
    }
}
@MainActor private final class OwnedMusicPlaylistPersistence: MusicPlaylistPersistence {
    var documents: [String: MusicPlaylistDocument] = [:]
    var failRead = false, failWrite = false
    func read(owner: String) throws -> MusicPlaylistDocument? { if failRead { throw HarborError(code: "owned-read") }; return documents[owner] }
    func write(_ value: MusicPlaylistDocument, owner: String) throws { if failWrite { throw HarborError(code: "owned-write") }; documents[owner] = value }
}

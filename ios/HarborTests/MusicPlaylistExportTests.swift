import XCTest
@testable import Harbor

@MainActor final class MusicPlaylistExportTests: XCTestCase {
    func testSourceExtendedM3UFormattingPreservesOrderDurationsUnicodeAndRejectsLineInjection() async throws {
        let track = MusicTrack(id: "owned-export-format", connectorId: "direct", sourceId: "owned", playbackUrl: nil,
            title: " \rOne\n二 \n", artist: " \nÅ\r rtist ", album: nil, artwork: "", durationSeconds: .max, durationLabel: "owned")
        let next = SharedMusicPlaybackTests.track("second", source: "second")
        let renderer = MusicM3URenderer()
        let data = try await renderer.render([.init(track: track, location: " https://owned.example.test/one?owned=1 \t"), .init(track: next, location: "/owned audio/two.wav")])
        XCTAssertEqual(String(decoding: data, as: UTF8.self), "#EXTM3U\n#EXTINF:18446744073709551615,Å  rtist - One 二\nhttps://owned.example.test/one?owned=1\n#EXTINF:8,Owned artist - Owned second\n/owned audio/two.wav\n")
        let empty = try await renderer.render([]); XCTAssertEqual(String(decoding: empty, as: UTF8.self), "#EXTM3U\n")
        for location in [" \t", "https://owned.example.test/one\n#EXTINF:1,Injected", "one\rtwo", "one\r\ntwo"] {
            do { _ = try await renderer.render([.init(track: next, location: location)]); XCTFail("Unexportable lines must fail the entire document") }
            catch MusicPlaylistExportError.location { }
        }
        XCTAssertEqual(MusicM3URenderer.filename(" A:B/<x>?\\z* "), "A B x z.m3u")
        XCTAssertEqual(MusicM3URenderer.filename(" <>:\"/\\|?* \n"), "playlist.m3u")
    }
    func testRealOwnedSessionExportsTheEntireRemoteAndImportedPlaylistInStoredOrder() async throws {
        let file = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "owned-tone", withExtension: "wav", subdirectory: "Fixtures"))
        let scope = SharedMusicScope(), pairs = SharedMusicPairingDisk(), publisher = try SharedMusicPublisher(audio: Data())
        let base = try await publisher.start(); defer { publisher.stop() }
        pairs.value = .salted(baseUrl: base.absoluteString, username: "owned-listener", password: "owned-password", salt: "owned-salt")
        let imported = try await MusicFileService.shared.importFile(file, owner: scope.scope.owner).record
        let server = SubsonicMusicService(scope: scope.scope, currentScope: { scope.scope }, persistence: pairs)
        do {
            let store = MusicPlaylistStore(owner: scope.scope.owner, persistence: SharedMusicDisk())
            let playlist = try XCTUnwrap(store.create("Owned export"))
            let remote = SharedMusicPlaybackTests.track("subsonic:owned-export", source: "owned-export", connector: "subsonic")
            let saved = try XCTUnwrap(store.add([remote, imported.local.track], to: playlist.id))
            let session = MusicPlaybackSession(server: server, playlists: store, localRecords: { [imported] }, currentScope: { scope.scope })
            let exported = try await MusicPlaylistExporter.prepare(saved, tracks: store.recordings(in: saved.id), owner: store.owner, using: session, allowed: { true })
            let lines = String(decoding: exported.data, as: UTF8.self).components(separatedBy: "\n")
            XCTAssertEqual(lines.count, 6); XCTAssertEqual(lines[0], "#EXTM3U")
            XCTAssertEqual(exported.count, 2); XCTAssertEqual(exported.name, "Owned export"); XCTAssertEqual(exported.filename, "Owned export.m3u")
            let url = try XCTUnwrap(URLComponents(string: lines[2]))
            XCTAssertEqual(url.path, "/rest/stream"); XCTAssertTrue(url.queryItems?.contains(.init(name: "id", value: "owned-export")) == true)
            XCTAssertEqual(lines[4], try MusicFileService.file(imported, owner: store.owner).path)
            XCTAssertTrue(FileManager.default.fileExists(atPath: lines[4]))
            server.dispose(); try await MusicFileService.shared.remove(imported, owner: scope.scope.owner)
        } catch { server.dispose(); try? await MusicFileService.shared.remove(imported, owner: scope.scope.owner); throw error }
    }
    func testHeldExportRejectsMissingEntriesRetiredPermissionsAndExpiredEarlierStreamLeases() async throws {
        let first = SharedMusicPlaybackTests.track("first", source: "first"), slow = SharedMusicPlaybackTests.track("second", source: "slow")
        let list = MusicPlaylist(id: UUID().uuidString, name: "Owned held export", createdAt: "1", updatedAt: "1", trackIds: [first.id, slow.id], trackAddedAt: [:])
        let resolver = SharedMusicResolver(), gate = SharedMusicGate(), permission = ExportPermission()
        resolver.gate = gate
        do { _ = try await MusicPlaylistExporter.prepare(list, tracks: [first], owner: resolver.scope.owner, using: resolver, allowed: { true }); XCTFail("Missing metadata must not silently shorten the exported list") }
        catch MusicPlaylistExportError.unavailable { }
        for reason in 0..<3 {
            permission.active = true
            let pending = Task { try await MusicPlaylistExporter.prepare(list, tracks: [first, slow], owner: resolver.scope.owner, using: resolver, allowed: { permission.active }) }
            try await waiting(gate)
            if reason == 0 { resolver.revision = UUID() }
            if reason == 1 { permission.active = false }
            if reason == 2 { pending.cancel() }
            await gate.release()
            do { _ = try await pending.value; XCTFail("An expired lease, removed permission or cancelled task cannot return export data") }
            catch is CancellationError { }
        }
        do { _ = try await MusicPlaylistExporter.prepare(list, tracks: [first, slow], owner: "another-owned-profile", using: resolver, allowed: { true }); XCTFail("Another profile cannot export this list") }
        catch is CancellationError { }
    }
    func testExportSourceAndMobileLabelsResolveInAllSixteenLanguages() throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "music-playlist-export-labels", withExtension: "json", subdirectory: "Fixtures"))
        let fixture = try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: url)); var count = 0
        for language in fixture["languages"].array {
            let code = try XCTUnwrap(language["code"].string)
            for (key, value) in language["expected"].objectValue {
                XCTAssertEqual(DesktopInterfaceText.value(key, language: code), try XCTUnwrap(value.string), code + ": " + key); count += 1
            }
        }
        XCTAssertEqual(count, 64)
    }
    private func waiting(_ gate: SharedMusicGate) async throws {
        for _ in 0..<300 { if await gate.waiting() { return }; try await Task.sleep(for: .milliseconds(20)) }
        XCTFail("Reach the owned resolution barrier before retiring its export"); throw HarborError(code: "owned-export-barrier")
    }
}
@MainActor private final class ExportPermission { var active = true }

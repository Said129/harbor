import AVFoundation
import XCTest
@testable import Harbor

@MainActor final class SharedMusicPlaybackTests: XCTestCase {
    func testActualSubsonicHTTPAudioAndOwnedLocalFileSharePlaybackPauseSeekAndQueue() async throws {
        let file = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "owned-tone", withExtension: "wav", subdirectory: "Fixtures"))
        let publisher = try SharedMusicPublisher(audio: Data(contentsOf: file)), base = try await publisher.start()
        let scope = SharedMusicScope(), disk = SharedMusicDisk(), pairs = SharedMusicPairingDisk()
        pairs.value = .salted(baseUrl: base.absoluteString, username: "owned-listener", password: "owned-password", salt: "owned-salt")
        let imported = try await MusicFileService.shared.importFile(file, owner: scope.scope.owner).record
        let engine = MusicAudioEngine(), player = MusicPlayback(engine: engine, systemIntegration: false, recordPlayed: { _, _ in })
        let savedVolume = player.volume, oldShuffle = player.shuffle, oldRepeat = player.repeatMode
        player.changeVolume(0); player.shuffle = false; player.repeatMode = .off
        defer { player.stop(); player.volume = savedVolume; player.shuffle = oldShuffle; player.repeatMode = oldRepeat; publisher.stop() }
        do {
            let store = MusicPlaylistStore(owner: scope.scope.owner, persistence: disk)
            let server = SubsonicMusicService(scope: scope.scope, currentScope: { scope.scope }, persistence: pairs)
            let session = MusicPlaybackSession(server: server, playlists: store, localRecords: { [imported] }, currentScope: { scope.scope })
            let remote = Self.track("subsonic:owned", source: "owned", connector: "subsonic")
            player.play(remote, queue: [remote, imported.local.track], using: session, origin: .init(kind: "playlist", id: "owned-mixed", name: "Owned mixed queue"))
            try await wait { player.error == nil && player.loaded && player.position > 0.15 }
            XCTAssertNil(player.error); XCTAssertNil(player.current, "A real remote stream must not masquerade as an imported file")
            XCTAssertEqual(player.currentTrack?.id, remote.id); XCTAssertEqual(player.items.count, 2)
            XCTAssertEqual(player.worldState.originId, "owned-mixed"); XCTAssertEqual(player.worldState.phase, .playing)
            XCTAssertTrue(publisher.requests.contains { $0.hasPrefix("GET /rest/stream?") && $0.contains("format=raw") })
            player.pauseForVideo(); try await wait { player.paused }
            XCTAssertTrue(player.pausedForVideo)
            player.setPaused(false); try await wait { !player.paused }; XCTAssertFalse(player.pausedForVideo)
            player.seek(2); try await wait { player.position >= 1.9 }
            XCTAssertLessThan(player.position, 3)
            player.next(); try await wait { player.current?.id == imported.id && player.loaded && player.position > 0.1 }
            XCTAssertNil(player.error); XCTAssertEqual(player.currentTrack?.connectorId, "local")
            XCTAssertEqual(player.upcomingItems.count, 0)
            XCTAssertNotNil(store.tracks[remote.id]); XCTAssertNotNil(store.tracks[imported.id])
            player.stop(); await engine.stop(request: .max)
            XCTAssertNil(player.currentItem); XCTAssertTrue(player.items.isEmpty)
            try await MusicFileService.shared.remove(imported, owner: scope.scope.owner)
        } catch {
            player.stop(); await engine.stop(request: .max)
            try? await MusicFileService.shared.remove(imported, owner: scope.scope.owner)
            throw error
        }
    }
    func testRealHTTPHeadersAndOldEngineRequestsCannotReplacePauseOrStopANewerCore() async throws {
        let file = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "owned-tone", withExtension: "wav", subdirectory: "Fixtures"))
        let publisher = try SharedMusicPublisher(audio: Data(contentsOf: file)), base = try await publisher.start()
        defer { publisher.stop() }
        let engine = MusicAudioEngine(), cookie = #"owned=one,two; path=one\\two; quoted="value""#
        let stream = MusicAudioStream(url: base.appendingPathComponent("audio.wav"), httpHeaders: ["Cookie": cookie, "User-Agent": "OwnedRemote/1.0"], mimeType: "audio/wav", bitrate: 0)
        try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default); try AVAudioSession.sharedInstance().setActive(true)
        do {
            try await engine.open(stream, request: 10, volume: 0, paused: false)
            let first = try await time(engine, request: 10, after: 0.15)
            XCTAssertGreaterThan(first, 0.15)
            XCTAssertTrue(publisher.requests.contains { request in
                let pairs = request.components(separatedBy: "\r\n").compactMap { line -> (String, String)? in
                    guard let colon = line.firstIndex(of: ":") else { return nil }
                    return (line[..<colon].lowercased(), line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces))
                }
                let headers = Dictionary(pairs, uniquingKeysWith: { _, last in last })
                return headers["user-agent"] == "OwnedRemote/1.0" && headers["cookie"] == cookie
            })
            do { try await engine.open(stream, request: 9, volume: 0, paused: true); XCTFail("An old open must not touch the active core") } catch is CancellationError { }
            try await engine.command(.paused(true), request: 9); await engine.stop(request: 9)
            let continued = try await time(engine, request: 10, after: first + 0.1)
            XCTAssertGreaterThan(continued, first)
            await engine.stop(request: 11)
            let events = await engine.read(request: 10); XCTAssertTrue(events.isEmpty)
        } catch { await engine.stop(request: .max); throw error }
    }
    func testSupersededAndStoppedResolutionsAndRetiredProfileLeasesCannotPublishLateAudio() async throws {
        let engine = SharedMusicControlledEngine(), resolver = SharedMusicResolver(), gate = SharedMusicGate()
        resolver.gate = gate
        let player = MusicPlayback(engine: engine, systemIntegration: false, recordPlayed: { _, _ in })
        defer { player.stop() }
        let slow = Self.track("slow", source: "slow"), fast = Self.track("fast", source: "fast")
        player.play(slow, queue: [slow], using: resolver)
        try await waitAsync { await gate.waiting() }
        player.play(fast, queue: [fast], using: resolver)
        try await wait { player.currentTrack?.id == fast.id && player.loaded }
        await gate.release(); try await Task.sleep(for: .milliseconds(50))
        let opened = await engine.opened; XCTAssertEqual(opened, ["fast.wav"])
        player.play(slow, queue: [slow], using: resolver); try await waitAsync { await gate.waiting() }
        player.stop(); await gate.release(); try await Task.sleep(for: .milliseconds(50))
        let afterStop = await engine.opened; XCTAssertEqual(afterStop, opened); XCTAssertNil(player.currentItem)
        player.play(fast, queue: [fast], using: resolver); try await wait { player.loaded }
        resolver.active = false; try await wait { player.currentItem == nil }
        XCTAssertEqual(player.phase, .idle)
    }
    func testSharedQueuePreviewManualRepeatPriorityAdoptionAndHistoryFollowEngineEvents() async throws {
        let engine = SharedMusicControlledEngine(), resolver = SharedMusicResolver()
        var recorded: [String] = []
        let player = MusicPlayback(engine: engine, systemIntegration: false, recordPlayed: { track, _ in recorded.append(track.id) })
        let oldShuffle = player.shuffle, oldRepeat = player.repeatMode
        defer { player.stop(); player.shuffle = oldShuffle; player.repeatMode = oldRepeat }
        let tracks = (0..<4).map { Self.track("song-\($0)", source: "song-\($0)") }
        player.shuffle = true; player.repeatMode = .off
        player.play(tracks[0], queue: tracks, using: resolver)
        try await wait { player.loaded }
        let expected = try XCTUnwrap(player.upcomingItems.first)
        player.next(); try await wait { player.currentItem?.id == expected.id && player.loaded }
        player.previous(); try await wait { player.currentTrack?.id == tracks[0].id && player.loaded }
        player.repeatMode = .one; XCTAssertTrue(player.upcomingItems.isEmpty)
        player.next(automatic: true); try await wait { player.loaded }
        XCTAssertEqual(player.currentTrack?.id, tracks[0].id)
        player.enqueue(tracks[3], using: resolver, next: true); player.next()
        try await wait { player.currentTrack?.id == tracks[3].id && player.loaded }
        player.repeatMode = .off; player.shuffle = false
        await engine.emit([.duration(2), .time(1), .time(1.8), .time(2), .ended(natural: false, failed: false)])
        try await wait { !resolver.scrobbled.isEmpty }
        XCTAssertEqual(resolver.scrobbled, [tracks[3].id]); XCTAssertTrue(recorded.contains(tracks[0].id))
        var adopted = Self.track("resolved", source: "resolved", connector: "subsonic")
        adopted.collectionOrigin = .init(id: tracks[0].id, connectorId: tracks[0].connectorId, title: tracks[0].title)
        player.play(adopted, queue: [tracks[0], tracks[1]], using: resolver)
        try await wait { player.loaded }
        XCTAssertEqual(player.items.first?.track.id, adopted.id, "The admitted source replaces its collection identity inside the queue")
        player.removeFromQueue(try XCTUnwrap(player.currentItem)); try await wait { player.currentTrack?.id == tracks[1].id && player.loaded }
        XCTAssertEqual(player.items.count, 1)
    }
    func testAnAppWithoutAnActiveProfileCannotAcquireAPlayableMusicWorkspace() throws {
        let app = AppModel(), workspace = app.musicWorkspaceForCurrentProfile()
        XCTAssertEqual(workspace.scope.owner, "unavailable")
        XCTAssertFalse(workspace.available); XCTAssertThrowsError(try workspace.playback.validate())
    }
    func testOnlyNewSharedPlayerLabelsMatchAllDesktopLanguageCatalogs() throws {
        let file = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "music-shared-player-labels", withExtension: "json", subdirectory: "Fixtures"))
        let fixture = try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: file))
        XCTAssertEqual(fixture["reference"].string, "0834340cec5531650bfe78cd628628702e636987")
        var comparisons = 0
        for language in fixture["languages"].array {
            let code = try XCTUnwrap(language["code"].string)
            for (key, value) in language["expected"].objectValue {
                XCTAssertEqual(DesktopInterfaceText.value(key, language: code), try XCTUnwrap(value.string), code + ": " + key); comparisons += 1
            }
        }
        XCTAssertEqual(comparisons, fixture["comparisons"].integer)
    }
    static func track(_ id: String, source: String, connector: String = "direct", artwork: String = "") -> MusicTrack {
        .init(id: id, connectorId: connector, sourceId: source, playbackUrl: nil, title: "Owned " + id, artist: "Owned artist", album: "Owned album", artwork: artwork, durationSeconds: 8, durationLabel: "0:08")
    }
    private func wait(_ predicate: @MainActor () -> Bool) async throws {
        for _ in 0..<500 { if predicate() { return }; try await Task.sleep(for: .milliseconds(20)) }
        XCTFail("The affected shared player state did not settle"); throw HarborError(code: "owned-shared-player-timeout")
    }
    private func waitAsync(_ predicate: () async -> Bool) async throws {
        for _ in 0..<250 { if await predicate() { return }; try await Task.sleep(for: .milliseconds(20)) }
        XCTFail("The held resolver did not reach its barrier"); throw HarborError(code: "owned-shared-resolver-timeout")
    }
    private func time(_ engine: MusicAudioEngine, request: UInt64, after value: Double) async throws -> Double {
        for _ in 0..<500 {
            let events = await engine.read(request: request)
            for event in events { if case .time(let current) = event, current > value { return current }; if case .failed = event { throw HarborError(code: "owned-shared-audio-failure") } }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTFail("Actual libmpv audio time did not advance"); throw HarborError(code: "owned-shared-audio-timeout")
    }
}

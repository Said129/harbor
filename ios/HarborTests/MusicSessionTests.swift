import Foundation
import XCTest
@testable import Harbor

@MainActor private final class CheckpointMusicResolver: MusicPlaybackResolving {
    let scope: PluginExecutionScope
    let url: URL
    var active = true
    init(owner: String, url: URL) { scope = .init(owner: owner, activation: UUID()); self.url = url }
    func validate() throws { if !active { throw CancellationError() } }
    func localRecord(_ track: MusicTrack) -> MusicRecord? { nil }
    func resolve(_ track: MusicTrack) async throws -> MusicPlaybackResolution {
        try validate()
        return .init(stream: .init(url: url, httpHeaders: [:], mimeType: "audio/wav", bitrate: 0),
                     valid: { [weak self] in self?.active == true })
    }
    func scrobble(_ track: MusicTrack, startedAt: UInt64) async throws { try validate() }
}

private actor HeldMusicSessionStore: MusicSessionPersisting {
    let gate: SharedMusicGate
    let heldOwner: String
    let snapshots: [String: MusicSessionSnapshot]
    init(gate: SharedMusicGate, owner: String, snapshots: [String: MusicSessionSnapshot]) {
        self.gate = gate; heldOwner = owner; self.snapshots = snapshots
    }
    func read(owner: String) async throws -> MusicSessionSnapshot? {
        if owner == heldOwner { await gate.hold() }
        return snapshots[owner]
    }
    func write(_ value: MusicSessionSnapshot, owner: String) throws { }
}

@MainActor final class MusicSessionTests: XCTestCase {
    func testNativeHTTPAudioCheckpointRestoresPausedQueueOriginAndSeekWithoutPersistingResolvedURLs() async throws {
        let file = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "owned-tone", withExtension: "wav", subdirectory: "Fixtures"))
        let publisher = try SharedMusicPublisher(audio: Data(contentsOf: file)), url = try await publisher.start()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("owned-music-session-" + UUID().uuidString)
        let owner = "owned-checkpoint-" + UUID().uuidString
        let store = MusicSessionFileStore(directory: directory), engine = MusicAudioEngine()
        let resolver = CheckpointMusicResolver(owner: owner, url: url)
        let player = MusicPlayback(engine: engine, systemIntegration: false, recordPlayed: { _, _ in }, checkpoints: store)
        let resumedEngine = MusicAudioEngine()
        let resumed = MusicPlayback(engine: resumedEngine, systemIntegration: false, recordPlayed: { _, _ in },
                                    checkpoints: MusicSessionFileStore(directory: directory))
        let oldShuffle = player.shuffle, oldRepeat = player.repeatMode, oldVolume = player.volume
        player.shuffle = false; player.repeatMode = .off; player.changeVolume(0)
        defer {
            player.stop(); resumed.stop(); publisher.stop()
            player.shuffle = oldShuffle; player.repeatMode = oldRepeat; player.volume = oldVolume
        }
        do {
            let song = track("saved-source"), next = track("next-source")
            let origin = MusicQueueOrigin(kind: "playlist", id: "owned-checkpoint-list", name: "Owned queue")
            player.play(song, queue: [song, next], using: resolver, origin: origin)
            try await wait { player.loaded && player.position > 0.1 }
            player.setPaused(true); try await wait { player.paused }
            player.seek(3); try await wait { abs(player.position - 3) < 0.2 }
            await player.flushCheckpoint()
            let stored = try await store.read(owner: owner)
            let saved = try XCTUnwrap(stored)
            XCTAssertEqual(saved.current.id, song.id); XCTAssertNil(saved.current.playbackUrl)
            XCTAssertEqual(saved.origin, origin); XCTAssertEqual(saved.queue.map(\.id), [song.id, next.id])
            XCTAssertEqual(saved.position, 3, accuracy: 0.2)
            player.stop(); await player.flushCheckpoint(); await engine.stop(request: .max)
            resumed.attach(resolver)
            try await wait { resumed.restored }
            XCTAssertEqual(resumed.phase, .paused); XCTAssertTrue(resumed.paused); XCTAssertFalse(resumed.loaded)
            XCTAssertEqual(resumed.position, 3, accuracy: 0.2); XCTAssertEqual(resumed.origin, origin)
            XCTAssertEqual(resumed.currentTrack?.id, song.id); XCTAssertEqual(resumed.items.count, 2)
            let beforePlay = await resumedEngine.signal(request: 0)
            XCTAssertNil(beforePlay, "Restoring metadata must not open a network stream or activate audio")
            resumed.togglePause()
            try await wait { resumed.loaded && !resumed.paused && resumed.position >= 2.9 }
            XCTAssertLessThan(resumed.position, 4); XCTAssertNil(resumed.error)
            resumed.setPaused(true); try await wait { resumed.paused }
            await resumed.flushCheckpoint()
            let otherOwner = try await store.read(owner: "different-owner")
            XCTAssertNil(otherOwner)
            let root = directory.appendingPathComponent(EBookShelf.hash(owner))
            for name in ["queue.json", "checkpoint.json"] {
                let bytes = try Data(contentsOf: root.appendingPathComponent(name))
                XCTAssertFalse(String(decoding: bytes, as: UTF8.self).contains("private-token"))
            }
            resumed.stop(); await resumed.flushCheckpoint(); await resumedEngine.stop(request: .max)
            try FileManager.default.removeItem(at: directory)
        } catch {
            player.stop(); resumed.stop()
            await player.flushCheckpoint(); await resumed.flushCheckpoint()
            await engine.stop(request: .max); await resumedEngine.stop(request: .max)
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }

    func testCheckpointRecoveryKeepsSubstituteAndUnknownDurationAndRejectsRetiredOwnerAndCorruptData() async throws {
        XCTAssertEqual(MusicSessionSnapshot.usablePosition(50, duration: 0), 50)
        XCTAssertEqual(MusicSessionSnapshot.usablePosition(7, duration: 8), 0)
        XCTAssertEqual(MusicSessionSnapshot.usablePosition(.nan, duration: 8), 0)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("owned-music-recovery-" + UUID().uuidString)
        let store = MusicSessionFileStore(directory: directory), owner = "owned-recovery-" + UUID().uuidString
        defer { try? FileManager.default.removeItem(at: directory) }
        let substitute = track("substitute"), unrelated = track("unrelated")
        let snapshot = MusicSessionSnapshot(revision: UUID(), queue: [unrelated], current: substitute,
                                           origin: nil, position: 3, savedAt: Date())
        try await store.write(snapshot, owner: owner)
        let stored = try await store.read(owner: owner)
        let saved = try XCTUnwrap(stored)
        XCTAssertEqual(saved.queue.map(\.id), [substitute.id, unrelated.id])
        let root = directory.appendingPathComponent(EBookShelf.hash(owner))
        try Data("invalid queue".utf8).write(to: root.appendingPathComponent("queue.json"), options: .atomic)
        let reopened = try await MusicSessionFileStore(directory: directory).read(owner: owner)
        let recovered = try XCTUnwrap(reopened)
        XCTAssertEqual(recovered.queue.map(\.id), [substitute.id]); XCTAssertEqual(recovered.position, 3)
        try Data("invalid checkpoint".utf8).write(to: root.appendingPathComponent("checkpoint.json"), options: .atomic)
        do { _ = try await store.read(owner: owner); XCTFail("Corrupt state must not become a playable queue") } catch { }
        let gate = SharedMusicGate(), first = SharedMusicResolver(), second = SharedMusicResolver()
        let other = track("other-profile")
        let secondSnapshot = MusicSessionSnapshot(revision: UUID(), queue: [other], current: other,
                                                 origin: nil, position: 2, savedAt: Date())
        let delayed = HeldMusicSessionStore(gate: gate, owner: first.scope.owner,
                                           snapshots: [first.scope.owner: snapshot, second.scope.owner: secondSnapshot])
        let engine = SharedMusicControlledEngine()
        let player = MusicPlayback(engine: engine, systemIntegration: false, recordPlayed: { _, _ in }, checkpoints: delayed)
        defer { player.stop() }
        player.attach(first)
        try await waitAsync { await gate.waiting() }
        player.attach(second)
        try await wait { player.restored && player.currentTrack?.id == other.id }
        await gate.release()
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(player.owner, second.scope.owner); XCTAssertEqual(player.currentTrack?.id, other.id)
        XCTAssertEqual(player.position, 2); XCTAssertEqual(player.phase, .paused)
        let opened = await engine.opened; XCTAssertTrue(opened.isEmpty)
        XCTAssertNil(player.error)
    }

    private func track(_ id: String) -> MusicTrack {
        .init(id: id, connectorId: "subsonic", sourceId: id, playbackUrl: "https://owned.invalid/private-token",
              title: "Owned " + id, artist: "Owned Artist", album: "Owned Album", artwork: "",
              durationSeconds: 8, durationLabel: "0:08")
    }
    private func wait(_ predicate: @MainActor () -> Bool) async throws {
        for _ in 0..<500 { if predicate() { return }; try await Task.sleep(for: .milliseconds(20)) }
        XCTFail("Owned music checkpoint did not settle"); throw HarborError(code: "owned-checkpoint-timeout")
    }
    private func waitAsync(_ predicate: () async -> Bool) async throws {
        for _ in 0..<250 { if await predicate() { return }; try await Task.sleep(for: .milliseconds(20)) }
        XCTFail("Owned checkpoint barrier did not settle"); throw HarborError(code: "owned-checkpoint-barrier")
    }
}

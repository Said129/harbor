import XCTest
@testable import Harbor

@MainActor final class MusicRememberCacheTests: XCTestCase {
    func testIdenticalAndSparsePlaybackMetadataAvoidWholeDocumentWritesWhileStorageErrorsStillRetry() throws {
        let disk = RememberCacheDisk(), store = MusicPlaylistStore(owner: "owned-music-write-cache", persistence: disk)
        var track = SharedMusicPlaybackTests.track("owned-cache", source: "owned-cache")
        track.explicit = true; track.version = "Original"; track.mediaKind = "audio"
        XCTAssertTrue(store.remember([track])); XCTAssertEqual(disk.attempts, 1)
        XCTAssertTrue(store.remember([track])); XCTAssertEqual(disk.attempts, 1)
        let sparse = SharedMusicPlaybackTests.track(track.id, source: "owned-cache")
        XCTAssertTrue(store.remember([sparse])); XCTAssertEqual(disk.attempts, 1)
        XCTAssertEqual(store.tracks[track.id]?.explicit, true); XCTAssertEqual(store.tracks[track.id]?.version, "Original")
        var changed = track; changed.version = "Remastered"
        XCTAssertTrue(store.remember([changed])); XCTAssertEqual(disk.attempts, 2)
        disk.failWrite = true; changed.version = "Uncommitted"
        XCTAssertFalse(store.remember([changed])); XCTAssertEqual(disk.attempts, 3)
        XCTAssertEqual(store.tracks[track.id]?.version, "Remastered")
        let cached = try XCTUnwrap(store.tracks[track.id])
        XCTAssertFalse(store.remember([cached]), "A prior storage error must not be bypassed just because this track is cached")
        XCTAssertEqual(disk.attempts, 4)
        disk.failWrite = false
        XCTAssertTrue(store.remember([cached])); XCTAssertEqual(disk.attempts, 5); XCTAssertNil(store.error)
        XCTAssertTrue(store.remember([cached])); XCTAssertEqual(disk.attempts, 5)
        let unreadable = RememberCacheDisk(); unreadable.failRead = true
        let locked = MusicPlaylistStore(owner: "owned-unreadable-write-cache", persistence: unreadable)
        XCTAssertFalse(locked.remember([])); XCTAssertEqual(unreadable.attempts, 0)
    }
}
@MainActor private final class RememberCacheDisk: MusicPlaylistPersistence {
    var value: MusicPlaylistDocument?
    var attempts = 0, failWrite = false, failRead = false
    func read(owner: String) throws -> MusicPlaylistDocument? { if failRead { throw HarborError(code: "owned-cache-read") }; return value }
    func write(_ value: MusicPlaylistDocument, owner: String) throws {
        attempts += 1; if failWrite { throw HarborError(code: "owned-cache-write") }; self.value = value
    }
}

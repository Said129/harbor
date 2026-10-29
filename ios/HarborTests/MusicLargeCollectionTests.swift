import XCTest
@testable import Harbor

@MainActor final class MusicLargeCollectionTests: XCTestCase {
    func testFiveThousandStoredRecordingsAndLongIDsReorderThroughTheActualBridgeWithoutDroppingMembership() throws {
        let disk = SharedMusicDisk(), store = MusicPlaylistStore(owner: "owned-large-music-store", persistence: disk)
        let list = try XCTUnwrap(store.create("Owned large playlist"))
        var tracks = (0..<5_000).map { SharedMusicPlaybackTests.track("owned-large-\($0)", source: String($0)) }
        tracks[0] = SharedMusicPlaybackTests.track("direct:" + String(repeating: "x", count: 4_096), source: "owned-long")
        XCTAssertNotNil(store.add(tracks, to: list.id)); XCTAssertNil(store.error)
        store.move(tracks[0].id, in: list.id, to: 4_999)
        XCTAssertNil(store.error)
        let expected = Array(tracks.dropFirst().map(\.id)) + [tracks[0].id]
        XCTAssertEqual(store.playlists.first?.trackIds, expected)
        let reopened = MusicPlaylistStore(owner: store.owner, persistence: disk)
        XCTAssertTrue(reopened.ready); XCTAssertEqual(reopened.recordings(in: list.id).map(\.id), expected)
        let invalid = SharedMusicPlaybackTests.track(String(repeating: "x", count: 8_193), source: "owned-invalid")
        XCTAssertNil(store.add([invalid], to: list.id)); XCTAssertNotNil(store.error)
        XCTAssertEqual(store.playlists.first?.trackIds, expected)
        XCTAssertEqual(disk.value?.playlists.first?.trackIds, expected)
    }
    func testFiveThousandQueueEntriesRemainPlayableBeyondFiveHundredAndAllUpcomingItemsArePreserved() throws {
        let resolver = SharedMusicResolver(), player = MusicPlayback(engine: SharedMusicControlledEngine(), systemIntegration: false, recordPlayed: { _, _ in })
        let oldShuffle = player.shuffle, oldRepeat = player.repeatMode
        defer { player.stop(); player.shuffle = oldShuffle; player.repeatMode = oldRepeat }
        player.shuffle = false; player.repeatMode = .off
        let tracks = (0..<5_000).map { SharedMusicPlaybackTests.track("owned-queue-\($0)", source: String($0)) }
        player.play(tracks[750], queue: tracks, using: resolver)
        XCTAssertEqual(player.items.map(\.track.id), tracks.map(\.id))
        XCTAssertEqual(player.currentTrack?.id, tracks[750].id)
        XCTAssertEqual(player.upcomingItems.map(\.track.id), Array(tracks.dropFirst(751).map(\.id)))
        player.next(); XCTAssertEqual(player.currentTrack?.id, tracks[751].id)
        let priority = SharedMusicPlaybackTests.track("owned-priority", source: "owned-priority")
        player.enqueue(priority, using: resolver, next: true)
        XCTAssertEqual(player.items.count, 5_001); XCTAssertEqual(player.upcomingItems.first?.id, MusicQueueOrder.key(priority))
        player.next(); XCTAssertEqual(player.currentTrack?.id, priority.id)
        XCTAssertEqual(player.items.count, 5_001)
        let order = MusicQueueOrder()
        XCTAssertEqual(try order.upcoming(tracks, index: 0, shuffle: false, repeatMode: .off).map(\.id), Array(tracks.dropFirst().map(\.id)))
    }
}

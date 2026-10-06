import XCTest
@testable import Harbor

final class MusicPlaybackTests: XCTestCase {
    @MainActor
    func testOwnedAudioUsesNativeMetadataRustIdentityAndActualPlaybackTime() async throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "owned-tone", withExtension: "wav", subdirectory: "Fixtures"))
        let owner = "music-native-test-" + UUID().uuidString
        let imported = try await MusicFileService.shared.importFile(url, owner: owner)
        let record = imported.record
        let player = MusicPlayback.shared
        let previousVolume = player.volume
        do {
            XCTAssertEqual(record.local.track.title, "owned-tone")
            XCTAssertEqual(record.local.track.durationSeconds, 8)
            XCTAssertEqual(record.local.track.durationLabel, "0:08")
            XCTAssertEqual(record.local.track.connectorId, "local")
            XCTAssertNil(record.local.track.playbackUrl)
            XCTAssertTrue(record.local.track.id.hasPrefix("local:"))
            player.changeVolume(0)
            player.play(record, queue: [record], owner: owner)
            let deadline = Date().addingTimeInterval(15)
            while Date() < deadline, player.error == nil, (!player.loaded || player.position <= 0.15) { try await Task.sleep(for: .milliseconds(100)) }
            XCTAssertNil(player.error)
            XCTAssertTrue(player.loaded)
            XCTAssertGreaterThan(player.position, 0.15, "Actual libmpv audio position must advance")
            player.setPaused(true)
            let pauseDeadline = Date().addingTimeInterval(3)
            while Date() < pauseDeadline, !player.paused { try await Task.sleep(for: .milliseconds(50)) }
            XCTAssertTrue(player.paused)
            player.seek(2)
            let seekDeadline = Date().addingTimeInterval(3)
            while Date() < seekDeadline, player.position < 1.9 { try await Task.sleep(for: .milliseconds(50)) }
            XCTAssertEqual(player.position, 2, accuracy: 0.2)
            let lists = MusicPlaylistStore(owner: owner)
            lists.create("  Night music  ")
            let list = try XCTUnwrap(lists.playlists.first)
            lists.add(record, to: list.id); lists.add(record, to: list.id)
            XCTAssertNil(lists.error)
            let restored = MusicPlaylistStore(owner: owner)
            XCTAssertEqual(restored.playlists.first?.name, "Night music")
            XCTAssertEqual(restored.playlists.first?.trackIds, [record.id])
            XCTAssertTrue(MusicPlaylistStore(owner: owner + "-other").playlists.isEmpty)
            restored.delete(list.id)
            XCTAssertTrue(MusicPlaylistStore(owner: owner).playlists.isEmpty)
            XCTAssertTrue(FileManager.default.fileExists(atPath: try MusicFileService.file(record, owner: owner).path), "Deleting a playlist must preserve owned audio")
            player.stop(); player.changeVolume(previousVolume)
            try await MusicFileService.shared.remove(record, owner: owner)
        } catch {
            player.stop(); player.changeVolume(previousVolume)
            try? await MusicFileService.shared.remove(record, owner: owner)
            throw error
        }
    }
}

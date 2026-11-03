import Foundation
import XCTest
@testable import Harbor

@MainActor final class SpotifyScrobbleTests: XCTestCase {
    func testConfirmedSpotifyPositionsExcludeAdsSeeksStaleConnectionsAndDuplicateSubmissions() async throws {
        let scope = SharedMusicScope(), original = scope.scope, fixture = try LastFmMusicFixture()
        let network = OwnedLastFmNetwork(endpoint: try await fixture.start())
        let lastfm = LastFmMusicService(scope: original, network: network, currentScope: { scope.scope })
        let recorder = SpotifyListeningRecorder(lastfm: lastfm, currentScope: { scope.scope })
        defer {
            recorder.dispose(); lastfm.dispose(); fixture.stop()
            try? KeychainStore().remove("music-lastfm-account-" + EBookShelf.hash(original.owner))
        }
        try lastfm.saveCredentials(apiKey: "key", secret: "secret")
        _ = try await lastfm.beginAuthorization(); try await lastfm.completeAuthorization()
        let first = UUID(), second = UUID(), date = Date(timeIntervalSince1970: 1_700_000_000)
        let song = track("0123456789ABCDEFGHIJKL", title: "Confirmed song")
        recorder.connect(first)
        for position in [0.0, 1, 2] { recorder.observe(song, position: position, paused: false, advertisement: false, connection: first, at: date) }
        recorder.seekRequested()
        for position in [6.0, 7] { recorder.observe(song, position: position, paused: false, advertisement: false, connection: first) }
        recorder.observe(song, position: 8, paused: false, advertisement: true, connection: first)
        XCTAssertEqual(submissions(fixture).count, 0)
        // The ad contributes no time, but the already confirmed part of this
        // same recording is retained when Spotify resumes it.
        for position in [6.0, 7] { recorder.observe(song, position: position, paused: false, advertisement: false, connection: first) }
        try await wait { self.submissions(fixture).count == 1 }
        XCTAssertEqual(submissions(fixture).first?["timestamp"], "1700000000")
        XCTAssertEqual(submissions(fixture).first?["track"], "Confirmed song")
        recorder.disconnect(first); recorder.connect(second)
        recorder.observe(song, position: 8, paused: false, advertisement: false, connection: first)
        for position in [7.0, 8] { recorder.observe(song, position: position, paused: false, advertisement: false, connection: second) }
        XCTAssertEqual(submissions(fixture).count, 1)
        // A confirmed end-to-start wrap can represent Spotify's repeat-one.
        recorder.observe(song, position: 0, paused: false, advertisement: false, connection: second, at: date.addingTimeInterval(100))
        for position in [1.0, 2, 3, 4] { recorder.observe(song, position: position, paused: false, advertisement: false, connection: second) }
        try await wait { self.submissions(fixture).count == 2 }
        XCTAssertEqual(submissions(fixture).last?["timestamp"], "1700000100")
        let podcast = track("0123456789ABCDEFGHIJKL", title: "Ignored episode", kind: "episode")
        for position in [0.0, 1, 2, 3, 4, 5] { recorder.observe(podcast, position: position, paused: false, advertisement: false, connection: second) }
        XCTAssertEqual(submissions(fixture).count, 2)
        let paused = track("0123456789ABCDEFGHIJKK", title: "Paused song")
        for position in [0.0, 1, 2, 3, 4] { recorder.observe(paused, position: position, paused: true, advertisement: false, connection: second) }
        XCTAssertEqual(submissions(fixture).count, 2)
        for position in [4.0, 5, 6, 7, 8] { recorder.observe(paused, position: position, paused: false, advertisement: false, connection: second) }
        try await wait { self.submissions(fixture).count == 3 }
        fixture.failScrobbles()
        recorder.playRequested()
        for position in [0.0, 1, 2, 3, 4] { recorder.observe(song, position: position, paused: false, advertisement: false, connection: second) }
        try await wait { recorder.error != nil }
        XCTAssertTrue(lastfm.connected)
        let count = submissions(fixture).count
        // New credentials must not inherit another session's listening total.
        try lastfm.saveCredentials(apiKey: "key", secret: "secret")
        _ = try await lastfm.beginAuthorization(); try await lastfm.completeAuthorization()
        for position in [4.0, 5, 6] { recorder.observe(song, position: position, paused: false, advertisement: false, connection: second) }
        XCTAssertNil(recorder.error); XCTAssertEqual(submissions(fixture).count, count)
        scope.scope = .init(owner: "owned-retired-spotify-" + UUID().uuidString, activation: UUID())
        for position in [0.0, 1, 2, 3, 4, 5] { recorder.observe(paused, position: position, paused: false, advertisement: false, connection: second) }
        XCTAssertEqual(submissions(fixture).count, count)
        XCTAssertFalse(recorder.enabled)
    }
    private func track(_ id: String, title: String, kind: String = "track") -> MusicTrack {
        let uri = "spotify:" + kind + ":" + id
        return MusicTrack(id: uri, connectorId: "spotify", sourceId: uri, playbackUrl: nil, title: title,
                          artist: "Owned artist", album: "Owned album", artwork: "", durationSeconds: 8, durationLabel: "0:08")
    }
    private func submissions(_ fixture: LastFmMusicFixture) -> [[String: String]] { fixture.requests.filter { $0["method"] == "track.scrobble" } }
    private func wait(_ condition: @MainActor () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(8)
        while Date() < deadline { if condition() { return }; try await Task.sleep(for: .milliseconds(25)) }
        XCTFail("Confirmed Spotify bookkeeping did not reach the owned Last.fm endpoint")
        throw HarborError(code: "owned-spotify-scrobble-timeout")
    }
}

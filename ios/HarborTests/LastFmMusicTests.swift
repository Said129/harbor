import SwiftUI
import UIKit
import XCTest
@testable import Harbor

private actor LastFmFailingSubsonic: MusicServiceHTTPTransport {
    private(set) var calls = 0
    func perform(_ request: URLRequest) async throws -> MusicServiceHTTPResponse {
        calls += 1; return .init(status: 503, data: Data())
    }
}

@MainActor final class LastFmMusicTests: XCTestCase {
    func testOriginalLastFmAuthAndNativeListeningClockSubmitOnceWithoutPrivateStreamMetadata() async throws {
        XCTAssertEqual(LastFmMusicProtocol.signature(["api_key": "key", "method": "auth.getSession", "token": "token", "format": "json"], secret: "secret"),
                       "9ac306496295a8866c4a8673395540eb")
        let scope = SharedMusicScope(), fixture = try LastFmMusicFixture()
        let network = OwnedLastFmNetwork(endpoint: try await fixture.start())
        let service = LastFmMusicService(scope: scope.scope, network: network, currentScope: { scope.scope })
        let engine = SharedMusicControlledEngine(), player = MusicPlayback(engine: engine, systemIntegration: false, recordPlayed: { _, _ in })
        let owner = scope.scope.owner
        defer { player.stop(); service.dispose(); fixture.stop(); cleanup(owner) }
        try service.saveCredentials(apiKey: "key", secret: "secret")
        let auth = try await service.beginAuthorization()
        XCTAssertEqual(auth.host, "www.last.fm")
        XCTAssertEqual(URLComponents(url: auth, resolvingAgainstBaseURL: false)?.path, "/api/auth/")
        try await service.completeAuthorization()
        XCTAssertTrue(service.connected); XCTAssertEqual(service.username, "Owned Listener")
        let restored = LastFmMusicService(scope: scope.scope, currentScope: { scope.scope })
        defer { restored.dispose() }
        XCTAssertTrue(restored.connected)
        let track = MusicTrack(id: "owned-lastfm", connectorId: "direct", sourceId: "owned",
            playbackUrl: "https://private.invalid/private-token", title: "Owned + canción & one", artist: "Owned Artist", album: " Owned Album ",
            artwork: "", durationSeconds: 180, durationLabel: "3:00")
        try await service.scrobble(track, startedAt: 1234)
        let first = try XCTUnwrap(fixture.requests.last)
        XCTAssertEqual(first["track"], "Owned + canción & one"); XCTAssertEqual(first["timestamp"], "1234")
        XCTAssertEqual(first["album"], "Owned Album"); XCTAssertEqual(first["chosenByUser"], "1")
        XCTAssertEqual(first["sk"], "owned-session-key"); XCTAssertNil(first["secret"])
        XCTAssertFalse(first.values.contains { $0.contains("private-token") || $0.contains("private.invalid") })
        let server = SubsonicMusicService(scope: scope.scope, currentScope: { scope.scope }, persistence: SharedMusicPairingDisk())
        defer { server.dispose() }
        let session = MusicPlaybackSession(server: server, playlists: MusicPlaylistStore(owner: owner, persistence: SharedMusicDisk()),
                                          localRecords: { [] }, lastfm: service, currentScope: { scope.scope })
        player.play(track, queue: [track], using: session)
        try await wait(context: "native player initially loaded") { player.loaded && !player.paused && player.position > 0 }
        player.seek(6); try await wait(context: "known seek observed") { player.position == 6 }
        XCTAssertEqual(fixture.requests.filter { $0["method"] == "track.scrobble" }.count, 1)
        await engine.emit([.time(0.25), .time(1.25), .time(2.25), .time(3.25), .time(4.25)])
        try await wait(context: "native listening threshold submits") { fixture.requests.filter { $0["method"] == "track.scrobble" }.count == 2 }
        await engine.emit([.time(5.25), .time(6.25)])
        try await wait(context: "subsequent clock observed") { player.position == 6.25 }
        XCTAssertEqual(fixture.requests.filter { $0["method"] == "track.scrobble" }.count, 2)
        XCTAssertNil(player.error); XCTAssertNil(player.scrobbleError)
        let failingTransport = LastFmFailingSubsonic(), pairing = SharedMusicPairingDisk()
        pairing.value = SubsonicPairing.salted(baseUrl: "https://owned-subsonic.invalid", username: "owned", password: "owned", salt: "owned")
        let failingServer = SubsonicMusicService(scope: scope.scope, currentScope: { scope.scope }, transport: failingTransport, persistence: pairing)
        defer { failingServer.dispose() }
        let fallback = MusicPlaybackSession(server: failingServer, playlists: MusicPlaylistStore(owner: owner, persistence: SharedMusicDisk()),
                                           localRecords: { [] }, lastfm: service, currentScope: { scope.scope })
        let subsonic = MusicTrack(id: "subsonic:owned", connectorId: "subsonic", sourceId: "owned", playbackUrl: nil,
                                 title: "Owned fallback", artist: "Owned Artist", album: nil, artwork: "", durationSeconds: 180, durationLabel: "3:00")
        try await fallback.scrobble(subsonic, startedAt: 1234)
        let attempts = await failingTransport.calls
        XCTAssertEqual(attempts, 1)
        XCTAssertEqual(fixture.requests.filter { $0["method"] == "track.scrobble" }.count, 3)
        XCTAssertEqual(fixture.requests.last?["track"], "Owned fallback")
        fixture.failScrobbles()
        player.play(track, queue: [track], using: session)
        try await wait(context: "second recording loaded") { player.loaded && player.position < 1 }
        await engine.emit([.time(1.25), .time(2.25), .time(3.25), .time(4.25)])
        try await wait(context: "rejected bookkeeping separated from playback") { player.scrobbleError != nil }
        XCTAssertNil(player.error); XCTAssertTrue(player.loaded); XCTAssertFalse(player.paused)
        XCTAssertEqual(player.phase, .playing)
        try service.disconnect()
        XCTAssertFalse(LastFmMusicService(scope: scope.scope, currentScope: { scope.scope }).connected)
        let requests = await network.requests
        XCTAssertTrue(requests.allSatisfy { $0.url == "https://ws.audioscrobbler.com/2.0/" && $0.followRedirects == false })
    }

    func testRetiredLastFmAuthorizationCannotSaveAUserSessionInEitherProfile() async throws {
        let scope = SharedMusicScope(), original = scope.scope
        let fixture = try LastFmMusicFixture(authDelay: 0.5)
        let network = OwnedLastFmNetwork(endpoint: try await fixture.start())
        let service = LastFmMusicService(scope: original, network: network, currentScope: { scope.scope })
        defer { service.dispose(); fixture.stop(); cleanup(original.owner); cleanup(scope.scope.owner) }
        try service.saveCredentials(apiKey: "key", secret: "secret")
        _ = try await service.beginAuthorization()
        let pending = Task { try await service.completeAuthorization() }
        try await wait { fixture.requests.count >= 2 }
        scope.scope = .init(owner: "owned-next-lastfm-" + UUID().uuidString, activation: UUID())
        service.dispose()
        do { try await pending.value; XCTFail("Retired authorization must not install a session") } catch is CancellationError { }
        let old = try KeychainStore().read("music-lastfm-account-" + EBookShelf.hash(original.owner), as: LastFmMusicAccount.self)
        XCTAssertNil(old?.sessionKey)
        XCTAssertNil(try KeychainStore().read("music-lastfm-account-" + EBookShelf.hash(scope.scope.owner), as: LastFmMusicAccount.self))
        XCTAssertFalse(service.connected); XCTAssertNil(service.username)
    }

    func testLastFmCredentialsAndConnectedAccountRenderForPhoneAndTabletInAllLanguages() async throws {
        let scope = SharedMusicScope(), owner = scope.scope.owner, fixture = try LastFmMusicFixture()
        let network = OwnedLastFmNetwork(endpoint: try await fixture.start())
        let service = LastFmMusicService(scope: scope.scope, network: network, currentScope: { scope.scope })
        let metadata = MusicArtistClient(scope: scope.scope, currentScope: { scope.scope })
        defer { service.dispose(); metadata.dispose(); fixture.stop(); cleanup(owner) }
        try service.saveCredentials(apiKey: "key", secret: "secret")
        for (name, size) in [("phone", CGSize(width: 390, height: 844)), ("tablet", CGSize(width: 1024, height: 1366))] {
            try await capture(NavigationStack { LastFmMusicConnectionView(service: service, metadata: metadata) }, name: "lastfm-form-" + name, size: size)
        }
        _ = try await service.beginAuthorization(); try await service.completeAuthorization()
        for (name, size) in [("phone", CGSize(width: 390, height: 844)), ("tablet", CGSize(width: 1024, height: 1366))] {
            try await capture(NavigationStack { LastFmMusicConnectionView(service: service, metadata: metadata) }, name: "lastfm-connected-" + name, size: size)
        }
        for code in InterfaceLanguage.all.map(\.code) {
            for key in ["music.lastfm.keyHelp", "music.lastfm.secret", "music.lastfm.finish", "music.connections.scrobbler"] {
                XCTAssertNotEqual(DesktopInterfaceText.value(key, language: code), key)
            }
        }
    }
    private func cleanup(_ owner: String) {
        for prefix in ["music-lastfm-account-", "music-lastfm-api-key-"] { try? KeychainStore().remove(prefix + EBookShelf.hash(owner)) }
    }
    private func wait(context: String = "authorization", _ condition: @MainActor () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(8)
        while Date() < deadline { if condition() { return }; try await Task.sleep(for: .milliseconds(25)) }
        XCTFail("Owned Last.fm operation did not settle: " + context); throw HarborError(code: "owned-lastfm-timeout")
    }
    private func capture<V: View>(_ view: V, name: String, size: CGSize) async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first { $0.isKeyWindow }, window = UIWindow(windowScene: scene)
        window.frame = CGRect(origin: .zero, size: size)
        let host = UIHostingController(rootView: view.preferredColorScheme(.dark))
        window.rootViewController = host; window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil; previous?.makeKeyAndVisible() }
        host.view.layoutIfNeeded(); try await Task.sleep(for: .milliseconds(450))
        let image = UIGraphicsImageRenderer(size: size).image { _ in host.view.drawHierarchy(in: CGRect(origin: .zero, size: size), afterScreenUpdates: true) }
        let attachment = XCTAttachment(image: image); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}

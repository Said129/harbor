import SwiftUI
import UIKit
import XCTest
@testable import Harbor

@MainActor final class PlexMusicTests: XCTestCase {
    func testPlexCatalogPrivateCoversStationsAndRealNativePlaybackUseTheOwnedServer() async throws {
        let audio = try resource("owned-tone", "wav"), cover = try resource("owned-playlist-cover", "png")
        let fixture = try PlexMusicFixture(audio: audio, artwork: cover), origin = try await fixture.start(), scope = SharedMusicScope()
        let plex = PlexMusicService(scope: scope.scope, currentScope: { scope.scope })
        let server = SubsonicMusicService(scope: scope.scope, currentScope: { scope.scope }, persistence: SharedMusicPairingDisk())
        let store = MusicPlaylistStore(owner: scope.scope.owner, persistence: SharedMusicDisk())
        let session = MusicPlaybackSession(server: server, playlists: store, localRecords: { [] }, plex: plex, currentScope: { scope.scope })
        let engine = MusicAudioEngine(), player = MusicPlayback(engine: engine, systemIntegration: false, recordPlayed: { _, _ in })
        let oldVolume = player.volume, oldShuffle = player.shuffle, oldRepeat = player.repeatMode
        player.changeVolume(0); player.shuffle = false; player.repeatMode = .off
        defer {
            player.stop(); plex.dispose(); server.dispose(); fixture.stop(); cleanup(scope.scope.owner)
            player.volume = oldVolume; player.shuffle = oldShuffle; player.repeatMode = oldRepeat
        }
        try await plex.connect(address: origin.absoluteString, token: "owned-plex-token")
        let reopened = PlexMusicService(scope: scope.scope, currentScope: { scope.scope }); XCTAssertTrue(reopened.configured); reopened.dispose()
        let result = try await plex.search("Owned", limit: 24), track = try XCTUnwrap(result.tracks.first)
        XCTAssertEqual(result.artists.first?.name, "Owned artist"); XCTAssertEqual(result.playlists.count, 1); XCTAssertEqual(result.albums.count, 1)
        let serialized = String(decoding: try JSONEncoder().encode(track), as: UTF8.self)
        XCTAssertFalse(serialized.contains("owned-plex-token")); XCTAssertFalse(serialized.contains(origin.absoluteString)); XCTAssertNil(track.playbackUrl)
        async let firstCover = plex.artwork(track.artwork)
        async let duplicateCover = plex.artwork(track.artwork)
        let covers = try await (firstCover, duplicateCover)
        XCTAssertEqual(covers.0, cover); XCTAssertEqual(covers.1, cover); XCTAssertNotNil(UIImage(data: covers.0))
        XCTAssertEqual(fixture.requests.filter { $0.hasPrefix("GET /photo/:/transcode?") }.count, 1)
        let album = try XCTUnwrap(result.albums.first), playlist = try XCTUnwrap(result.playlists.first), artist = try XCTUnwrap(result.artists.first)
        let albums = try await plex.albumTracks(album), lists = try await plex.playlistTracks(playlist), artists = try await plex.artistTop(artist)
        XCTAssertEqual(albums.map(.id), ["plex:1"]); XCTAssertEqual(lists.map(.id), ["plex:1"]); XCTAssertEqual(artists.map(.id), ["plex:1"])
        let rows = try await plex.home()
        let stations: [MusicCatalogStation] = rows.flatMap(.items).compactMap { if case .station(let value) = $0 { value } else { nil } }
        let detail = MusicCatalogDetailModel(); await detail.load(.station(try XCTUnwrap(stations.first)), kind: .tracks, client: plex)
        XCTAssertEqual(detail.items.count, 1); XCTAssertNil(detail.failure)
        let choices = try await session.sources(for: track); XCTAssertTrue(choices.contains { $0.connectorId == "plex" })
        player.play(track, queue: [track], using: session)
        try await wait { player.loaded && player.position > 0.1 }
        player.setPaused(true); try await wait { player.paused }
        player.seek(2); try await wait { abs(player.position - 2) < 0.25 }
        XCTAssertEqual(player.currentTrack?.connectorId, "plex"); XCTAssertNil(player.error)
        XCTAssertTrue(fixture.requests.contains { $0.hasPrefix("GET /library/parts/1/file.wav?") })
        player.stop(); await engine.stop(request: .max)
        let oldCover = track.artwork
        try plex.disconnect(); XCTAssertFalse(plex.configured)
        try await plex.connect(address: origin.absoluteString, token: "owned-plex-token")
        let count = fixture.requests.count
        do { _ = try await plex.artwork(oldCover); XCTFail("A retired connection must not reuse an old cover") } catch { }
        XCTAssertEqual(fixture.requests.count, count)
    }

    func testLatePlexConnectionAndRememberedAccountStayWithinTheirProfile() async throws {
        let fixture = try PlexMusicFixture(audio: Data(), authDelay: 0.4), origin = try await fixture.start(), scope = SharedMusicScope()
        let original = scope.scope, plex = PlexMusicService(scope: scope.scope, currentScope: { scope.scope })
        defer { plex.dispose(); fixture.stop(); cleanup(original.owner); cleanup(original.owner + "-other") }
        let pending = Task { try await plex.connect(address: origin.absoluteString, token: "owned-plex-token") }
        try await wait { fixture.requests.contains { $0.hasPrefix("GET /library/sections ") } }
        scope.scope = .init(owner: original.owner + "-other", activation: UUID())
        do { try await pending.value; XCTFail("Late authorization must not commit into a retired profile") } catch is CancellationError { }
        XCTAssertNil(plex.account)
        let stale = PlexMusicService(scope: original, currentScope: { original }); XCTAssertFalse(stale.configured); stale.dispose()
        let other = PlexMusicService(scope: scope.scope, currentScope: { scope.scope }); XCTAssertFalse(other.configured); other.dispose()
    }

    func testPlexConnectionAndPrivateMusicCoverRenderForPhoneAndTabletInSixteenLanguages() async throws {
        let fixture = try PlexMusicFixture(audio: resource("owned-tone", "wav"), artwork: resource("owned-playlist-cover", "png"))
        let origin = try await fixture.start(), scope = SharedMusicScope(), service = PlexMusicService(scope: scope.scope, currentScope: { scope.scope })
        let server = SubsonicMusicService(scope: scope.scope, currentScope: { scope.scope }, persistence: SharedMusicPairingDisk())
        let session = MusicPlaybackSession(server: server, playlists: MusicPlaylistStore(owner: scope.scope.owner, persistence: SharedMusicDisk()), localRecords: { [] }, plex: service, currentScope: { scope.scope })
        defer { service.dispose(); server.dispose(); fixture.stop(); cleanup(scope.scope.owner) }
        for language in ["en", "ar", "zh", "fr", "de", "hi", "id", "it", "ja", "ko", "pl", "pt", "ru", "es", "tr", "vi"] {
            let value = DesktopInterfaceText.value("music.mobile.plex.discovery", language: language)
            XCTAssertFalse(value.isEmpty); XCTAssertNotEqual(value, "music.mobile.plex.discovery")
        }
        for (name, size) in [("phone", CGSize(width: 390, height: 844)), ("tablet", CGSize(width: 1024, height: 1366))] {
            try await capture(NavigationStack { PlexMusicConnectionView(service: service, changed: {}) }, name: "plex-form-" + name, size: size)
        }
        try await service.connect(address: origin.absoluteString, token: "owned-plex-token")
        let result = try await service.search("Owned", limit: 24), track = try XCTUnwrap(result.tracks.first)
        _ = try await service.artwork(track.artwork)
        for (name, size) in [("phone", CGSize(width: 390, height: 844)), ("tablet", CGSize(width: 1024, height: 1366))] {
            try await capture(VStack { MusicArtwork(url: track.artwork).frame(width: 180, height: 180); NavigationStack { PlexMusicConnectionView(service: service, changed: {}) } }.environment(.musicPlaybackSession, session), name: "plex-cover-connected-" + name, size: size)
        }
    }
    private func capture<V: View>(_ content: V, name: String, size: CGSize) async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first { $0.isKeyWindow }, window = UIWindow(windowScene: scene)
        window.frame = CGRect(origin: .zero, size: size)
        let host = UIHostingController(rootView: content.preferredColorScheme(.dark))
        window.rootViewController = host; window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil; previous?.makeKeyAndVisible() }
        host.view.layoutIfNeeded(); try await Task.sleep(for: .milliseconds(600))
        let image = UIGraphicsImageRenderer(size: size).image { _ in XCTAssertTrue(host.view.drawHierarchy(in: CGRect(origin: .zero, size: size), afterScreenUpdates: true)) }
        let attachment = XCTAttachment(image: image); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    private func resource(_ name: String, _ type: String) throws -> Data { try Data(contentsOf: XCTUnwrap(Bundle(for: Self.self).url(forResource: name, withExtension: type, subdirectory: "Fixtures"))) }
    private func cleanup(_ owner: String) { try? KeychainStore().remove("music-plex-account-" + EBookShelf.hash(owner)) }
    private func wait(_ condition: @MainActor () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline { if condition() { return }; try await Task.sleep(for: .milliseconds(30)) }
        XCTFail("Owned Plex operation did not settle"); throw HarborError(code: "owned-plex-timeout")
    }
}

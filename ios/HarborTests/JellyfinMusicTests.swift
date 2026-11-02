import SwiftUI
import UIKit
import XCTest
@testable import Harbor

@MainActor final class JellyfinMusicTests: XCTestCase {
    func testOriginalJellyfinCatalogRadioAndRealPlaybackUseTheOwnedServer() async throws {
        let file = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "owned-tone", withExtension: "wav", subdirectory: "Fixtures"))
        let fixture = try JellyfinMusicFixture(audio: Data(contentsOf: file)), origin = try await fixture.start(), scope = SharedMusicScope()
        let service = JellyfinMusicService(scope: scope.scope, currentScope: { scope.scope })
        let server = SubsonicMusicService(scope: scope.scope, currentScope: { scope.scope }, persistence: SharedMusicPairingDisk())
        let playlists = MusicPlaylistStore(owner: scope.scope.owner, persistence: SharedMusicDisk())
        let session = MusicPlaybackSession(server: server, playlists: playlists, localRecords: { [] }, jellyfin: service, currentScope: { scope.scope })
        let engine = MusicAudioEngine(), player = MusicPlayback(engine: engine, systemIntegration: false, recordPlayed: { _, _ in })
        let oldVolume = player.volume, oldShuffle = player.shuffle, oldRepeat = player.repeatMode
        player.changeVolume(0); player.shuffle = false; player.repeatMode = .off
        defer {
            player.stop(); service.dispose(); server.dispose(); fixture.stop()
            player.volume = oldVolume; player.shuffle = oldShuffle; player.repeatMode = oldRepeat
            try? KeychainStore().remove("music-jellyfin-account-" + EBookShelf.hash(scope.scope.owner))
        }
        try await service.connect(address: origin.absoluteString + "/", username: "owned", password: "owned-password")
        XCTAssertEqual(service.account?.origin, origin.absoluteString)
        XCTAssertEqual(service.account?.userName, "Owned listener")
        let reopened = JellyfinMusicService(scope: scope.scope, currentScope: { scope.scope })
        XCTAssertTrue(reopened.configured); reopened.dispose()
        let rows = try await service.home()
        XCTAssertEqual(Set(rows.map(.id)), Set(["jellyfin:home:recent", "jellyfin:home:stations", "jellyfin:home:playlists", "jellyfin:home:favourites"]))
        let found = try await service.search("Owned", limit: 24), track = try XCTUnwrap(found.tracks.first)
        XCTAssertEqual(found.albums.count, 1); XCTAssertEqual(found.artists.count, 1); XCTAssertEqual(found.playlists.count, 1)
        XCTAssertNil(track.playbackUrl); XCTAssertFalse(track.artwork.contains("owned-token"))
        let album = try XCTUnwrap(found.albums.first), albumTracks = try await service.albumTracks(album)
        XCTAssertEqual(albumTracks.map(.id), ["jellyfin:a1"])
        let station = try XCTUnwrap(rows.flatMap(.items).compactMap { if case .station(let value) = $0 { value } else { nil } }.first)
        let model = MusicCatalogDetailModel(); await model.load(.station(station), kind: .tracks, client: service)
        XCTAssertEqual(model.items.count, 1); XCTAssertNil(model.failure)
        let matches = try await session.sources(for: track)
        XCTAssertTrue(matches.contains { $0.connectorId == "jellyfin" })
        XCTAssertFalse(fixture.requests.contains { $0.hasPrefix("POST /jellyfin/Sessions/Playing ") })
        player.play(track, queue: [track], using: session)
        try await wait { player.loaded && player.position > 0.1 }
        player.setPaused(true); try await wait { player.paused }
        player.seek(2); try await wait { abs(player.position - 2) < 0.25 }
        try await wait { fixture.requests.contains { $0.hasPrefix("POST /jellyfin/Sessions/Playing ") } }
        XCTAssertTrue(fixture.requests.contains { $0.hasPrefix("GET /jellyfin/Audio/a1/universal?") })
        XCTAssertEqual(player.currentTrack?.connectorId, "jellyfin"); XCTAssertNil(player.error)
        player.stop(); await engine.stop(request: .max)
        try await wait { fixture.requests.contains { $0.hasPrefix("POST /jellyfin/Sessions/Playing/Stopped ") } }
        XCTAssertEqual(fixture.requests.filter { $0.hasPrefix("POST /jellyfin/Sessions/Playing ") }.count, 1)
        XCTAssertEqual(fixture.requests.filter { $0.hasPrefix("POST /jellyfin/Sessions/Playing/Stopped ") }.count, 1)
        try service.disconnect(); XCTAssertFalse(service.configured)
        let disconnected = JellyfinMusicService(scope: scope.scope, currentScope: { scope.scope }); XCTAssertFalse(disconnected.configured); disconnected.dispose()
    }

    func testLateJellyfinAuthorizationCannotPersistIntoAnotherProfile() async throws {
        let fixture = try JellyfinMusicFixture(audio: Data(), authDelay: 0.4), origin = try await fixture.start(), scope = SharedMusicScope()
        let original = scope.scope
        let service = JellyfinMusicService(scope: original, currentScope: { scope.scope })
        defer { service.dispose(); fixture.stop(); try? KeychainStore().remove("music-jellyfin-account-" + EBookShelf.hash(original.owner)) }
        let task = Task { try await service.connect(address: origin.absoluteString, username: "owned", password: "owned-password") }
        try await wait { fixture.requests.contains { $0.hasPrefix("POST /jellyfin/Users/AuthenticateByName ") } }
        scope.scope = .init(owner: original.owner + "-other", activation: UUID())
        do { try await task.value; XCTFail("A retired profile must not receive an account") } catch is CancellationError { }
        XCTAssertNil(service.account)
        let fresh = JellyfinMusicService(scope: original, currentScope: { original }); XCTAssertFalse(fresh.configured); fresh.dispose()
        let other = JellyfinMusicService(scope: scope.scope, currentScope: { scope.scope }); XCTAssertFalse(other.configured); other.dispose()
        scope.scope = original
        let cancelled = Task { try await service.connect(address: origin.absoluteString, username: "owned", password: "owned-password") }
        try await wait { fixture.requests.filter { $0.hasPrefix("POST /jellyfin/Users/AuthenticateByName ") }.count >= 2 }
        service.cancelPending()
        do { try await cancelled.value; XCTFail("Cancelled authorization must not persist") } catch is CancellationError { }
        XCTAssertNil(service.account)
    }

    func testDisconnectRejectsPrivateRowsWhileAnotherCatalogIsStillLoading() async throws {
        let fixture = try JellyfinMusicFixture(audio: Data()), origin = try await fixture.start(), scope = SharedMusicScope()
        let service = JellyfinMusicService(scope: scope.scope, currentScope: { scope.scope })
        let server = SubsonicMusicService(scope: scope.scope, currentScope: { scope.scope }, persistence: SharedMusicPairingDisk())
        let gate = SharedMusicGate(), catalog = JellyfinWaitingPublicCatalog(gate: gate)
        let client = MusicServerCatalogClient(server: server, catalog: catalog, jellyfin: service, currentScope: { scope.scope })
        defer { Task { await gate.release() } }
        defer { service.dispose(); server.dispose(); fixture.stop(); try? KeychainStore().remove("music-jellyfin-account-" + EBookShelf.hash(scope.scope.owner)) }
        try await service.connect(address: origin.absoluteString, username: "owned", password: "owned-password")
        let task = Task { try await client.home() }
        try await wait { fixture.requests.filter { $0.hasPrefix("GET /jellyfin/Items?") }.count >= 4 }
        try await Task.sleep(for: .milliseconds(100))
        try service.disconnect(); await gate.release()
        do { _ = try await task.value; XCTFail("An old account's rows must not return after disconnect") } catch is CancellationError { }
    }

    func testJellyfinConnectionRendersForPhoneAndTabletWithoutDesktopFields() async throws {
        let scope = SharedMusicScope(), service = JellyfinMusicService(scope: scope.scope, currentScope: { scope.scope })
        defer { service.dispose() }
        for (name, size) in [("phone", CGSize(width: 390, height: 844)), ("tablet", CGSize(width: 1024, height: 1366))] {
            let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
            let previous = scene.windows.first { $0.isKeyWindow }, window = UIWindow(windowScene: scene)
            window.frame = CGRect(origin: .zero, size: size)
            let host = UIHostingController(rootView: NavigationStack { JellyfinMusicConnectionView(service: service, changed: {}) }.preferredColorScheme(.dark))
            window.rootViewController = host; window.makeKeyAndVisible()
            defer { window.isHidden = true; window.rootViewController = nil; previous?.makeKeyAndVisible() }
            host.view.layoutIfNeeded(); try await Task.sleep(for: .milliseconds(450))
            XCTAssertEqual(host.view.bounds.width, size.width, accuracy: 1)
            XCTAssertEqual(host.view.bounds.height, size.height, accuracy: 1)
            let image = UIGraphicsImageRenderer(size: size).image { _ in XCTAssertTrue(host.view.drawHierarchy(in: CGRect(origin: .zero, size: size), afterScreenUpdates: true)) }
            let attachment = XCTAttachment(image: image); attachment.name = "jellyfin-" + name; attachment.lifetime = .keepAlways; add(attachment)
        }
    }
    private func wait(_ condition: @MainActor () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline { if condition() { return }; try await Task.sleep(for: .milliseconds(30)) }
        XCTFail("Owned Jellyfin operation did not settle"); throw HarborError(code: "owned-jellyfin-timeout")
    }
}

private struct JellyfinWaitingPublicCatalog: MusicCatalogCalling {
    let gate: SharedMusicGate
    func home() async throws -> [MusicCatalogRow] { await gate.hold(); return [] }
    func search(_ query: String, limit: Int) async throws -> MusicCatalogSearch { throw CancellationError() }
    func albumTracks(_ album: MusicCatalogAlbum) async throws -> [MusicTrack] { throw CancellationError() }
    func artistTop(_ artist: MusicCatalogArtist) async throws -> [MusicTrack] { throw CancellationError() }
    func artistRows(_ artist: MusicCatalogArtist) async throws -> [MusicCatalogRow] { throw CancellationError() }
    func artistCatalog(_ artist: MusicCatalogArtist, kind: MusicCatalogKind, cursor: String?) async throws -> MusicCatalogPage { throw CancellationError() }
    func playlistTracks(_ playlist: MusicCatalogPlaylist) async throws -> [MusicTrack] { throw CancellationError() }
}

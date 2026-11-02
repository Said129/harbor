import AVFoundation
import SwiftUI
import UIKit
import XCTest
@testable import Harbor

@MainActor final class MusicAudioTests: XCTestCase {
    func testRealNativeDSPChangesApplyWithoutResettingPauseOrSeekPosition() async throws {
        let file = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "owned-tone", withExtension: "wav", subdirectory: "Fixtures"))
        let owner = "owned-audio-" + UUID().uuidString, preferences = MusicAudioPreferences(owner: owner)
        defer { cleanup(owner) }
        var options = MusicAudioOptions()
        options.eqEnabled = true; options.eqBands[5] = -6; options.balance = 1; options.preampDb = -3
        options.speed = 1.25; options.keepPitch = true; options.replayGain = "album"
        let plan = try await preferences.plan(options), engine = MusicAudioEngine()
        try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try AVAudioSession.sharedInstance().setActive(true)
        do {
            try await engine.configure(plan, request: 10)
            try await engine.open(.init(url: file, httpHeaders: [:], mimeType: "audio/wav", bitrate: 0), request: 10, volume: 0, paused: true)
            try await wait(engine, token: 10) { events in events.contains { if case .loaded = $0 { true } else { false } } }
            let initialSignal = await engine.signal(request: 10), signal = try XCTUnwrap(initialSignal)
            XCTAssertEqual(signal.speed ?? 0, 1.25, accuracy: 0.001)
            XCTAssertEqual(signal.replayGain, "album")
            XCTAssertTrue(signal.filters?.contains("equalizer") == true)
            XCTAssertTrue(signal.filters?.contains("pan=") == true)
            XCTAssertGreaterThan(signal.sourceRate ?? 0, 0)
            try await engine.command(.seek(2), request: 10)
            try await wait(engine, token: 10) { events in events.contains { if case .time(let value) = $0 { abs(value - 2) < 0.2 } else { false } } }
            options.dspBypass = true
            let bypass = try await preferences.plan(options)
            try await engine.configure(bypass, request: 10)
            let nextSignal = await engine.signal(request: 10), after = try XCTUnwrap(nextSignal)
            XCTAssertEqual(after.replayGain, "no")
            XCTAssertFalse(after.filters?.contains("equalizer") == true)
            XCTAssertEqual(after.speed ?? 0, 1.25, accuracy: 0.001)
            try await engine.command(.paused(false), request: 10)
            try await wait(engine, token: 10) { events in events.contains { if case .time(let value) = $0 { value > 2.1 && value < 4 } else { false } } }
            try await engine.command(.paused(true), request: 10)
            try await wait(engine, token: 10) { events in events.contains { if case .paused(let value) = $0 { value } else { false } } }
            await engine.stop(request: 11)
            do { try await engine.configure(plan, request: 10); XCTFail("A retired request must not apply to another audio core") } catch is CancellationError { }
            let retired = await engine.signal(request: 10); XCTAssertNil(retired)
        } catch { await engine.stop(request: .max); throw error }
    }

    func testOriginalNineteenPresetsAndListeningProfilesPreserveRoutingAndCeiling() async throws {
        let catalog = try XCTUnwrap(MusicEQPresetCatalog.original)
        XCTAssertEqual(catalog.presets.count, 19)
        XCTAssertEqual(catalog.presets.first(where: { $0.id == "bassBoost" })?.bands, [7, 6, 5, 3, 1, 0, 0, 0, 0, 0])
        let owner = "owned-profiles-" + UUID().uuidString, preferences = MusicAudioPreferences(owner: owner)
        defer { cleanup(owner) }
        var correction = MusicAudioOptions()
        correction.eqEnabled = true; correction.eqBands[2] = -4; correction.device = "other-device"
        correction.boostEnabled = true; correction.volumeLimit = 5; correction.sampleRate = 192000
        try preferences.saveProfile(name: "Owned headphones", settings: correction)
        let reloaded = MusicAudioPreferences(owner: owner)
        let profile = try XCTUnwrap(reloaded.profiles.first)
        var current = MusicAudioOptions(); current.device = "auto"; current.sampleRate = 48000
        let applied = profile.loading(into: current)
        XCTAssertEqual(applied.device, "auto"); XCTAssertEqual(applied.sampleRate, 48000)
        XCTAssertFalse(applied.boostEnabled); XCTAssertEqual(applied.volumeLimit, 1)
        XCTAssertEqual(applied.eqBands[2], -4)
        XCTAssertTrue(MusicAudioPreferences(owner: owner + "-other").profiles.isEmpty)
        for index in 1..<20 { try reloaded.saveProfile(name: "Owned \(index)", settings: current) }
        XCTAssertThrowsError(try reloaded.saveProfile(name: "Overflow", settings: current))
        try reloaded.deleteProfile(profile.id)
        XCTAssertEqual(MusicAudioPreferences(owner: owner).profiles.count, 19)
    }

    func testChangingARealMusicSourcePreservesPositionAndPausedState() async throws {
        let fixture = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "owned-tone", withExtension: "wav", subdirectory: "Fixtures"))
        let scope = SharedMusicScope(), publisher = try SharedMusicPublisher(audio: Data(contentsOf: fixture))
        let base = try await publisher.start()
        let record = try await MusicFileService.shared.importFile(fixture, owner: scope.scope.owner).record
        let disk = SharedMusicDisk(), pairs = SharedMusicPairingDisk()
        let server = SubsonicMusicService(scope: scope.scope, currentScope: { scope.scope }, persistence: pairs)
        let store = MusicPlaylistStore(owner: scope.scope.owner, persistence: disk)
        let session = MusicPlaybackSession(server: server, playlists: store, localRecords: { [record] }, currentScope: { scope.scope })
        let engine = MusicAudioEngine(), player = MusicPlayback(engine: engine, systemIntegration: false, recordPlayed: { _, _ in })
        let oldVolume = player.volume, oldShuffle = player.shuffle, oldRepeat = player.repeatMode
        player.changeVolume(0); player.shuffle = false; player.repeatMode = .off
        defer { player.stop(); player.volume = oldVolume; player.shuffle = oldShuffle; player.repeatMode = oldRepeat; server.dispose(); publisher.stop() }
        do {
            player.play(record.local.track, queue: [record.local.track], using: session)
            try await waitPlayer { player.loaded && player.position > 0.1 }
            player.setPaused(true); try await waitPlayer { player.paused }
            player.seek(2); try await waitPlayer { abs(player.position - 2) < 0.2 }
            let original = record.local.track
            let other = MusicTrack(id: "owned-direct-recording", connectorId: "direct", sourceId: "owned-direct-recording",
                                   playbackUrl: base.appendingPathComponent("audio.wav").absoluteString,
                                   title: original.title, artist: original.artist, album: original.album, artwork: original.artwork,
                                   durationSeconds: original.durationSeconds, durationLabel: original.durationLabel)
            try player.switchSource(other)
            try await waitPlayer { player.loaded && !player.resolving && abs(player.position - 2) < 0.2 }
            XCTAssertEqual(player.currentTrack?.connectorId, "direct")
            XCTAssertTrue(player.paused); XCTAssertEqual(player.items.count, 1)
            XCTAssertTrue(publisher.requests.contains { $0.hasPrefix("GET /audio.wav") })
            XCTAssertNil(player.error)
            player.setPaused(false); try await waitPlayer { !player.paused && player.position > 2.1 }
            player.stop(); await engine.stop(request: .max)
            try await MusicFileService.shared.remove(record, owner: scope.scope.owner)
        } catch {
            player.stop(); await engine.stop(request: .max)
            try? await MusicFileService.shared.remove(record, owner: scope.scope.owner)
            throw error
        }
    }

    func testAudioAndSpotifyConnectionInterfacesRenderOnPhoneAndTablet() async throws {
        let scope = PluginExecutionScope(owner: "owned-audio-ui-" + UUID().uuidString, activation: UUID())
        let workspace = MusicWorkspace(scope: scope, currentScope: { scope })
        let player = MusicPlayback(systemIntegration: false, recordPlayed: { _, _ in })
        defer { workspace.dispose(); player.stop(); cleanup(scope.owner) }
        for (name, size) in [("phone", CGSize(width: 390, height: 844)), ("tablet", CGSize(width: 1024, height: 1366))] {
            try await capture(MusicAudioSettingsView(session: workspace.playback, player: player), name: "audio-" + name, size: size)
            try await capture(NavigationStack { SpotifyMusicView(service: workspace.spotify) }, name: "spotify-" + name, size: size)
        }
    }

    private func wait(_ engine: MusicAudioEngine, token: UInt64, until condition: ([MusicAudioEvent]) -> Bool) async throws {
        let deadline = Date().addingTimeInterval(8)
        while Date() < deadline {
            let events = await engine.read(request: token)
            XCTAssertFalse(events.contains { if case .failed = $0 { true } else { false } })
            if condition(events) { return }
            try await Task.sleep(for: .milliseconds(40))
        }
        XCTFail("Changed native audio operation did not settle"); throw HarborError(code: "owned-audio-timeout")
    }
    private func waitPlayer(_ condition: @MainActor () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(8)
        while Date() < deadline { if condition() { return }; try await Task.sleep(for: .milliseconds(40)) }
        XCTFail("Music source did not preserve its transport state"); throw HarborError(code: "owned-music-switch")
    }
    private func cleanup(_ owner: String) {
        for prefix in ["music-audio-options-", "music-listening-profiles-"] { try? KeychainStore().remove(prefix + EBookShelf.hash(owner)) }
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
        XCTAssertEqual(image.size, size)
        let attachment = XCTAttachment(image: image); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}

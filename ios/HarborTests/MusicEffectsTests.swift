import SwiftUI
import UIKit
import XCTest
@testable import Harbor

private actor HeldEffectsEngine: MusicAudioEngineOperating {
    private let gate = SharedMusicGate()
    private let inner = SharedMusicControlledEngine()
    private var newest: UInt64 = 0, opens = 0
    private(set) var plans: [MusicAudioPlan] = []
    func waiting() async -> Bool { await gate.waiting() }
    func release() async { await gate.release() }
    func configure(_ plan: MusicAudioPlan, request: UInt64) throws {
        guard request >= newest else { throw CancellationError() }
        plans.append(plan)
    }
    func open(_ stream: MusicAudioStream, request: UInt64, volume: Double, paused: Bool) async throws {
        guard request >= newest else { throw CancellationError() }; newest = request; opens += 1
        if opens == 2 { await gate.hold() }
        guard request == newest else { throw CancellationError() }
        try await inner.open(stream, request: request, volume: volume, paused: paused)
    }
    func command(_ command: MusicAudioCommand, request: UInt64) async throws { try await inner.command(command, request: request) }
    func read(request: UInt64) async -> [MusicAudioEvent] { await inner.read(request: request) }
    func stop(request: UInt64) async { newest = max(newest, request); await inner.stop(request: request) }
}

@MainActor final class MusicEffectsTests: XCTestCase {
    func testNativeLiveBeatEffectsRetainPausedClockSavedProcessingAndPanelOwnership() async throws {
        XCTAssertTrue(MusicAudioRuntime.extended)
        let scope = SharedMusicScope(), owner = scope.scope.owner
        let file = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "owned-tone", withExtension: "wav", subdirectory: "Fixtures"))
        let record = try await MusicFileService.shared.importFile(file, owner: owner).record
        let audio = MusicAudioPreferences(owner: owner)
        var options = MusicAudioOptions(); options.eqEnabled = true; options.eqBands[4] = -2; options.speed = 0.9
        try audio.save(try await audio.plan(options))
        let server = SubsonicMusicService(scope: scope.scope, currentScope: { scope.scope }, persistence: SharedMusicPairingDisk())
        let session = MusicPlaybackSession(server: server, playlists: MusicPlaylistStore(owner: owner, persistence: SharedMusicDisk()),
                                          localRecords: { [record] }, audio: audio, currentScope: { scope.scope })
        let engine = MusicAudioEngine(), player = MusicPlayback(engine: engine, systemIntegration: false, recordPlayed: { _, _ in })
        let oldVolume = player.volume; player.changeVolume(0)
        defer { player.stop(); player.volume = oldVolume; server.dispose(); cleanup(owner) }
        var phase = "initial native audio"
        do {
            player.play(record.local.track, queue: [record.local.track], using: session)
            try await wait { player.loaded && player.position > 0.1 }
            phase = "pause"
            player.setPaused(true); try await wait { player.paused }
            let position = player.position, first = try player.beginEffects(using: session)
            phase = "echo and saved processing"
            try await player.applyEffects(.init(kind: "echo", depth: 0.6, beats: 0.75, bpm: 100), lease: first, using: session)
            let initial = await player.audioSignal()
            XCTAssertTrue(initial?.filters?.contains("aecho=") == true); XCTAssertTrue(initial?.filters?.contains("equalizer=") == true)
            XCTAssertEqual(initial?.speed ?? 0, 0.9, accuracy: 0.001)
            XCTAssertTrue(player.paused); XCTAssertEqual(player.position, position, accuracy: 0.1)
            options.preampDb = -3
            try await player.applyAudio(options, using: session)
            XCTAssertEqual(player.audioPlan.effects.kind, "echo")
            XCTAssertEqual(MusicAudioPreferences(owner: owner).options.preampDb, -3)
            let saved = try await MusicAudioPreferences(owner: owner).plan()
            XCTAssertEqual(saved.effects.kind, "off", "A temporary performance effect must not become a saved listening preference")
            let second = try player.beginEffects(using: session)
            phase = "panel replacement and wide effect"
            await player.endEffects(first, using: session)
            XCTAssertEqual(player.audioEffects.kind, "echo", "A retired panel cannot clear the newer panel's audio")
            try await player.applyEffects(.init(kind: "wide", depth: 0.4), lease: second, using: session)
            let wide = await player.audioSignal()
            XCTAssertTrue(wide?.filters?.contains("pan=") == true); XCTAssertFalse(wide?.filters?.contains("aecho=") == true)
            await player.endEffects(second, using: session)
            let cleared = await player.audioSignal()
            XCTAssertFalse(cleared?.filters?.contains("aecho=") == true); XCTAssertFalse(cleared?.filters?.contains("pan=") == true)
            XCTAssertTrue(cleared?.filters?.contains("equalizer=") == true); XCTAssertTrue(player.paused)
            XCTAssertEqual(player.position, position, accuracy: 0.1)
            do { try await player.applyEffects(.init(kind: "echo"), lease: first, using: session); XCTFail("Retired controls must not reapply") }
            catch is CancellationError { }
            player.stop(); await engine.stop(request: .max)
            try await MusicFileService.shared.remove(record, owner: owner)
        } catch {
            let signal = await player.audioSignal()
            let attachment = XCTAttachment(string: "\(phase)\nloaded=\(player.loaded), paused=\(player.paused), position=\(player.position), error=\(player.error ?? "none"), outputRate=\(String(describing: signal?.outputRate)), backend=\(signal?.backend ?? "none")")
            attachment.name = "owned-live-effects-failure-phase"; attachment.lifetime = .keepAlways; add(attachment)
            player.stop(); await engine.stop(request: .max)
            try? await MusicFileService.shared.remove(record, owner: owner)
            throw error
        }
    }

    func testClosingEffectsDuringAReplacementLoadCannotLeaveTheOldPlanOnTheNewRecording() async throws {
        XCTAssertTrue(MusicAudioRuntime.extended)
        let scope = SharedMusicScope(), owner = scope.scope.owner, engine = HeldEffectsEngine()
        let server = SubsonicMusicService(scope: scope.scope, currentScope: { scope.scope }, persistence: SharedMusicPairingDisk())
        let audio = MusicAudioPreferences(owner: owner)
        let session = MusicPlaybackSession(server: server, playlists: MusicPlaylistStore(owner: owner, persistence: SharedMusicDisk()),
                                          localRecords: { [] }, audio: audio, currentScope: { scope.scope })
        let player = MusicPlayback(engine: engine, systemIntegration: false, recordPlayed: { _, _ in })
        defer { player.stop(); server.dispose(); cleanup(owner) }
        let first = track("first"), second = track("second")
        player.play(first, queue: [first, second], using: session)
        try await wait { player.loaded }
        let lease = try player.beginEffects(using: session)
        try await player.applyEffects(.init(kind: "echo"), lease: lease, using: session)
        player.play(second, queue: [first, second], using: session)
        for _ in 0..<400 { if await engine.waiting() { break }; try await Task.sleep(for: .milliseconds(20)) }
        let waiting = await engine.waiting(); XCTAssertTrue(waiting)
        guard waiting else { throw HarborError(code: "owned-effects-load-barrier") }
        await player.endEffects(lease, using: session)
        XCTAssertEqual(player.audioEffects.kind, "off")
        await engine.release()
        try await wait { player.loaded && player.currentTrack?.id == second.id }
        let plans = await engine.plans
        XCTAssertTrue(plans.contains { $0.effects.kind == "echo" })
        XCTAssertEqual(plans.last?.effects.kind, "off"); XCTAssertEqual(player.audioPlan.effects.kind, "off")
        XCTAssertNil(player.error)
    }

    func testBeatEffectControlsRenderWithTouchTargetsOnPhoneTabletAndRightToLeft() async throws {
        let scope = SharedMusicScope(), owner = scope.scope.owner, server = SubsonicMusicService(scope: scope.scope, currentScope: { scope.scope }, persistence: SharedMusicPairingDisk())
        let session = MusicPlaybackSession(server: server, playlists: MusicPlaylistStore(owner: owner, persistence: SharedMusicDisk()),
                                          localRecords: { [] }, audio: MusicAudioPreferences(owner: owner), currentScope: { scope.scope })
        let player = MusicPlayback(engine: SharedMusicControlledEngine(), systemIntegration: false, recordPlayed: { _, _ in })
        let oldLanguage = UserDefaults.standard.string(forKey: "uiLanguage")
        defer {
            player.stop(); server.dispose(); cleanup(owner)
            if let oldLanguage { UserDefaults.standard.set(oldLanguage, forKey: "uiLanguage") }
            else { UserDefaults.standard.removeObject(forKey: "uiLanguage") }
        }
        let song = track("controls"); player.play(song, queue: [song], using: session)
        try await wait { player.loaded }
        for (name, size, direction) in [
            ("phone", CGSize(width: 390, height: 844), LayoutDirection.leftToRight),
            ("tablet", CGSize(width: 1024, height: 1366), LayoutDirection.leftToRight),
            ("rtl-phone", CGSize(width: 390, height: 844), LayoutDirection.rightToLeft)
        ] {
            UserDefaults.standard.set(direction == .rightToLeft ? "ar" : "es", forKey: "uiLanguage")
            let lease = UUID()
            try await capture(NavigationStack { Form { MusicBeatEffectsSection(player: player, session: session, owner: lease) } }.environment(\.layoutDirection, direction),
                              name: "music-beat-effects-" + name, size: size, ready: { player.effectLease == lease })
            await player.endEffects(lease, using: session)
        }
        UserDefaults.standard.set("es", forKey: "uiLanguage")
        for (name, size) in [("phone", CGSize(width: 390, height: 844)), ("tablet", CGSize(width: 1024, height: 1366))] {
            try await capture(MusicAudioSettingsView(session: session, player: player), name: "music-audio-revised-" + name, size: size)
        }
        for code in InterfaceLanguage.all.map(\.code) {
            for key in ["dj.fx.beat", "dj.fx.echo", "dj.fx.delay", "dj.fx.spiral", "dj.fx.wide", "dj.fx.depth", "dj.fx.beats", "dj.bpm"] {
                XCTAssertNotEqual(DesktopInterfaceText.value(key, language: code), key)
            }
        }
    }

    private func track(_ id: String) -> MusicTrack {
        .init(id: id, connectorId: "direct", sourceId: id, playbackUrl: "https://owned.invalid/" + id + ".wav",
              title: "Owned " + id, artist: "Owned Artist", album: nil, artwork: "", durationSeconds: 8, durationLabel: "0:08")
    }
    private func cleanup(_ owner: String) { try? KeychainStore().remove("music-audio-options-" + EBookShelf.hash(owner)) }
    private func wait(_ condition: @MainActor () -> Bool) async throws {
        for _ in 0..<500 { if condition() { return }; try await Task.sleep(for: .milliseconds(20)) }
        XCTFail("Owned live effects did not settle"); throw HarborError(code: "owned-effects-timeout")
    }
    private func capture<V: View>(_ view: V, name: String, size: CGSize, ready: (@MainActor () -> Bool)? = nil) async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first { $0.isKeyWindow }, window = UIWindow(windowScene: scene)
        window.frame = CGRect(origin: .zero, size: size)
        let host = UIHostingController(rootView: view.preferredColorScheme(.dark))
        window.rootViewController = host; window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil; previous?.makeKeyAndVisible() }
        host.view.layoutIfNeeded()
        if let ready { try await wait(ready) }
        try await Task.sleep(for: .milliseconds(450))
        let image = UIGraphicsImageRenderer(size: size).image { _ in host.view.drawHierarchy(in: CGRect(origin: .zero, size: size), afterScreenUpdates: true) }
        let attachment = XCTAttachment(image: image); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}

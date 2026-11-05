import AVFoundation
import Observation
import SwiftUI
import UIKit
import XCTest
@testable import Harbor

@MainActor final class MusicMeterTests: XCTestCase {
    func testOriginalMeasuredNativeBandsFollowSeeksAndSilenceWithoutChangingTheListeningPlan() async throws {
        XCTAssertTrue(MusicAudioMeter.supported, "The verified spectrum-filter candidate is required")
        var history = MusicAudioSpectrum()
        sample(&history, time: 1, level: -12); sample(&history, time: 1.1, level: -30)
        XCTAssertEqual(history.at(0.8)[0], -120); XCTAssertEqual(history.at(1)[0], -12)
        XCTAssertEqual(history.at(1.1)[0], -30); XCTAssertEqual(history.at(1.5)[0], -120)
        for index in 0..<1000 { sample(&history, time: Double(index), level: -18) }
        XCTAssertEqual(history.at(0)[0], -120)
        sample(&history, time: 0, level: -6); XCTAssertEqual(history.at(0)[0], -6)
        XCTAssertEqual(MusicAudioMeter.decibels("-inf"), -120); XCTAssertNil(MusicAudioMeter.decibels("NaN"))
        let engine = MusicAudioEngine()
        try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try AVAudioSession.sharedInstance().setActive(true)
        let file = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "owned-meter-tones", withExtension: "wav", subdirectory: "Fixtures"))
        var options = MusicAudioOptions(); options.preampDb = -3; options.eqEnabled = true; options.eqBands[4] = -2
        let plan: MusicAudioPlan = try await CoreBridge().call("musicAudioPlan", ["settings": try .encoded(options)])
        do {
            try await engine.configure(plan, request: 10)
            try await engine.open(.init(url: file, httpHeaders: [:], mimeType: "audio/wav", bitrate: 0), request: 10, volume: 0, paused: false)
            try await meter(engine, true, revision: 1, phase: "enable-before-load")
            let first = try await measurement(engine, phase: "initial-500Hz") { time, value in time > 0.1 && time < 3 && value.active && value.channels.count == 2 && value.spectrumDb.count == 8 && value.spectrumDb[3] > -40 }
            XCTAssertGreaterThan(first.channels[0].peakDb, first.channels[1].peakDb + 3)
            XCTAssertLessThan(first.channels[0].rmsDb, first.channels[0].peakDb)
            XCTAssertTrue(first.channels.allSatisfy { $0.rmsDb.isFinite && $0.peakDb.isFinite })
            XCTAssertEqual(first.spectrumDb.enumerated().max(by: { $0.element < $1.element })?.offset, 3)
            let signal = await engine.signal(request: 10)
            XCTAssertTrue(signal?.filters?.contains("harbor_meter") == true); XCTAssertTrue(signal?.filters?.contains("equalizer=") == true)
            try await engine.command(.seek(4.5), request: 10)
            let silent = try await measurement(engine, phase: "seek-silence") { time, value in time >= 4.5 && time < 5.8 && value.active && value.channels.count == 2 && value.channels.allSatisfy { $0.rmsDb < -90 } && value.spectrumDb.count == 8 && value.spectrumDb.allSatisfy { $0 < -90 } }
            XCTAssertTrue(silent.channels.allSatisfy { $0.peakDb <= -90 })
            try await engine.command(.seek(7), request: 10)
            let after = try await measurement(engine, phase: "seek-120Hz") { time, value in time >= 7 && time < 9 && value.active && value.spectrumDb.count == 8 && value.spectrumDb[1] > -40 }
            XCTAssertEqual(after.spectrumDb.enumerated().max(by: { $0.element < $1.element })?.offset, 1)
            try await meter(engine, false, revision: 5, phase: "disable-after-seeks")
            let cleared = await engine.signal(request: 10)
            XCTAssertFalse(cleared?.filters?.contains("harbor_meter") == true)
            XCTAssertTrue(cleared?.filters?.contains("equalizer=") == true)
            let stopped = await engine.meterSnapshot(request: 10); XCTAssertNil(stopped)
            do { try await engine.setMetering(true, request: 10, revision: 4); XCTFail("A retired consumer cannot restart analysis") } catch is CancellationError { }
            let stillOff = await engine.signal(request: 10); XCTAssertFalse(stillOff?.filters?.contains("harbor_meter") == true)
            await engine.stop(request: 11)
            do { try await engine.setMetering(true, request: 10, revision: 100); XCTFail("An old recording cannot acquire the newer decoder") } catch is CancellationError { }
            await engine.stop(request: .max)
        } catch { await engine.stop(request: .max); throw error }
    }

    func testOwnedMeterConsumersReleaseAnalysisAndRenderPhoneTabletAndArabicWithoutInventedFrames() async throws {
        XCTAssertTrue(MusicAudioMeter.supported)
        let scope = SharedMusicScope(), owner = scope.scope.owner
        let file = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "owned-meter-tones", withExtension: "wav", subdirectory: "Fixtures"))
        let record = try await MusicFileService.shared.importFile(file, owner: owner).record
        let audio = MusicAudioPreferences(owner: owner); audio.showLevels = true; audio.dockVisualizer = true
        XCTAssertTrue(MusicAudioPreferences(owner: owner).dockVisualizer)
        XCTAssertFalse(MusicAudioPreferences(owner: owner + "-other").dockVisualizer)
        let server = SubsonicMusicService(scope: scope.scope, currentScope: { scope.scope }, persistence: SharedMusicPairingDisk())
        let session = MusicPlaybackSession(server: server, playlists: MusicPlaylistStore(owner: owner, persistence: SharedMusicDisk()),
                                          localRecords: { [record] }, audio: audio, currentScope: { scope.scope })
        let engine = MusicAudioEngine(), player = MusicPlayback(engine: engine, systemIntegration: false, recordPlayed: { _, _ in })
        let oldVolume = player.volume, oldLanguage = UserDefaults.standard.string(forKey: "uiLanguage")
        player.changeVolume(0)
        defer {
            player.stop(); player.volume = oldVolume; server.dispose()
            for prefix in ["music-levels-", "music-spectrum-"] { UserDefaults.standard.removeObject(forKey: prefix + EBookShelf.hash(owner)) }
            if let oldLanguage { UserDefaults.standard.set(oldLanguage, forKey: "uiLanguage") }
            else { UserDefaults.standard.removeObject(forKey: "uiLanguage") }
        }
        do {
            player.play(record.local.track, queue: [record.local.track], using: session)
            try await wait { player.loaded && player.position > 0.1 }
            let first = player.acquireMeter(), second = player.acquireMeter()
            try await waitAsync {
                let value = try await player.meterSnapshot(first)
                return value?.measurement.channels.count == 2 && value?.measurement.spectrumDb.count == 8
            }
            await player.releaseMeter(first)
            let retained = await player.audioSignal(); XCTAssertTrue(retained?.filters?.contains("harbor_meter") == true)
            let retired = try await player.meterSnapshot(first); XCTAssertNil(retired)
            let effect = try player.beginEffects(using: session)
            try await player.applyEffects(.init(kind: "echo", depth: 0.4, beats: 0.5, bpm: 120), lease: effect, using: session)
            let combined = await player.audioSignal()
            XCTAssertTrue(combined?.filters?.contains("aecho=") == true)
            XCTAssertTrue(combined?.filters?.contains("harbor_meter") == true)
            await player.releaseMeter(second)
            let released = await player.audioSignal(); XCTAssertFalse(released?.filters?.contains("harbor_meter") == true)
            XCTAssertTrue(released?.filters?.contains("aecho=") == true)
            await player.endEffects(effect, using: session)
            let cleared = await player.audioSignal(); XCTAssertFalse(cleared?.filters?.contains("aecho=") == true)
            for (name, size, language, direction) in [
                ("phone", CGSize(width: 390, height: 844), "es", LayoutDirection.leftToRight),
                ("tablet", CGSize(width: 1024, height: 1366), "es", LayoutDirection.leftToRight),
                ("arabic-phone", CGSize(width: 390, height: 844), "ar", LayoutDirection.rightToLeft)
            ] {
                UserDefaults.standard.set(language, forKey: "uiLanguage")
                // The tones last twelve seconds and a slow runner can spend longer than that on the steps above or on an
                // earlier capture. Starting the track again makes every capture begin with a playing, freshly loaded player.
                player.play(record.local.track, queue: [record.local.track], using: session)
                try await wait { player.loaded && player.position > 0.1 && player.position < 3 }
                do { try await capture(player, name: "music-measured-meter-" + name, size: size, direction: direction) }
                catch {
                    let failure = await engine.meterFailure, signal = await player.audioSignal()
                    XCTFail("The \(name) meters did not settle: mpv=\(failure ?? "none"), consumers=\(player.meterConsumerCount), signal=\(signal == nil ? "nil" : "present"), af=\(signal?.filters ?? "-"), phase=\(player.phase), loaded=\(player.loaded), position=\(player.position)")
                    throw error
                }
            }
            XCTAssertNil(player.error)
            player.stop(); await engine.stop(request: .max)
            try await MusicFileService.shared.remove(record, owner: owner)
        } catch {
            player.stop(); await engine.stop(request: .max)
            try? await MusicFileService.shared.remove(record, owner: owner)
            throw error
        }
    }

    private func sample(_ history: inout MusicAudioSpectrum, time: Double, level: Double) {
        history.ingest("ametadata@harbor_band_0: frame:0 pts:0 pts_time:\(time)")
        history.ingest("ametadata@harbor_band_0: lavfi.astats.Overall.RMS_level=\(level)")
    }
    private func measurement(_ engine: MusicAudioEngine, phase: String, until condition: (Double, MusicMeterMeasurement) -> Bool) async throws -> MusicMeterMeasurement {
        let deadline = Date().addingTimeInterval(10)
        var position = 0.0
        var diagnostic = "no measurement"
        while Date() < deadline {
            let events = await engine.read(request: 10)
            for event in events {
                if case .time(let value) = event { position = value }
                if case .failed = event { throw HarborError(code: "owned-meter-audio-failure") }
            }
            if let value = await engine.meterSnapshot(request: 10) {
                if condition(position, value) { return value }
                diagnostic = "active=\(value.active), rms=\(value.channels.map(\.rmsDb)), bands=\(value.spectrumDb)"
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTFail("The native analysis did not match \(phase), position=\(position), \(diagnostic)")
        throw HarborError(code: "owned-meter-measurement-timeout")
    }
    private func wait(_ condition: @MainActor () -> Bool) async throws {
        for _ in 0..<500 { if condition() { return }; try await Task.sleep(for: .milliseconds(20)) }
        XCTFail("The owned player meter did not settle"); throw HarborError(code: "owned-meter-player-timeout")
    }
    private func waitAsync(_ phase: String = "consumer", _ condition: @MainActor () async throws -> Bool) async throws {
        for _ in 0..<500 { if try await condition() { return }; try await Task.sleep(for: .milliseconds(20)) }
        XCTFail("The owned analysis consumer did not settle: \(phase)"); throw HarborError(code: "owned-meter-consumer-timeout")
    }
    private func meter(_ engine: MusicAudioEngine, _ enabled: Bool, revision: UInt64, phase: String) async throws {
        do { try await engine.setMetering(enabled, request: 10, revision: revision) }
        catch {
            let failure = await engine.meterFailure
            XCTFail("Native analysis \(phase) failed: \(error), mpv=\(failure ?? "none")")
            throw error
        }
    }
    private func capture(_ player: MusicPlayback, name: String, size: CGSize, direction: LayoutDirection) async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first { $0.isKeyWindow }, window = UIWindow(windowScene: scene)
        window.frame = CGRect(origin: .zero, size: size)
        let presence = MeterPresence()
        let host = UIHostingController(rootView: MeterCaptureRoot(player: player, presence: presence)
            .environment(\.scenePhase, .active).environment(\.layoutDirection, direction).preferredColorScheme(.dark))
        window.rootViewController = host; window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil; previous?.makeKeyAndVisible() }
        host.view.layoutIfNeeded()
        try await waitAsync("acquire-" + name) { await player.audioSignal()?.filters?.contains("harbor_meter") == true }
        try await Task.sleep(for: .milliseconds(450))
        let image = UIGraphicsImageRenderer(size: size).image { _ in host.view.drawHierarchy(in: CGRect(origin: .zero, size: size), afterScreenUpdates: true) }
        let attachment = XCTAttachment(image: image); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
        // Closing is the production path: both consumers leave a visible
        // hierarchy. Hiding a test window does not represent a closed panel.
        presence.shown = false; host.view.layoutIfNeeded()
        // While the looped track restarts there is no signal at all, which also means no meter filter is left behind.
        try await waitAsync("release-" + name) {
            let present = await player.audioSignal()?.filters?.contains("harbor_meter") ?? false
            return player.meterConsumerCount == 0 && !present
        }
    }
}

@MainActor @Observable private final class MeterPresence { var shown = true }

@MainActor private struct MeterCaptureRoot: View {
    let player: MusicPlayback
    let presence: MeterPresence
    var body: some View {
        NavigationStack {
            Form {
                if presence.shown {
                    MusicAudioMeterView(player: player)
                    MusicAudioMeterView(player: player, presentation: .spectrum).frame(width: 152, height: 32)
                }
            }.navigationTitle(DesktopInterfaceText.value("music.quality.title"))
        }
    }
}

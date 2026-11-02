import AVFoundation
import XCTest
@testable import Harbor

@MainActor final class MusicExtendedAudioTests: XCTestCase {
    func testOriginalParametricCrossfeedReverbAndEffectsExecuteInTheNativeAudioCore() async throws {
        XCTAssertTrue(MusicAudioRuntime.extended, "This case requires the verified extended filter candidate")
        XCTAssertEqual(MusicAudioRuntime.version, UInt32((11 << 16) | (14 << 8) | 102))
        let file = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "owned-tone", withExtension: "wav", subdirectory: "Fixtures"))
        let engine = MusicAudioEngine()
        var settings = MusicAudioOptions()
        settings.eqEnabled = true; settings.eqMode = "parametric"; settings.eqStrength = 0.75
        settings.crossfeed = 0.3; settings.reverb = 0.2
        let types = ["peak", "lowShelf", "highShelf", "lowPass", "highPass", "notch"]
        settings.peqFilters = types.enumerated().map { index, type in
            MusicPEQFilter(type: type, frequency: 250 + Double(index) * 250, gain: 0.5, q: 0.7071)
        }
        try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try AVAudioSession.sharedInstance().setActive(true)
        do {
            let plan = try await makePlan(settings)
            XCTAssertTrue(MusicAudioRuntime.supports(plan))
            try await engine.configure(plan, request: 10)
            try await engine.open(.init(url: file, httpHeaders: [:], mimeType: "audio/wav", bitrate: 0), request: 10, volume: 0, paused: true)
            try await wait(engine) { $0.contains { if case .loaded = $0 { true } else { false } } }
            let initial = await engine.signal(request: 10)
            let signal = try XCTUnwrap(initial)
            for name in ["equalizer", "bass", "treble", "lowpass", "highpass", "bandreject", "crossfeed", "aecho"] {
                XCTAssertTrue(signal.filters?.contains(name) == true, name)
            }
            try await engine.command(.seek(2), request: 10)
            try await wait(engine) { $0.contains { if case .time(let value) = $0 { abs(value - 2) < 0.25 } else { false } } }
            settings.eqEnabled = false; settings.crossfeed = 0; settings.reverb = 0
            for kind in ["echo", "delay", "spiral", "wide"] {
                let effects = MusicAudioEffects(kind: kind, depth: 0.4, beats: 0.5, bpm: 120)
                let next = try await makePlan(settings, effects: effects)
                try await engine.configure(next, request: 10)
                let updated = await engine.signal(request: 10)
                XCTAssertTrue(updated?.filters?.contains(kind == "wide" ? "pan=" : "aecho=") == true, kind)
                try await engine.command(.paused(false), request: 10)
                try await wait(engine) { $0.contains { if case .time(let value) = $0 { value > 2.1 && value < 5 } else { false } } }
                try await engine.command(.paused(true), request: 10)
                try await wait(engine) { $0.contains { if case .paused(let value) = $0 { value } else { false } } }
                try await engine.command(.seek(1), request: 10)
                try await wait(engine) { $0.contains { if case .time(let value) = $0 { abs(value - 1) < 0.25 } else { false } } }
            }
            settings.dspBypass = true
            let bypass = try await makePlan(settings, effects: .init(kind: "echo"))
            XCTAssertEqual(bypass.filter, "")
            try await engine.configure(bypass, request: 10)
            let disabled = await engine.signal(request: 10)
            XCTAssertFalse(disabled?.filters?.contains("aecho") == true)
            await engine.stop(request: 11)
        } catch { await engine.stop(request: .max); throw error }
    }

    private func makePlan(_ settings: MusicAudioOptions, effects: MusicAudioEffects = .init()) async throws -> MusicAudioPlan {
        try await CoreBridge().call("musicAudioPlan", ["settings": try .encoded(settings), "effects": try .encoded(effects)])
    }
    private func wait(_ engine: MusicAudioEngine, until condition: ([MusicAudioEvent]) -> Bool) async throws {
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline {
            let events = await engine.read(request: 10)
            XCTAssertFalse(events.contains {
                switch $0 { case .failed: true; case .ended(_, let failed): failed; default: false }
            })
            if condition(events) { return }
            try await Task.sleep(for: .milliseconds(40))
        }
        XCTFail("Extended native audio did not retain the expected transport state")
        throw HarborError(code: "owned-extended-audio-timeout")
    }
}

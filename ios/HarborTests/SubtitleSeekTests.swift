import GLKit
import UIKit
import XCTest
@testable import Harbor

final class SubtitleSeekTests: XCTestCase {
    @available(iOS, deprecated: 12.0)
    @MainActor func testHTTPRangeSeeksRetainEmbeddedAndExternalCuesAndRenderedSubtitles() async throws {
        let clip = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "owned-subtitle-seek", withExtension: "mkv", subdirectory: "Fixtures"))
        let server = try SubtitleRangeFixture(data: Data(contentsOf: clip)); defer { server.stop() }
        let url = try await server.start()
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first { $0.isKeyWindow }, window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 640, height: 360)
        let preferences = PlaybackPreferences.shared.options
        PlaybackPreferences.shared.options = PlaybackOptions()
        defer { window.isHidden = true; window.rootViewController = nil; previous?.makeKeyAndVisible(); PlaybackPreferences.shared.options = preferences }
        let state = PlayerState(), controller = MPVController(source: .init(url: url.absoluteString, headers: nil, subtitles: nil, via: "test-fixture"), state: state, startPaused: true)
        window.rootViewController = controller; window.makeKeyAndVisible(); controller.view.layoutIfNeeded()
        defer { controller.close() }
        let surface = try XCTUnwrap(controller.view as? GLKView)
        try await wait(surface, state: state) { state.loaded && state.paused && state.tracks.contains { $0.type == "sub" } }
        controller.set("demuxer-max-bytes", "64KiB")
        controller.set("demuxer-max-back-bytes", "32KiB")
        let embedded = try XCTUnwrap(state.tracks.first { $0.type == "sub" && !$0.external })
        controller.selectSubtitle(String(embedded.id))
        try await wait(surface, state: state) { !state.subtitleChanging && state.primarySubtitle?.id == embedded.id }
        try await exercise(controller, surface: surface, state: state, prefix: "EMBEDDED")
        try await captureSeek(controller, surface: surface, state: state, prefix: "EMBEDDED", target: 17, cue: 4)
        try await captureSeek(controller, surface: surface, state: state, prefix: "EMBEDDED", target: 5, cue: 1)
        let input = FileManager.default.temporaryDirectory.appendingPathComponent("http-seek-" + UUID().uuidString + ".srt")
        defer { try? FileManager.default.removeItem(at: input) }
        let text = (0..<7).map { index in "\(index + 1)\n00:00:\(String(format: "%02d", index * 4)),000 --> 00:00:\(String(format: "%02d", index * 4 + 3)),500\nEXTERNAL CUE \(index)\n" }.joined(separator: "\n")
        try text.write(to: input, atomically: true, encoding: .utf8)
        controller.importLocalSubtitle(input)
        try await wait(surface, state: state) { !state.subtitleChanging && state.primarySubtitle?.external == true }
        try await exercise(controller, surface: surface, state: state, prefix: "EXTERNAL")
        try await captureSeek(controller, surface: surface, state: state, prefix: "EXTERNAL", target: 17, cue: 4)
        try await captureSeek(controller, surface: surface, state: state, prefix: "EXTERNAL", target: 5, cue: 1)
        XCTAssertTrue(server.requestedOffsets.contains { $0 > 0 }, "The test must execute actual HTTP range reads, not only a cached local file")
        XCTAssertNil(state.subtitleIssue)
        XCTAssertEqual(state.subtitleDelay, 0, accuracy: 0.001)
    }

    @available(iOS, deprecated: 12.0)
    @MainActor private func captureSeek(_ controller: MPVController, surface: GLKView, state: PlayerState, prefix: String, target: Double, cue: Int) async throws {
        controller.run(["seek", String(target), "absolute+exact"])
        try await wait(surface, state: state) { abs(state.position - target) < 0.3 && state.primarySubtitleText.contains("\(prefix) CUE \(cue)") }
        for _ in 0..<3 { surface.display(); try await Task.sleep(for: .milliseconds(50)) }
        let image = surface.snapshot
        let attachment = XCTAttachment(image: image)
        attachment.name = "http-seek-\(prefix.lowercased())-\(Int(target))-cue-\(cue)"; attachment.lifetime = .keepAlways; add(attachment)
    }

    @available(iOS, deprecated: 12.0)
    @MainActor func testEmbeddedAndExternalCuesFollowForwardBackwardAndPausedSeeks() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first { $0.isKeyWindow }
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 320, height: 180)
        let defaults = PlaybackPreferences.shared.options
        let autoSync = UserDefaults.standard.bool(forKey: "subtitleAutoSync")
        PlaybackPreferences.shared.options = PlaybackOptions()
        UserDefaults.standard.set(false, forKey: "subtitleAutoSync")
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("seek-cues-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer {
            window.isHidden = true; window.rootViewController = nil; previous?.makeKeyAndVisible()
            PlaybackPreferences.shared.options = defaults
            UserDefaults.standard.set(autoSync, forKey: "subtitleAutoSync")
            try? FileManager.default.removeItem(at: folder)
        }
        let external = folder.appendingPathComponent("external.srt")
        let cues = (0..<7).map { index in
            "\(index + 1)\n00:00:\(String(format: "%02d", index * 4)),000 --> 00:00:\(String(format: "%02d", index * 4 + 3)),500\nEXTERNAL CUE \(index)\n"
        }.joined(separator: "\n")
        try cues.write(to: external, atomically: true, encoding: .utf8)
        let clip = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "owned-subtitle-seek", withExtension: "mkv", subdirectory: "Fixtures"))
        let state = PlayerState()
        let controller = MPVController(source: .init(url: clip.absoluteString, headers: nil, subtitles: nil, via: "test-fixture"), state: state, startPaused: true)
        window.rootViewController = controller; window.makeKeyAndVisible(); controller.view.layoutIfNeeded()
        defer { controller.close() }
        let surface = try XCTUnwrap(controller.view as? GLKView)
        try await wait(surface, state: state) { state.loaded && state.paused && state.tracks.contains { $0.type == "sub" } }
        let embedded = try XCTUnwrap(state.tracks.first { $0.type == "sub" && !$0.external })
        controller.selectSubtitle(String(embedded.id))
        try await wait(surface, state: state) { !state.subtitleChanging && state.primarySubtitle?.id == embedded.id }
        try await exercise(controller, surface: surface, state: state, prefix: "EMBEDDED")
        controller.importLocalSubtitle(external)
        try await wait(surface, state: state) { !state.subtitleChanging && state.primarySubtitle?.external == true }
        try await exercise(controller, surface: surface, state: state, prefix: "EXTERNAL")
        XCTAssertEqual(state.subtitleDelay, 0, accuracy: 0.001)
        XCTAssertEqual(state.subtitleFPS, 0)
        XCTAssertNil(state.subtitleIssue)
    }

    @available(iOS, deprecated: 12.0)
    @MainActor private func exercise(_ controller: MPVController, surface: GLKView, state: PlayerState, prefix: String) async throws {
        for (target, cue) in [(1.0, 0), (17, 4), (5, 1), (25, 6), (9, 2)] {
            controller.run(["seek", String(target), "absolute+exact"])
            try await wait(surface, state: state) { abs(state.position - target) < 0.3 && state.primarySubtitleText.contains("\(prefix) CUE \(cue)") }
        }
        controller.seekRelative(8)
        try await wait(surface, state: state) { abs(state.position - 17) < 0.3 && state.primarySubtitleText.contains("\(prefix) CUE 4") }
        controller.seekRelative(-12)
        try await wait(surface, state: state) { abs(state.position - 5) < 0.3 && state.primarySubtitleText.contains("\(prefix) CUE 1") }
        controller.set("pause", "no")
        try await wait(surface, state: state) { !state.paused && state.position > 5.1 }
        controller.run(["seek", "21", "absolute+exact"])
        try await wait(surface, state: state) { state.position >= 21 && state.position < 23 && state.primarySubtitleText.contains("\(prefix) CUE 5") }
        controller.set("pause", "yes")
        try await wait(surface, state: state) { state.paused }
    }

    @available(iOS, deprecated: 12.0)
    @MainActor private func wait(_ surface: GLKView, state: PlayerState, until condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(12)
        while Date() < deadline, state.error == nil {
            surface.display()
            if condition() { return }
            try await Task.sleep(for: .milliseconds(40))
        }
        XCTFail("Native seek did not settle: position=\(state.position), text=\(state.primarySubtitleText), error=\(state.error ?? "none")")
        throw HarborError(code: "subtitle-seek-timeout")
    }
}

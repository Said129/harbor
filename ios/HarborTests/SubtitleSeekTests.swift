import GLKit
import UIKit
import XCTest
@testable import Harbor

final class SubtitleSeekTests: XCTestCase {
    @available(iOS, deprecated: 12.0)
    @MainActor func testDownloadedCommunityWebVTTCuesFollowSeeksAfterResumingMidVideo() async throws {
        let clip = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "owned-subtitle-seek", withExtension: "mkv", subdirectory: "Fixtures"))
        let vtt = "WEBVTT\n\n" + (0..<7).map { index in "00:00:\(String(format: "%02d", index * 4)).000 --> 00:00:\(String(format: "%02d", index * 4 + 3)).500\nCOMMUNITY CUE \(index)\n" }.joined(separator: "\n")
        let server = try SubtitleRangeFixture(data: Data(contentsOf: clip), subtitle: Data(vtt.utf8))
        defer { server.stop() }
        let url = try await server.start(), caption = url.deletingLastPathComponent().appendingPathComponent("community.vtt")
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first { $0.isKeyWindow }, window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 640, height: 360)
        let preferences = PlaybackPreferences.shared.options; PlaybackPreferences.shared.options = PlaybackOptions()
        defer { window.isHidden = true; window.rootViewController = nil; previous?.makeKeyAndVisible(); PlaybackPreferences.shared.options = preferences }
        let state = PlayerState(), controller = MPVController(source: .init(url: url.absoluteString, headers: nil, subtitles: nil, via: "test-fixture"), state: state, startMs: 8000, preservePosition: true, startPaused: true)
        window.rootViewController = controller; window.makeKeyAndVisible(); controller.view.layoutIfNeeded()
        defer { controller.close() }
        let surface = try XCTUnwrap(controller.view as? GLKView)
        try await wait(surface, state: state) { state.loaded && state.paused && state.position >= 8 }
        controller.loadAddonSubtitle(.init(url: caption.absoluteString, lang: "spa", id: "owned-community", title: "Owned Community fixture"))
        try await wait(surface, state: state) { !state.subtitleChanging && state.primarySubtitle?.external == true }
        try await exercise(controller, surface: surface, state: state, prefix: "COMMUNITY")
        try await captureSeek(controller, surface: surface, state: state, prefix: "COMMUNITY", target: 17, cue: 4)
        try await captureSeek(controller, surface: surface, state: state, prefix: "COMMUNITY", target: 5, cue: 1)
        XCTAssertNotNil(state.addonSubtitleTracks[caption.absoluteString]); XCTAssertNil(state.subtitleIssue)
        XCTAssertEqual(state.subtitleDelay, 0, accuracy: 0.001)
    }

    @available(iOS, deprecated: 12.0)
    @MainActor func testHTTPRangeSeeksRetainEmbeddedAndExternalCuesAndRenderedSubtitles() async throws {
        let clip = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "owned-indexed-subtitle-seek", withExtension: "mkv", subdirectory: "Fixtures"))
        let server = try SubtitleRangeFixture(data: Data(contentsOf: clip), chunkDelay: 0.015); defer { server.stop() }
        defer {
            let attachment = XCTAttachment(string: server.requestedOffsets.map(String.init).joined(separator: ","))
            attachment.name = "owned-http-range-offsets"; attachment.lifetime = .keepAlways; add(attachment)
        }
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
        try await wait(surface, state: state, context: "HTTP loaded paused with subtitle track") { state.loaded && state.paused && state.tracks.contains { $0.type == "sub" } }
        controller.set("demuxer-max-bytes", "64KiB")
        controller.set("demuxer-max-back-bytes", "32KiB")
        let embedded = try XCTUnwrap(state.tracks.first { $0.type == "sub" && !$0.external })
        controller.selectSubtitle(String(embedded.id))
        try await wait(surface, state: state, context: "HTTP embedded selection") { !state.subtitleChanging && state.primarySubtitle?.id == embedded.id }
        let initialRequests = server.requestedOffsets.count
        try await exercise(controller, surface: surface, state: state, prefix: "EMBEDDED")
        try await captureSeek(controller, surface: surface, state: state, prefix: "EMBEDDED", target: 17, cue: 4)
        try await captureSeek(controller, surface: surface, state: state, prefix: "EMBEDDED", target: 5, cue: 1)
        let input = FileManager.default.temporaryDirectory.appendingPathComponent("http-seek-" + UUID().uuidString + ".srt")
        defer { try? FileManager.default.removeItem(at: input) }
        let text = (0..<7).map { index in "\(index + 1)\n00:00:\(String(format: "%02d", index * 4)),000 --> 00:00:\(String(format: "%02d", index * 4 + 3)),500\nEXTERNAL CUE \(index)\n" }.joined(separator: "\n")
        try text.write(to: input, atomically: true, encoding: .utf8)
        controller.importLocalSubtitle(input)
        try await wait(surface, state: state, context: "HTTP external selection") { !state.subtitleChanging && state.primarySubtitle?.external == true }
        try await exercise(controller, surface: surface, state: state, prefix: "EXTERNAL")
        try await captureSeek(controller, surface: surface, state: state, prefix: "EXTERNAL", target: 17, cue: 4)
        try await captureSeek(controller, surface: surface, state: state, prefix: "EXTERNAL", target: 5, cue: 1)
        XCTAssertTrue(server.requestedOffsets.dropFirst(initialRequests).contains { $0 > 0 }, "Seeking must trigger a new HTTP range read after loading; an initial metadata probe is insufficient")
        XCTAssertNil(state.subtitleIssue)
        XCTAssertEqual(state.subtitleDelay, 0, accuracy: 0.001)
    }

    @available(iOS, deprecated: 12.0)
    @MainActor private func captureSeek(_ controller: MPVController, surface: GLKView, state: PlayerState, prefix: String, target: Double, cue: Int) async throws {
        controller.run(["seek", String(target), "absolute+exact"])
        try await wait(surface, state: state, context: "\(prefix) capture seek \(target)") { abs(state.position - target) < 0.3 && state.primarySubtitleText.contains("\(prefix) CUE \(cue)") }
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
            try await wait(surface, state: state, context: "\(prefix) absolute seek \(target)") { abs(state.position - target) < 0.3 && state.primarySubtitleText.contains("\(prefix) CUE \(cue)") }
        }
        controller.seekRelative(8)
        try await wait(surface, state: state, context: "\(prefix) relative +8") { abs(state.position - 17) < 0.3 && state.primarySubtitleText.contains("\(prefix) CUE 4") }
        controller.seekRelative(-12)
        try await wait(surface, state: state, context: "\(prefix) relative -12") { abs(state.position - 5) < 0.3 && state.primarySubtitleText.contains("\(prefix) CUE 1") }
        controller.set("pause", "no")
        try await wait(surface, state: state, context: "\(prefix) resume at 5") { !state.paused && state.position > 5.1 }
        controller.run(["seek", "21", "absolute+exact"])
        try await wait(surface, state: state, context: "\(prefix) playing seek 21") { state.position >= 21 && state.position < 23 && state.primarySubtitleText.contains("\(prefix) CUE 5") }
        controller.set("pause", "yes")
        try await wait(surface, state: state, context: "\(prefix) pause after playing seek") { state.paused }
    }

    @available(iOS, deprecated: 12.0)
    @MainActor private func wait(_ surface: GLKView, state: PlayerState, context: String = "", until condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(12)
        var trace: [String] = [], bucket = -1, captured = false
        while Date() < deadline, state.error == nil {
            surface.display()
            if condition() { return }
            let elapsed = max(0, 12 - deadline.timeIntervalSinceNow), current = Int(elapsed * 2)
            if current != bucket {
                bucket = current
                trace.append("t=\(elapsed) position=\(state.position) paused=\(state.paused) buffered=\(state.buffering) text=\(state.primarySubtitleText) delay=\(state.subtitleDelay) fps=\(String(describing: state.subtitleFPS))")
            }
            if !captured, context.contains("playing seek"), state.position >= 21.2, state.position < 23 {
                captured = true
                let attachment = XCTAttachment(image: surface.snapshot)
                attachment.name = context + "-pending-cue"; attachment.lifetime = .keepAlways; add(attachment)
            }
            try await Task.sleep(for: .milliseconds(40))
        }
        let attachment = XCTAttachment(string: context + "\n" + trace.joined(separator: "\n"))
        attachment.name = "owned-seek-failure-timeline"; attachment.lifetime = .keepAlways; add(attachment)
        XCTFail("Native seek did not settle (\(context)): position=\(state.position), paused=\(state.paused), buffering=\(state.buffering), text=\(state.primarySubtitleText), error=\(state.error ?? "none")")
        throw HarborError(code: "subtitle-seek-timeout")
    }
}

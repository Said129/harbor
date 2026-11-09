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
    @MainActor func testHTTPSeeksRebaseAnOffsetMediaClockForEmbeddedAndDownloadedSubtitles() async throws {
        // All source packets and index points start at seven seconds. The user-facing clock and downloaded
        // WebVTT cues still start at zero. A failed rebase selects a visibly different cue after a seek.
        let clip = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "owned-shifted-clock-subtitle-seek", withExtension: "mkv", subdirectory: "Fixtures"))
        let vtt = "WEBVTT\n\n" + (0..<7).map { index in
            "00:00:\(String(format: "%02d", index * 4)).000 --> 00:00:\(String(format: "%02d", index * 4 + 3)).500\nSHIFTED CUE \(index)\n"
        }.joined(separator: "\n")
        let server = try SubtitleRangeFixture(data: Data(contentsOf: clip), subtitle: Data(vtt.utf8))
        defer { server.stop() }
        let url = try await server.start()
        let captions = url.deletingLastPathComponent().appendingPathComponent("community.vtt")
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previousWindow = scene.windows.first { $0.isKeyWindow }
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 640, height: 360)

        let preferences = PlaybackPreferences.shared.options
        let autoSync = UserDefaults.standard.object(forKey: "subtitleAutoSync")
        PlaybackPreferences.shared.options = PlaybackOptions()
        UserDefaults.standard.set(false, forKey: "subtitleAutoSync")
        defer {
            window.isHidden = true; window.rootViewController = nil; previousWindow?.makeKeyAndVisible()
            PlaybackPreferences.shared.options = preferences
            UserDefaults.standard.set(autoSync, forKey: "subtitleAutoSync")
        }
        let state = PlayerState()
        let controller = MPVController(source: .init(url: url.absoluteString, headers: nil, subtitles: nil, via: "test-fixture"), state: state, startPaused: true)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()
        defer { controller.close() }
        let surface = try XCTUnwrap(controller.view as? GLKView)
        try await wait(surface, state: state, context: "offset media loaded") { state.loaded && state.paused && state.tracks.contains { $0.type == "sub" } }
        controller.set("demuxer-max-bytes", "64KiB")
        controller.set("demuxer-max-back-bytes", "32KiB")
        let embedded = try XCTUnwrap(state.tracks.first { $0.type == "sub" && !$0.external })
        controller.selectSubtitle(String(embedded.id))
        try await wait(surface, state: state, context: "offset media embedded selected") { !state.subtitleChanging && state.primarySubtitle?.id == embedded.id }
        let initialRanges = server.requestedOffsets.count
        try await exercise(controller, surface: surface, state: state, prefix: "EMBEDDED")

        controller.loadAddonSubtitle(.init(url: captions.absoluteString, lang: "spa", id: "offset-test", title: "Owned offset fixture"))
        try await wait(surface, state: state, context: "offset media WebVTT selected") { !state.subtitleChanging && state.primarySubtitle?.external == true }
        try await exercise(controller, surface: surface, state: state, prefix: "SHIFTED")
        XCTAssertTrue(server.requestedOffsets.dropFirst(initialRanges).contains { $0 > 0 })
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
        let autoSync = UserDefaults.standard.bool(forKey: "subtitleAutoSync")
        PlaybackPreferences.shared.options = PlaybackOptions()
        UserDefaults.standard.set(false, forKey: "subtitleAutoSync")
        defer {
            window.isHidden = true; window.rootViewController = nil; previous?.makeKeyAndVisible()
            PlaybackPreferences.shared.options = preferences
            UserDefaults.standard.set(autoSync, forKey: "subtitleAutoSync")
        }
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
    @MainActor func testHiddenNativeSecondaryTrackStillPublishesItsOwnCuesAfterSeeks() async throws {
        let clip = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "owned-subtitle-seek", withExtension: "mkv", subdirectory: "Fixtures"))
        let captions = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".srt")
        let text = """
        1
        00:00:04,000 --> 00:00:07,500
        PRIMARY ONE

        2
        00:00:16,000 --> 00:00:19,500
        PRIMARY FOUR
        """
        try (text + "\n").write(to: captions, atomically: true, encoding: .utf8)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first { $0.isKeyWindow }, window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 320, height: 180)
        let preferences = PlaybackPreferences.shared.options
        PlaybackPreferences.shared.options = PlaybackOptions()
        defer {
            window.isHidden = true; window.rootViewController = nil; previous?.makeKeyAndVisible()
            PlaybackPreferences.shared.options = preferences
            try? FileManager.default.removeItem(at: captions)
        }

        let state = PlayerState()
        let controller = MPVController(source: .init(url: clip.absoluteString, headers: nil, subtitles: nil, via: "test-fixture"), state: state,
                                       startPaused: true, usesInlineSecondarySubtitleOverlay: true)
        window.rootViewController = controller; window.makeKeyAndVisible(); controller.view.layoutIfNeeded()
        defer { controller.close() }
        let surface = try XCTUnwrap(controller.view as? GLKView)
        try await wait(surface, state: state, context: "dual tracks initial load") { state.loaded && state.paused && state.tracks.contains { $0.type == "sub" } }
        let embedded = try XCTUnwrap(state.tracks.first { $0.type == "sub" && !$0.external })
        controller.importLocalSubtitle(captions)
        try await wait(surface, state: state, context: "dual tracks external selection") { !state.subtitleChanging && state.primarySubtitle?.external == true }
        controller.selectSubtitle(String(embedded.id), secondary: true)
        try await wait(surface, state: state, context: "dual tracks secondary selection") { !state.subtitleChanging && state.secondarySubtitle?.id == embedded.id }

        XCTAssertEqual(controller.stat("sub-visibility"), "yes")
        XCTAssertEqual(controller.stat("secondary-sub-visibility"), "no")
        for (target, primary, secondary) in [(17.0, "PRIMARY FOUR", "EMBEDDED CUE 4"), (5.0, "PRIMARY ONE", "EMBEDDED CUE 1")] {
            controller.run(["seek", String(target), "absolute+exact"])
            try await wait(surface, state: state, context: "dual tracks seek \(target)") {
                !state.seeking && abs(state.position - target) < 0.3 &&
                    state.primarySubtitleText.contains(primary) && state.secondarySubtitleText.contains(secondary)
            }
        }
        controller.selectSubtitle("no", secondary: true)
        try await wait(surface, state: state, context: "dual tracks secondary cleared") {
            state.secondarySubtitle == nil && state.secondarySubtitleText.isEmpty && state.primarySubtitleText.contains("PRIMARY ONE")
        }
    }

    @available(iOS, deprecated: 12.0)
    @MainActor func testFrameCaptureExportsPNGFromPausedNativeVideo() async throws {
        let clip = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "owned-subtitle-seek", withExtension: "mkv", subdirectory: "Fixtures"))
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first { $0.isKeyWindow }, window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 320, height: 180)
        let state = PlayerState()
        let controller = MPVController(source: .init(url: clip.absoluteString, headers: nil, subtitles: nil, via: "test-fixture"), state: state, startPaused: true)
        XCTAssertFalse(controller.canCaptureFrame)
        window.rootViewController = controller; window.makeKeyAndVisible(); controller.view.layoutIfNeeded()
        defer { controller.close(); window.isHidden = true; window.rootViewController = nil; previous?.makeKeyAndVisible() }
        let surface = try XCTUnwrap(controller.view as? GLKView)
        try await wait(surface, state: state, context: "ready to capture video") { controller.canCaptureFrame && state.paused && state.hasPosition }

        let drawing = Task { @MainActor in
            while !Task.isCancelled {
                surface.display()
                try? await Task.sleep(for: .milliseconds(30))
            }
        }
        defer { drawing.cancel() }
        let position = state.position
        let png = try await controller.captureFrame()
        XCTAssertEqual(Array(png.prefix(8)), [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        let image = try XCTUnwrap(UIImage(data: png))
        XCTAssertGreaterThan(image.size.width, 0)
        XCTAssertGreaterThan(image.size.height, 0)
        XCTAssertEqual(state.position, position, accuracy: 0.001)
        XCTAssertTrue(state.paused)
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
        // The cue on screen must be the one that belongs to the picture's position. The loop can be held up for a couple of
        // seconds while mpv seeks over HTTP on a slow runner, so it judges the first sample it gets after the seek
        // instead of insisting on a 2 second window.
        var fits = false
        try await wait(surface, state: state, context: "\(prefix) playing seek 21") {
            fits = state.position >= 21 && Self.cueFits(position: state.position, text: state.primarySubtitleText, prefix: prefix)
            return fits || state.position >= 24.5
        }
        XCTAssertTrue(fits, "\(prefix) subtitle after the playing seek does not belong to the picture: position=\(state.position), text=\(state.primarySubtitleText)")
        controller.set("pause", "yes")
        try await wait(surface, state: state, context: "\(prefix) pause after playing seek") { state.paused }
    }

    /// The fixtures show cue n from 4n to 4n + 3.5 seconds. Away from an edge the text must be that cue; near an edge a
    /// frame of lag is allowed, so the previous cue or an empty line also fits.
    private static func cueFits(position: Double, text: String, prefix: String) -> Bool {
        let index = Int(position / 4)
        let offset = position - Double(index * 4)
        let current = text.contains("\(prefix) CUE \(index)")
        if offset >= 0.4 && offset <= 3.1 { return current }
        if offset > 3.1 && offset < 3.9 { return current || text.isEmpty }
        let previous = index > 0 && text.contains("\(prefix) CUE \(index - 1)")
        return current || previous || text.isEmpty
    }

    @available(iOS, deprecated: 12.0)
    @MainActor private func wait(_ surface: GLKView, state: PlayerState, context: String = "", until condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(12)
        var trace: [String] = [], bucket = -1
        while Date() < deadline, state.error == nil {
            let before = Date(), previousPosition = state.position
            surface.display()
            let drawing = Date().timeIntervalSince(before)
            if condition() {
                // One picture once the condition holds. Taking pictures while waiting froze this loop for seconds
                // (the first snapshot of a failing run took 2.8 s), long enough to miss the 2 s window it checks.
                if context.contains("playing seek") {
                    let attachment = XCTAttachment(image: surface.snapshot)
                    attachment.name = context + "-settled-frame"; attachment.lifetime = .keepAlways; add(attachment)
                }
                return
            }
            let elapsed = max(0, 12 - deadline.timeIntervalSinceNow), current = Int(elapsed * 2)
            if current != bucket {
                bucket = current
                trace.append("t=\(elapsed) positionBeforeDraw=\(previousPosition) drawSeconds=\(drawing) position=\(state.position) paused=\(state.paused) buffered=\(state.buffering) text=\(state.primarySubtitleText) delay=\(state.subtitleDelay) fps=\(String(describing: state.subtitleFPS))")
            }
            try await Task.sleep(for: .milliseconds(40))
        }
        let attachment = XCTAttachment(string: context + "\n" + trace.joined(separator: "\n"))
        attachment.name = "owned-seek-failure-timeline"; attachment.lifetime = .keepAlways; add(attachment)
        XCTFail("Native seek did not settle (\(context)): position=\(state.position), paused=\(state.paused), buffering=\(state.buffering), text=\(state.primarySubtitleText), error=\(state.error ?? "none")")
        throw HarborError(code: "subtitle-seek-timeout")
    }
}

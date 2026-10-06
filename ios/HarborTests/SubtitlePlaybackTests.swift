import GLKit
import UIKit
import XCTest
@testable import Harbor

final class SubtitlePlaybackTests: XCTestCase {
    // Exercise actual libass/mpv tracks and acknowledged property transitions,
    // using the existing real video fixture rather than a mocked controller.
    @available(iOS, deprecated: 12.0)
    @MainActor
    func testSubtitleTimingResetsBeforeDualSelectionAndReplay() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first { $0.isKeyWindow }
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 320, height: 180)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("subtitle-playback-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { window.isHidden = true; window.rootViewController = nil; previous?.makeKeyAndVisible(); try? FileManager.default.removeItem(at: directory) }
        let first = directory.appendingPathComponent("primary.srt")
        let second = directory.appendingPathComponent("secondary.srt")
        try "1\n00:00:00,000 --> 00:00:29,500\nPRIMARY ACTUAL SUBTITLE\n".write(to: first, atomically: true, encoding: .utf8)
        try "1\n00:00:00,000 --> 00:00:29,500\nSECONDARY ACTUAL SUBTITLE\n".write(to: second, atomically: true, encoding: .utf8)
        let video = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "render-8bit", withExtension: "mp4", subdirectory: "Fixtures"))
        let source = PlaybackSource(url: video.absoluteString, headers: nil, subtitles: [
            .init(url: first.absoluteString, lang: "eng", id: "primary"), .init(url: second.absoluteString, lang: "spa", id: "secondary")
        ], via: "test-fixture")
        let state = PlayerState()
        let controller = MPVController(source: source, state: state)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()
        defer { controller.close() }
        let surface = try XCTUnwrap(controller.view as? GLKView)
        try await wait(surface, state: state) { state.loaded && state.tracks.filter { $0.type == "sub" }.count == 2 && state.videoFPS != nil && state.subtitleFPS != nil }
        controller.set("pause", "yes")
        try await wait(surface, state: state) { state.paused }
        let main = try XCTUnwrap(state.tracks.first { $0.externalFilename.hasSuffix("primary.srt") })
        let extra = try XCTUnwrap(state.tracks.first { $0.externalFilename.hasSuffix("secondary.srt") })
        XCTAssertTrue(main.isTextSubtitle)
        controller.selectSubtitle(String(main.id))
        try await wait(surface, state: state) { !state.subtitleChanging && state.primarySubtitle?.id == main.id }
        XCTAssertNil(SubtitleTiming.unavailable(state))

        // Enqueue both without waiting: selecting another track must wait for
        // the FPS acknowledgement and its successful reset first.
        controller.applySubtitleFPS(25)
        controller.selectSubtitle(String(extra.id), secondary: true)
        try await wait(surface, state: state) { !state.subtitleChanging && state.secondarySubtitle?.id == extra.id && state.subtitleFPS == 0 }
        XCTAssertNil(state.subtitleIssue)
        XCTAssertNotNil(SubtitleTiming.unavailable(state))
        controller.run(["seek", "1", "absolute+exact"])
        try await wait(surface, state: state) { state.primarySubtitleText.contains("PRIMARY ACTUAL") && state.secondarySubtitleText.contains("SECONDARY ACTUAL") }
        XCTAssertEqual(state.primarySubtitle?.id, main.id)
        XCTAssertEqual(state.secondarySubtitle?.mainSelection, 1)

        controller.selectSubtitle("no", secondary: true)
        try await wait(surface, state: state) { !state.subtitleChanging && state.secondarySubtitle == nil }
        controller.applySubtitleFPS(24000.0 / 1001)
        try await wait(surface, state: state) { !state.subtitleChanging && SubtitleTiming.matches(state.subtitleFPS, 24000.0 / 1001) }
        controller.selectSubtitle(String(extra.id))
        try await wait(surface, state: state) { !state.subtitleChanging && state.primarySubtitle?.id == extra.id && state.subtitleFPS == 0 }
        controller.applySubtitleFPS(30)
        try await wait(surface, state: state) { !state.subtitleChanging && state.subtitleFPS == 30 }
        let generation = state.mediaGeneration
        controller.replay()
        try await wait(surface, state: state) { !state.subtitleChanging && state.mediaGeneration > generation && state.loaded && state.subtitleFPS == 0 && state.tracks.filter { $0.type == "sub" }.count == 2 }
        XCTAssertNil(state.subtitleIssue)
        XCTAssertNil(state.error)
        XCTAssertGreaterThan(state.renderCalls, 0)
    }

    @available(iOS, deprecated: 12.0)
    @MainActor private func wait(_ surface: GLKView, state: PlayerState, until condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(12)
        while Date() < deadline, state.error == nil {
            surface.display()
            if condition() { return }
            try await Task.sleep(for: .milliseconds(50))
        }
        throw NSError(domain: "SubtitlePlaybackTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Actual subtitle operation did not settle; loaded=\(state.loaded), tracks=\(state.tracks.count), primary=\(state.primarySubtitle?.id ?? -1), secondary=\(state.secondarySubtitle?.id ?? -1), fps=\(state.subtitleFPS ?? -1), changing=\(state.subtitleChanging), error=\(state.error ?? state.subtitleIssue ?? "none")"])
    }
}

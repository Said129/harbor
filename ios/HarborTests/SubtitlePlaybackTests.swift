import AVFoundation
import GLKit
import SwiftUI
import UIKit
import XCTest
@testable import Harbor

final class SubtitlePlaybackTests: XCTestCase {
    @MainActor
    func testSecondaryLanguagePriorityAliasesAndRegions() {
        func track(_ id: Int, _ language: String, codec: String = "subrip") -> PlayerState.Track {
            var value = PlayerState.Track(id: id, type: "sub", label: language, selected: false)
            value.language = language; value.codec = codec
            return value
        }
        let tracks = [track(1, "spa"), track(2, "eng"), track(3, "es_MX"), track(4, "por"), track(5, "pt_BR"), track(6, "pt_BR", codec: "hdmv_pgs_subtitle"), track(7, "ara")]
        XCTAssertEqual(SubtitleLanguages.preferredCodes("fra,fre, fr ,eng,en,pt_BR,por"), ["fr", "en", "pt-br", "pt"])
        XCTAssertEqual(SubtitleLanguages.preferredSecondary(in: tracks, excluding: 4, languages: "eng,spa")?.id, 2, "Preference order must take precedence over file track order")
        XCTAssertEqual(SubtitleLanguages.preferredSecondary(in: tracks, excluding: 2, languages: "es-419")?.id, 3)
        XCTAssertEqual(SubtitleLanguages.preferredSecondary(in: tracks, excluding: 4, languages: "pt-br")?.id, 5)
        XCTAssertNil(SubtitleLanguages.preferredSecondary(in: [tracks[4], tracks[5]], excluding: 5, languages: "pt_BR"), "The primary track and bitmap tracks cannot become a second line")
        XCTAssertEqual(SubtitleLanguages.preferredSecondary(in: tracks, excluding: 4, languages: "ar")?.id, 7, "Languages beyond the previous eight must resolve ISO aliases")
        XCTAssertEqual(SubtitleLanguages.preferredSecondary(in: [tracks[0]], excluding: 4, languages: "es-419")?.id, 1, "A generic language is the fallback when its preferred region is unavailable")
        XCTAssertTrue(SubtitleLanguages.allCodes.contains("ar"))
        XCTAssertTrue(SubtitleLanguages.allCodes.contains("zu"))
    }

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

        try await capturePanel(NavigationStack { PlayerTrackPanel(page: .subtitles, state: state) }, in: window, over: controller, name: "native-subtitle-original-tracks")

        controller.selectSubtitle("no", secondary: true)
        try await wait(surface, state: state) { !state.subtitleChanging && state.secondarySubtitle == nil }
        controller.applySubtitleFPS(24000.0 / 1001)
        try await wait(surface, state: state) { !state.subtitleChanging && SubtitleTiming.matches(state.subtitleFPS, 24000.0 / 1001) }
        controller.selectSubtitle(String(extra.id))
        try await wait(surface, state: state) { !state.subtitleChanging && state.primarySubtitle?.id == extra.id && state.subtitleFPS == 0 }
        controller.applySubtitleFPS(30)
        try await wait(surface, state: state) { !state.subtitleChanging && state.subtitleFPS == 30 }
        try await capturePanel(NavigationStack { SubtitleTimingView(state: state) }, in: window, over: controller, name: "native-subtitle-original-fps")
        let generation = state.mediaGeneration
        controller.replay()
        try await wait(surface, state: state) { !state.subtitleChanging && state.mediaGeneration > generation && state.loaded && state.subtitleFPS == 0 && state.tracks.filter { $0.type == "sub" }.count == 2 }
        XCTAssertNil(state.subtitleIssue)
        XCTAssertNil(state.error)
        XCTAssertGreaterThan(state.renderCalls, 0)

        controller.set("pause", "yes")
        try await wait(surface, state: state) { state.paused }
        let replayPrimary = try XCTUnwrap(state.tracks.first { $0.externalFilename.hasSuffix("primary.srt") })
        controller.selectSubtitle(String(replayPrimary.id))
        try await wait(surface, state: state) { !state.subtitleChanging && state.primarySubtitle?.id == replayPrimary.id }
        let importedInput = directory.appendingPathComponent("Imported Spanish.srt")
        let text = "1\n00:00:00,000 --> 00:00:29,500\nIMPORTED ACTUAL SUBTITLE\n"
        try text.write(to: importedInput, atomically: true, encoding: .utf8)
        controller.applySubtitleFPS(25)
        controller.importLocalSubtitle(importedInput)
        try await wait(surface, state: state) { !state.subtitleChanging && state.subtitleImportMessage != nil && state.subtitleFPS == 0 }
        let imported = try XCTUnwrap(state.primarySubtitle)
        XCTAssertTrue(imported.external)
        XCTAssertTrue(state.importedSubtitleIDs.contains(imported.id))
        XCTAssertEqual(imported.title, importedInput.lastPathComponent)
        let copiedFile = imported.externalFilename.hasPrefix("file:") ? try XCTUnwrap(URL(string: imported.externalFilename)) : URL(fileURLWithPath: imported.externalFilename)
        XCTAssertNotEqual(copiedFile.standardizedFileURL.path, importedInput.standardizedFileURL.path)
        XCTAssertEqual(try String(contentsOf: copiedFile, encoding: .utf8), text)
        controller.run(["seek", "1", "absolute+exact"])
        try await wait(surface, state: state) { state.primarySubtitleText.contains("IMPORTED ACTUAL") }
        XCTAssertNil(state.subtitleIssue)
        XCTAssertEqual(SubtitleLanguages.normalize("spa"), "es")
        XCTAssertEqual(SubtitleLanguages.normalize("fre"), "fr")
        XCTAssertEqual(SubtitleLanguages.normalize("es_MX"), "es-419")
        XCTAssertEqual(SubtitleLanguages.normalize("pt_BR"), "pt-br")
        let unsupported = directory.appendingPathComponent("unsupported.txt")
        try text.write(to: unsupported, atomically: true, encoding: .utf8)
        controller.importLocalSubtitle(unsupported)
        try await wait(surface, state: state) { !state.subtitleChanging && state.subtitleIssue != nil }
        XCTAssertEqual(state.primarySubtitle?.id, imported.id)
        XCTAssertNil(state.error, "A rejected Files import must not stop the loaded video")
        let preferences = PlaybackPreferences.shared
        let previousOptions = preferences.options
        preferences.options.resumeAfterInterruption = true
        preferences.options.resumeOnForeground = false
        defer { preferences.options = previousOptions }
        let center = NotificationCenter.default
        func interruption(_ type: AVAudioSession.InterruptionType, options: AVAudioSession.InterruptionOptions = []) {
            center.post(name: AVAudioSession.interruptionNotification, object: AVAudioSession.sharedInstance(), userInfo: [AVAudioSessionInterruptionTypeKey: type.rawValue, AVAudioSessionInterruptionOptionKey: options.rawValue])
        }
        controller.togglePause()
        try await wait(surface, state: state) { !state.paused }
        interruption(.began)
        try await wait(surface, state: state) { state.paused }
        interruption(.ended)
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertTrue(state.paused, "An interruption without shouldResume must leave actual mpv paused")
        controller.togglePause()
        try await wait(surface, state: state) { !state.paused }
        interruption(.began)
        try await wait(surface, state: state) { state.paused }
        interruption(.began)
        try await Task.sleep(for: .milliseconds(100))
        interruption(.ended, options: .shouldResume)
        try await wait(surface, state: state) { !state.paused }
        center.post(name: AVAudioSession.routeChangeNotification, object: AVAudioSession.sharedInstance(), userInfo: [AVAudioSessionRouteChangeReasonKey: AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue])
        try await wait(surface, state: state) { state.paused }
        controller.togglePause()
        try await wait(surface, state: state) { !state.paused }
        center.post(name: UIApplication.willResignActiveNotification, object: nil)
        try await wait(surface, state: state) { state.paused }
        let callbacks = state.renderCalls
        surface.display()
        XCTAssertEqual(state.renderCalls, callbacks, "A suspended surface must not issue mpv GL render calls")
        center.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertTrue(state.paused, "The default foreground preference must keep playback paused")
        preferences.options.resumeOnForeground = true
        controller.togglePause()
        try await wait(surface, state: state) { !state.paused }
        center.post(name: UIApplication.willResignActiveNotification, object: nil)
        try await wait(surface, state: state) { state.paused }
        center.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        try await wait(surface, state: state) { !state.paused }
        controller.run(["seek", "29.8", "absolute+exact"])
        controller.set("pause", "no")
        try await wait(surface, state: state) { state.ended }
        XCTAssertTrue(state.endedNaturally, "Automatic episode advance must use the actual native EOF reason")
        controller.close()
        let cleanupDeadline = Date().addingTimeInterval(3)
        while Date() < cleanupDeadline, FileManager.default.fileExists(atPath: copiedFile.path) { try await Task.sleep(for: .milliseconds(50)) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: copiedFile.path), "Closing the native player removes its private subtitle copies")
        XCTAssertEqual(try String(contentsOf: importedInput, encoding: .utf8), text, "The user's original subtitle must remain untouched")

        let switchedState = PlayerState()
        let switched = MPVController(source: source, state: switchedState, startMs: 28_000, preservePosition: true)
        window.rootViewController = switched
        switched.view.layoutIfNeeded()
        switched.set("pause", "yes")
        defer { switched.close() }
        let switchedSurface = try XCTUnwrap(switched.view as? GLKView)
        try await wait(switchedSurface, state: switchedState) { switchedState.loaded && switchedState.paused && switchedState.hasPosition && switchedState.duration > 29 }
        XCTAssertEqual(switchedState.position, 28, accuracy: 0.75, "Changing source must preserve its real native timestamp inside the final 20 seconds")
        let beforeRetry = switchedState.mediaGeneration
        switched.retry(positionMs: .nan, autoplay: false)
        XCTAssertFalse(switchedState.restarting, "Invalid timestamps must not start a reload")
        switched.retry(positionMs: 28_000, autoplay: false)
        try await wait(switchedSurface, state: switchedState) { switchedState.mediaGeneration > beforeRetry && switchedState.loaded && switchedState.paused && !switchedState.restarting && switchedState.hasPosition }
        XCTAssertNil(switchedState.error)
        XCTAssertEqual(switchedState.position, 28, accuracy: 0.75, "An acknowledged native retry must keep the timestamp near completion")
        let beforeRestart = switchedState.mediaGeneration
        switched.retry(positionMs: 0, autoplay: true)
        try await wait(switchedSurface, state: switchedState) {
            switchedState.mediaGeneration > beforeRestart && switchedState.loaded && !switchedState.paused &&
                !switchedState.restarting && switchedState.hasPosition && switchedState.position < 2
        }
        XCTAssertNil(switchedState.error)
        XCTAssertEqual(switchedState.subtitleFPS, 0, "Restart must clear timing overrides before reloading the actual clip")
        let currentEpisode = Episode(id: "fixture:1:1", season: 1, episode: 1)
        var fixtureSeries = Media(id: "fixture", type: "series", name: "Harbor")
        fixtureSeries.videos = [currentEpisode, Episode(id: "fixture:1:2", season: 1, episode: 2), Episode(id: "fixture:2:1", season: 2, episode: 1)]
        try await capturePanel(PlayerEpisodesView(media: fixtureSeries,
            current: ResumeTarget(id: "fixture", season: 1, episode: 1, videoId: currentEpisode.id), library: nil,
            canRestart: switched.canRestartPlayback, restart: { switched.retry(positionMs: 0, autoplay: true) }, close: {}, play: { _ in }),
            in: window, over: switched, name: "native-player-original-episodes-fixture")
    }

    @available(iOS, deprecated: 12.0)
    @MainActor private func capturePanel<V: View>(_ view: V, in window: UIWindow, over controller: MPVController, name: String) async throws {
        let originalFrame = window.frame
        window.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
        controller.view.layoutIfNeeded()
        let panel = UIHostingController(rootView: view.preferredColorScheme(.dark))
        controller.addChild(panel); controller.view.addSubview(panel.view); panel.didMove(toParent: controller)
        defer {
            panel.willMove(toParent: nil); panel.view.removeFromSuperview(); panel.removeFromParent()
            window.frame = originalFrame; controller.view.layoutIfNeeded()
        }
        panel.view.frame = controller.view.bounds
        try await Task.sleep(for: .milliseconds(400))
        panel.view.layoutIfNeeded()
        let image = UIGraphicsImageRenderer(bounds: panel.view.bounds).image { _ in _ = panel.view.drawHierarchy(in: panel.view.bounds, afterScreenUpdates: true) }
        let attachment = XCTAttachment(image: image)
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
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

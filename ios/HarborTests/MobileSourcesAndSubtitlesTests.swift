import GLKit
import SwiftUI
import UIKit
import XCTest
@testable import Harbor

final class MobileSourcesAndSubtitlesTests: XCTestCase {
    private func addon(_ id: String, enabled: Bool = true) -> Addon {
        Addon(manifest: .object(["id": .string(id), "name": .string(id), "types": .array([.string("movie"), .string("series")]), "resources": .array([.string("subtitles")]), "idPrefixes": .array([.string("tt")])]), transportUrl: "https://example.org/\(id)/manifest.json", enabled: enabled)
    }

    private func offers() -> [StreamOffer] {
        (0..<13).map { index in
            let tier = index < 9 ? (index == 8 ? "1080p_HDR" : "1080p") : index < 11 ? "720p" : "SD"
            return StreamOffer(id: index, raw: .object(["addonId": .string(index == 12 ? "watchhub" : "corenexus"), "addonName": .string(index == 12 ? "WatchHub" : "Core Nexus"), "tier": .string(tier), "name": .string("Danmachi · E07 · \(tier)"), "url": .string("https://example.org/\(index).mkv"), "title": .string("Danmachi.S01E07.\(tier).BluRay.FLAC.mkv")]))
        }
    }

    func testQualityGroupsKeepAllThirteenSourcesAndIntersectProvider() {
        let values = offers()
        XCTAssertEqual(StreamPickerFilter.sources(values, quality: nil, provider: nil).count, 13)
        XCTAssertEqual(StreamPickerFilter.sources(values, quality: "1080p", provider: nil).count, 9, "FHD includes both SDR and HDR sources")
        XCTAssertEqual(StreamPickerFilter.sources(values, quality: "720p", provider: nil).count, 2)
        XCTAssertEqual(StreamPickerFilter.sources(values, quality: "SD", provider: nil).count, 2)
        XCTAssertEqual(StreamPickerFilter.sources(values, quality: "SD", provider: values.last?.pickerInstance).map(\.id), [12])
        XCTAssertTrue(StreamPickerFilter.sources(values, quality: "4K", provider: nil).isEmpty)
        XCTAssertEqual(StreamPickerFilter.sources(values, quality: nil, provider: values[0].pickerInstance).count, 12)
    }

    func testSubtitlePlansUseVerifiedEpisodeAndSafelyEncodeFileHints() async throws {
        var media = Media(id: "kitsu:9962", type: "series", name: "Danmachi", imdbID: "tt4728568")
        media.videos = [Episode(id: "kitsu:9962:7", season: 1, episode: 7, imdbID: "tt4728568", imdbSeason: 1, imdbEpisode: 7)]
        let request = SubtitleRequest(media: media, videoID: "kitsu:9962:7", season: 1, episode: 7, addons: [addon("enabled"), addon("disabled", enabled: false)], stream: .object(["behaviorHints": .object(["filename": .string("Danmachi #7 & 日本語/1080p.mkv"), "videoSize": .integer(12345678), "videoHash": .string("1234abcd")])]))
        let plans = try await request.plans()
        XCTAssertEqual(plans.count, 1)
        let url = try XCTUnwrap(URLComponents(string: plans[0].url))
        XCTAssertTrue(url.path.contains("/subtitles/series/tt4728568:1:7/"))
        XCTAssertTrue(url.percentEncodedPath.contains("%26")); XCTAssertTrue(url.percentEncodedPath.contains("%2F1080p"))
        XCTAssertTrue(url.path.contains("videoSize=12345678")); XCTAssertTrue(url.path.contains("videoHash=1234abcd"))
        XCTAssertNil(url.query); XCTAssertNil(url.fragment)
        media.videos?[0].imdbEpisode = 8
        let mismatched = SubtitleRequest(media: media, videoID: request.videoID, season: 1, episode: 7, addons: request.addons, stream: .null)
        let rejected = try await mismatched.plans()
        XCTAssertTrue(rejected.isEmpty, "Never substitute another mapped anime episode")
    }

    @MainActor func testAutomaticFiltersDoNotRemoveManualPickerSources() async throws {
        let preferences = StreamPreferences.shared
        let old = preferences.filterLevel; preferences.filterLevel = "strict"
        defer { preferences.filterLevel = old }
        let media = Media(id: "tt0903747", type: "series", name: "Breaking Bad", releaseInfo: "2008")
        let raw: [JSONValue] = [1, 2].map { episode in .object(["addonId": .string("test"), "addonName": .string("Test"), "title": .string("Breaking.Bad.S01E0\(episode).1080p.WEB-DL.H264.AAC"), "url": .string("https://example.org/\(episode).mkv"), "size": .integer(2_000_000_000)]) }
        let ranked: JSONValue = try await CoreBridge().call("rank", ["streams": .array(raw), "trust": StreamFilterConfiguration(level: "off", addonOrder: true).trust(media, season: 1, episode: 1), "score": .object([:])])
        let all = ranked["picker"]["all"].array.enumerated().map { StreamOffer(id: $0.offset, raw: $0.element) }
        XCTAssertEqual(all.count, 2)
        let automatic = try await HarborService().automaticStreams(all, media: media, season: 1, episode: 1)
        XCTAssertEqual(automatic.count, 1)
        XCTAssertTrue(automatic.first?.title.contains("S01E01") == true)
        XCTAssertEqual(all.count, 2, "Automatic trust filtering must not mutate the complete manual list")
    }

    func testSubtitleSearchKeepsPartialResultsAndRejectsInvalidURLs() async throws {
        let media = Media(id: "tt15398776", type: "movie", name: "Oppenheimer")
        let request = SubtitleRequest(media: media, videoID: media.id, season: nil, episode: nil, addons: [addon("first"), addon("second"), addon("failed")], stream: .null)
        let response: JSONValue = .object(["subtitles": .array([
            .object(["url": .string("https://example.org/spanish.srt"), "lang": .string("spa"), "label": .string("Español SDH")]),
            .object(["url": .string("javascript:invalid")]),
            .object(["url": .string("file:///private/account.json")]),
            .object(["url": .string("http://127.0.0.1:11470/subtitles.vtt?from=https%3A%2F%2Fexample.org%2Fenglish.srt"), "lang": .string("eng")])])])
        let result = try await SubtitleAddonService().search(request, load: { plan in
            if plan.title == "failed" { throw HarborError(code: "network") }
            return response
        })
        XCTAssertEqual(result.providers, 3); XCTAssertEqual(result.failures, 1)
        XCTAssertEqual(Set(result.subtitles.map(\.url)), ["https://example.org/spanish.srt", "https://example.org/english.srt"])
        XCTAssertTrue(result.subtitles.contains { $0.lang == "spa" && $0.title?.contains("Español SDH") == true })
    }

    func testCancelledSubtitleSearchCannotReturnStaleResults() async throws {
        let media = Media(id: "tt15398776", type: "movie", name: "Oppenheimer")
        let request = SubtitleRequest(media: media, videoID: media.id, season: nil, episode: nil, addons: [addon("slow")], stream: .null)
        let task = Task { try await SubtitleAddonService().search(request, load: { _ in
            try await Task.sleep(for: .seconds(5))
            return .object(["subtitles": .array([])])
        }) }
        task.cancel()
        do { _ = try await task.value; XCTFail("Cancelled subtitle lookup must not publish a result") }
        catch is CancellationError {}
    }

    func testSubtitleDownloadRequestHasNoVideoCredentialsOrCookies() throws {
        let request = try SubtitleFileService.remoteRequest("https://example.org/subtitles/123.srt")
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        XCTAssertNil(request.value(forHTTPHeaderField: "Cookie"))
        XCTAssertNil(request.value(forHTTPHeaderField: "Referer"))
        XCTAssertEqual(request.cachePolicy, .reloadIgnoringLocalCacheData)
        XCTAssertThrowsError(try SubtitleFileService.remoteRequest("https://user:password@example.org/sub.srt"))
        XCTAssertThrowsError(try SubtitleFileService.remoteRequest("file:///private/account.json"))
    }

    @available(iOS, deprecated: 12.0)
    @MainActor func testDirectSourcePickerLayout() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first { $0.isKeyWindow }
        let window = UIWindow(windowScene: scene); window.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
        defer { window.isHidden = true; window.rootViewController = nil; previous?.makeKeyAndVisible() }
        let media = Media(id: "kitsu:9962", type: "series", name: "Danmachi")
        let model = DetailModel(media, service: HarborService(), metadataLoaded: true); model.offers = offers()
        let picker = StreamPickerView(model: model, addons: [], episode: Episode(id: "kitsu:9962:7", season: 1, episode: 7, name: "Sword Princess"), downloading: false, downloadMessage: nil, play: { _ in }, download: nil, refresh: {}, back: {})
        let host = UIHostingController(rootView: NavigationStack { picker }.preferredColorScheme(.dark))
        window.rootViewController = host; window.makeKeyAndVisible()
        try await Task.sleep(for: .milliseconds(500)); host.view.layoutIfNeeded()
        capture(host.view, name: "native-sources-direct-initial")
        func scrollView(_ view: UIView) -> UIScrollView? {
            if let scroll = view as? UIScrollView { return scroll }
            return view.subviews.compactMap { scrollView($0) }.first
        }
        let scroll = try XCTUnwrap(scrollView(host.view))
        scroll.setContentOffset(CGPoint(x: 0, y: min(560, max(0, scroll.contentSize.height - scroll.bounds.height))), animated: false)
        try await Task.sleep(for: .milliseconds(300)); host.view.layoutIfNeeded()
        capture(host.view, name: "native-sources-direct-quality-list")
    }

    @available(iOS, deprecated: 12.0)
    @MainActor func testAddonSubtitleLoadsOnlyChosenFileWithoutDuplicatingOrStoppingVideo() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first { $0.isKeyWindow }
        let window = UIWindow(windowScene: scene); window.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { window.isHidden = true; window.rootViewController = nil; previous?.makeKeyAndVisible(); try? FileManager.default.removeItem(at: directory) }
        let subtitle = directory.appendingPathComponent("addon-spanish.srt")
        try "1\n00:00:00,000 --> 00:00:29,500\nSUBTITULO EXTERNO ELEGIDO\n".write(to: subtitle, atomically: true, encoding: .utf8)
        let video = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "render-8bit", withExtension: "mp4", subdirectory: "Fixtures"))
        let state = PlayerState()
        let controller = MPVController(source: PlaybackSource(url: video.absoluteString, headers: nil, subtitles: nil, via: "test-fixture"), state: state)
        window.rootViewController = controller; window.makeKeyAndVisible(); controller.view.layoutIfNeeded()
        defer { controller.close() }
        let surface = try XCTUnwrap(controller.view as? GLKView)
        func wait(_ condition: () -> Bool) async throws {
            let end = Date().addingTimeInterval(12)
            while Date() < end, state.error == nil {
                surface.display(); if condition() { return }
                try await Task.sleep(for: .milliseconds(50))
            }
            XCTFail("Actual addon subtitle operation failed: \(state.subtitleIssue ?? state.error ?? "timeout")")
            throw HarborError(code: "subtitle-timeout")
        }
        try await wait { state.loaded }
        let chosen = PlaybackSource.Subtitle(url: subtitle.absoluteString, lang: "spa", id: "addon-es", title: "Subtitle addon · Español")
        state.addonSubtitles = [chosen, .init(url: "https://example.org/not-downloaded.srt", lang: "eng", id: "unused", title: "Second addon")]
        state.canSearchAddonSubtitles = true
        XCTAssertFalse(state.tracks.contains { $0.type == "sub" }, "Discovery must not download every subtitle")
        controller.loadAddonSubtitle(chosen)
        try await wait { !state.subtitleChanging && state.primarySubtitle?.external == true }
        XCTAssertEqual(state.primarySubtitle?.language, "spa")
        XCTAssertEqual(state.primarySubtitle?.title, chosen.title)
        controller.run(["seek", "1", "absolute+exact"])
        try await wait { state.primarySubtitleText.contains("SUBTITULO EXTERNO ELEGIDO") }
        controller.loadAddonSubtitle(chosen)
        try await wait { !state.subtitleChanging }
        XCTAssertEqual(state.tracks.filter { $0.type == "sub" }.count, 1, "Choosing the same addon entry must reuse the loaded track")
        XCTAssertNil(state.error); XCTAssertNil(state.subtitleIssue)
        let panel = UIHostingController(rootView: NavigationStack { SubtitleTracksView(state: state) }.preferredColorScheme(.dark))
        controller.addChild(panel); controller.view.addSubview(panel.view); panel.didMove(toParent: controller); panel.view.frame = controller.view.bounds
        defer { panel.willMove(toParent: nil); panel.view.removeFromSuperview(); panel.removeFromParent() }
        try await Task.sleep(for: .milliseconds(400)); panel.view.layoutIfNeeded()
        capture(panel.view, name: "native-subtitles-addon-results-and-loaded-track")
    }

    @MainActor private func capture(_ view: UIView, name: String) {
        let image = UIGraphicsImageRenderer(bounds: view.bounds).image { _ in _ = view.drawHierarchy(in: view.bounds, afterScreenUpdates: true) }
        let attachment = XCTAttachment(image: image); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}

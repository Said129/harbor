import SwiftUI
import UIKit
import XCTest
@testable import Harbor

@MainActor final class MusicSignalDetailsTests: XCTestCase {
    func testOriginalQualityTiersKeepDeclaredSourceSemantics() {
        XCTAssertEqual(MusicTrackQuality(track("flac", rate: 96_000, depth: 24))?.tier, .hiRes)
        XCTAssertEqual(MusicTrackQuality(track("flac", rate: 48_000, depth: 24))?.tier, .lossless)
        XCTAssertEqual(MusicTrackQuality(track("pcm_s24le", rate: 44_100, depth: 16))?.format, "PCM")
        let lossy = MusicTrackQuality(track("mp3", rate: 44_100, depth: 32, bitrate: 320))
        XCTAssertEqual(lossy?.tier, .lossy); XCTAssertNil(lossy?.bitDepth); XCTAssertEqual(lossy?.bitrateKbps, 320)
        XCTAssertEqual(MusicTrackQuality(track("flac", rate: 96_000, depth: 24, lossless: false))?.tier, .lossy)
        XCTAssertEqual(MusicTrackQuality(track("wav", rate: 44_100, depth: 16))?.tier, .unverified)
        XCTAssertEqual(MusicTrackQuality(track(nil, lossless: true))?.tier, .lossless)
        XCTAssertNil(MusicTrackQuality(track(nil)))
        XCTAssertNil(MusicTrackQuality(track("unknown-codec")))
        XCTAssertNil(MusicTrackQuality(track("flac", rate: 4_000_000, depth: 24))?.sampleRateHz)
        XCTAssertEqual(MusicTrackQuality(track(nil, connector: "local", source: "file:///owned/a%20b.FLAC"))?.format, "FLAC")
        XCTAssertEqual(MusicTrackQuality(track(nil, connector: "local", source: "C:\\Owned\\song.wv"))?.format, "WavPack")
        XCTAssertNil(MusicTrackQuality(track(nil, connector: "local", source: "relative/a.flac")))
        XCTAssertNil(MusicTrackQuality(track(nil, connector: "direct", source: "/owned/a.flac")))
        XCTAssertEqual(MusicTrackQuality.sampleRateLabel(44_100), "44.1 kHz")
        XCTAssertEqual(MusicTrackQuality.sampleRateLabel(48_000), "48 kHz")
        XCTAssertEqual(MusicTrackQuality.sampleRateLabel(352_800), "352.8 kHz")
        XCTAssertEqual(MusicTrackQuality.helpKey(.hiRes), "music.quality.hiResHelp")
        XCTAssertEqual(MusicTrackQuality.helpKey(.unverified), "music.quality.unverifiedHelp")
    }

    func testSignalDetailsRenderDeclaredSourceAndOutputStagesOnPhoneTabletAndArabic() async throws {
        let engine = SharedMusicControlledEngine(), resolver = SharedMusicResolver()
        let player = MusicPlayback(engine: engine, systemIntegration: false, recordPlayed: { _, _ in })
        let oldLanguage = UserDefaults.standard.string(forKey: "uiLanguage")
        defer {
            player.stop()
            if let oldLanguage { UserDefaults.standard.set(oldLanguage, forKey: "uiLanguage") }
            else { UserDefaults.standard.removeObject(forKey: "uiLanguage") }
        }
        var song = MusicTrack(id: "signal", connectorId: "direct", sourceId: "signal", playbackUrl: "https://owned.invalid/signal.flac",
                              title: "Owned signal", artist: "Owned Artist", album: nil, artwork: "", durationSeconds: 8, durationLabel: "0:08")
        song.quality = MusicAudioQuality(codec: "flac", lossless: true, sampleRateHz: 96_000, bitDepth: 24, bitrateKbps: 2_400)
        player.play(song, queue: [song], using: resolver)
        try await wait { player.loaded }
        XCTAssertEqual(MusicTrackQuality(song)?.tier, .hiRes)
        for (name, size, language, direction) in [
            ("phone", CGSize(width: 390, height: 844), "es", LayoutDirection.leftToRight),
            ("tablet", CGSize(width: 1024, height: 1366), "es", LayoutDirection.leftToRight),
            ("arabic-phone", CGSize(width: 390, height: 844), "ar", LayoutDirection.rightToLeft)
        ] {
            UserDefaults.standard.set(language, forKey: "uiLanguage")
            for key in ["music.quality.hiRes", "music.quality.hiResHelp", "music.quality.source", "music.quality.output", "music.quality.selectedOutput"] {
                XCTAssertNotEqual(DesktopInterfaceText.value(key, language: language), key)
            }
            try await capture(NavigationStack { ScrollView { MusicSignalDetailsView(player: player).padding(20) } }
                .environment(\.layoutDirection, direction).environment(\.locale, Locale(identifier: language)),
                              name: "music-signal-details-" + name, size: size)
        }
    }

    private func track(_ codec: String?, rate: Double? = nil, depth: Double? = nil, bitrate: Double? = nil, lossless: Bool? = nil,
                       connector: String = "direct", source: String? = nil) -> MusicTrack {
        var value = MusicTrack(id: "quality", connectorId: connector, sourceId: source, playbackUrl: nil, title: "Owned", artist: "Owned Artist",
                               album: nil, artwork: "", durationSeconds: 1, durationLabel: "0:01")
        value.quality = MusicAudioQuality(codec: codec, lossless: lossless, sampleRateHz: rate, bitDepth: depth, bitrateKbps: bitrate)
        return value
    }
    private func wait(_ predicate: @MainActor () -> Bool) async throws {
        for _ in 0..<250 { if predicate() { return }; try await Task.sleep(for: .milliseconds(20)) }
        XCTFail("Owned signal player did not settle"); throw HarborError(code: "owned-signal-timeout")
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
        let attachment = XCTAttachment(image: image); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}

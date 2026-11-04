import SwiftUI
import UIKit
import XCTest
@testable import Harbor

@MainActor private final class ArtworkPaletteObservation {
    var value: MusicArtworkPalette?
    var updates = 0
}
@MainActor private struct ArtworkPaletteProbe: View {
    @Environment(\.musicArtworkPalette) private var palette
    let observation: ArtworkPaletteObservation
    var body: some View {
        Color.clear.frame(width: 1, height: 1).allowsHitTesting(false)
            .onChange(of: palette, initial: true) { _, value in observation.value = value; observation.updates += 1 }
    }
}

@MainActor final class MusicArtworkTests: XCTestCase {
    func testOriginalArtworkVectorsAndActualImageDecodingRetainTransparentAndStableTieSemantics() async throws {
        struct Fixture: Decodable {
            struct Case: Decodable { let name: String; let pixels: [UInt8]; let expected: MusicArtworkPalette }
            let reference: String
            let cases: [Case]
        }
        let fixture = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: resource("music-artwork-reference", "json")))
        XCTAssertEqual(fixture.reference, "0834340cec5531650bfe78cd628628702e636987")
        XCTAssertEqual(fixture.cases.count, 19)
        let analyser = MusicArtworkColours()
        for item in fixture.cases {
            let actual = try await analyser.analyse(item.pixels)
            XCTAssertEqual(actual, item.expected, item.name)
        }
        let image = try Data(contentsOf: resource("owned-music-artwork", "png"))
        let actual = try await analyser.palette(image)
        XCTAssertEqual(actual?.dominant?.rgb, [220, 32, 32], "Image decoding must preserve the top-first stable tie")
        XCTAssertFalse(actual?.dominant?.darkInk ?? true)
        let cached = try await analyser.palette(image); XCTAssertEqual(cached, actual)
        let oversized = try await analyser.palette(Data(repeating: 0, count: 4 * 1024 * 1024 + 1)); XCTAssertNil(oversized)
        do { _ = try await analyser.analyse([0]); XCTFail("Incomplete RGBA must be rejected") } catch { }
        do { _ = try await analyser.palette(Data([0, 1, 2])); XCTFail("Invalid encoded images must be rejected") } catch { }
        let cancelled = Task { try await analyser.palette(image) }
        cancelled.cancel()
        do { _ = try await cancelled.value; XCTFail("Cancelled decoration must not publish cached colours") } catch is CancellationError { }
    }

    func testOwnedArtworkColoursRenderResponsivePlayerAndRespectDisableAndProfileRetirement() async throws {
        let scope = SharedMusicScope(), owner = scope.scope.owner
        var record = try await MusicFileService.shared.importFile(resource("owned-meter-tones", "wav"), owner: owner).record
        let image = try XCTUnwrap(UIImage(contentsOfFile: resource("owned-music-artwork", "png").path))
        let jpeg = try XCTUnwrap(image.jpegData(compressionQuality: 0.95))
        record.cover = String(record.filename.prefix(64)) + ".jpg"
        try jpeg.write(to: MusicFileService.root(owner: owner).appendingPathComponent(try XCTUnwrap(record.cover)), options: .atomic)
        let expected = try await MusicArtworkColours.shared.palette(jpeg)
        _ = try XCTUnwrap(expected?.dominant)
        let audio = MusicAudioPreferences(owner: owner)
        XCTAssertTrue(audio.artworkColors)
        audio.showLevels = false; audio.dockVisualizer = false
        let server = SubsonicMusicService(scope: scope.scope, currentScope: { scope.scope }, persistence: SharedMusicPairingDisk())
        let session = MusicPlaybackSession(server: server, playlists: MusicPlaylistStore(owner: owner, persistence: SharedMusicDisk()),
                                          localRecords: { [record] }, audio: audio, currentScope: { scope.scope })
        let player = MusicPlayback(engine: SharedMusicControlledEngine(), systemIntegration: false, recordPlayed: { _, _ in })
        let theme = ThemePreferences.shared, oldPreset = theme.preset, oldCustom = theme.custom, oldColors = theme.customColors
        let oldLanguage = UserDefaults.standard.string(forKey: "uiLanguage")
        defer {
            player.stop(); server.dispose(); theme.preset = oldPreset; theme.customColors = oldColors; theme.custom = oldCustom
            for prefix in ["music-art-colors-", "music-levels-", "music-spectrum-"] {
                UserDefaults.standard.removeObject(forKey: prefix + EBookShelf.hash(owner))
            }
            if let oldLanguage { UserDefaults.standard.set(oldLanguage, forKey: "uiLanguage") }
            else { UserDefaults.standard.removeObject(forKey: "uiLanguage") }
        }
        do {
            player.play(record.local.track, queue: [record.local.track], using: session)
            try await wait { player.loaded }
            theme.custom = false
            for (name, size, light, language, direction) in [
                ("phone-dark", CGSize(width: 390, height: 844), false, "es", LayoutDirection.leftToRight),
                ("tablet-light", CGSize(width: 1024, height: 1366), true, "es", LayoutDirection.leftToRight),
                ("phone-arabic", CGSize(width: 390, height: 844), false, "ar", LayoutDirection.rightToLeft)
            ] {
                theme.preset = "cool-grey"; theme.custom = light
                if light {
                    theme.customColors = ["canvas": [0.96, 0.95, 0.92, 1], "surface": [0.92, 0.91, 0.88, 1],
                                          "ink": [0.08, 0.08, 0.09, 1], "ink-muted": [0.3, 0.3, 0.32, 1]]
                }
                UserDefaults.standard.set(language, forKey: "uiLanguage")
                try await capture(player, name: "music-artwork-" + name, size: size, direction: direction, expected: expected)
            }
            try await validateChanges(player, audio: audio, scope: scope, expected: expected)
            XCTAssertTrue(MusicAudioPreferences(owner: owner + "-other").artworkColors)
            for code in InterfaceLanguage.all.map(\.code) {
                for key in ["music.now.colors", "music.quality.levels", "music.now.visualizer"] {
                    XCTAssertNotEqual(DesktopInterfaceText.value(key, language: code), key)
                }
            }
            player.stop(); try await MusicFileService.shared.remove(record, owner: owner)
        } catch {
            player.stop(); try? await MusicFileService.shared.remove(record, owner: owner); throw error
        }
    }
    private func resource(_ name: String, _ ext: String) throws -> URL {
        try XCTUnwrap(Bundle(for: Self.self).url(forResource: name, withExtension: ext, subdirectory: "Fixtures"))
    }
    private func wait(_ condition: @MainActor () -> Bool) async throws {
        for _ in 0..<300 { if condition() { return }; try await Task.sleep(for: .milliseconds(20)) }
        XCTFail("Owned artwork pipeline did not settle"); throw HarborError(code: "owned-artwork-timeout")
    }
    private func capture(_ player: MusicPlayback, name: String, size: CGSize, direction: LayoutDirection, expected: MusicArtworkPalette?) async throws {
        let observation = ArtworkPaletteObservation()
        try await mounted(
            NavigationStack { MusicPlayerView(player: player) }
                .overlay(alignment: .bottom) { MusicMiniPlayer(player: player) }
                .background(ArtworkPaletteProbe(observation: observation))
                .modifier(MusicArtworkTheme(player: player))
                .environment(\.layoutDirection, direction),
            size: size
        ) { host in
            try await self.wait { observation.value == expected }
            try await Task.sleep(for: .milliseconds(450))
            let image = UIGraphicsImageRenderer(size: size).image { _ in
                host.view.drawHierarchy(in: CGRect(origin: .zero, size: size), afterScreenUpdates: true)
            }
            let attachment = XCTAttachment(image: image); attachment.name = name; attachment.lifetime = .keepAlways; self.add(attachment)
        }
    }
    private func validateChanges(_ player: MusicPlayback, audio: MusicAudioPreferences, scope: SharedMusicScope, expected: MusicArtworkPalette?) async throws {
        let observation = ArtworkPaletteObservation()
        try await mounted(ArtworkPaletteProbe(observation: observation).modifier(MusicArtworkTheme(player: player)), size: CGSize(width: 390, height: 844)) { _ in
            try await self.wait { observation.value == expected }
            audio.artworkColors = false
            try await self.wait { observation.value == nil }
            XCTAssertFalse(MusicAudioPreferences(owner: audio.owner).artworkColors)
            audio.artworkColors = true
            try await self.wait { observation.value == expected }
            // Retiring the profile invalidates both the task and its already
            // published environment value; reusing the same cover is not enough.
            scope.scope = .init(owner: scope.scope.owner + "-retired", activation: UUID())
            audio.artworkColors = false
            try await self.wait { observation.value == nil }
            audio.artworkColors = true
            try await Task.sleep(for: .milliseconds(150))
            XCTAssertNil(observation.value)
            player.stop()
        }
    }
    private func mounted<V: View>(_ view: V, size: CGSize, action: (UIHostingController<V>) async throws -> Void) async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first { $0.isKeyWindow }, window = UIWindow(windowScene: scene)
        window.frame = CGRect(origin: .zero, size: size)
        let host = UIHostingController(rootView: view)
        window.rootViewController = host; window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil; previous?.makeKeyAndVisible() }
        host.view.layoutIfNeeded()
        try await action(host)
    }
}

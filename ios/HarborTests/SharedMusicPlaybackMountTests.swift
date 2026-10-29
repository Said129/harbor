import Observation
import SwiftUI
import UIKit
import XCTest
@testable import Harbor

@MainActor @Observable private final class SharedMusicMountLayout { var regular = false }
@MainActor private struct SharedMusicMountedPlayer: View {
    let player: MusicPlayback
    @Bindable var layout: SharedMusicMountLayout
    var body: some View {
        NavigationStack { MusicPlayerView(player: player) }
            .environment(\.horizontalSizeClass, layout.regular ? .regular : .compact)
            .environment(\.locale, Locale(identifier: "en"))
            .environment(\.layoutDirection, .leftToRight).preferredColorScheme(.dark)
            .foregroundStyle(HarborTheme.ink).transaction { $0.disablesAnimations = true }
    }
}

@MainActor final class SharedMusicPlaybackMountTests: XCTestCase {
    func testActualSharedPlayerMetadataTransportAndQueueMountInBothNativeSizes() async throws {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let artwork = UIGraphicsImageRenderer(size: CGSize(width: 360, height: 360), format: format).image { context in
            UIColor(red: 0.12, green: 0.2, blue: 0.36, alpha: 1).setFill(); context.fill(CGRect(x: 0, y: 0, width: 360, height: 360))
            UIColor(red: 0.97, green: 0.62, blue: 0.28, alpha: 1).setFill(); context.cgContext.fillEllipse(in: CGRect(x: 60, y: 60, width: 240, height: 240))
            ("OWNED\nMUSIC" as NSString).draw(in: CGRect(x: 92, y: 140, width: 200, height: 110), withAttributes: [.font: UIFont.boldSystemFont(ofSize: 32), .foregroundColor: UIColor.black])
        }
        let publisher = try SharedMusicPublisher(audio: Data(), artwork: try XCTUnwrap(artwork.pngData()))
        let base = try await publisher.start(), engine = SharedMusicControlledEngine(), resolver = SharedMusicResolver()
        let player = MusicPlayback(engine: engine, systemIntegration: false, recordPlayed: { _, _ in })
        let oldShuffle = player.shuffle, oldRepeat = player.repeatMode
        let oldLanguage = UserDefaults.standard.object(forKey: "uiLanguage")
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow), window = UIWindow(windowScene: scene)
        defer {
            player.stop(); player.shuffle = oldShuffle; player.repeatMode = oldRepeat; publisher.stop()
            window.isHidden = true; window.rootViewController = nil; previous?.makeKey()
            if let oldLanguage { UserDefaults.standard.set(oldLanguage, forKey: "uiLanguage") } else { UserDefaults.standard.removeObject(forKey: "uiLanguage") }
        }
        UserDefaults.standard.set("en", forKey: "uiLanguage"); player.shuffle = false; player.repeatMode = .off
        let tracks = (1...14).map { SharedMusicPlaybackTests.track("recording-\($0)", source: "recording-\($0)", artwork: base.appendingPathComponent("cover.png").absoluteString) }
        player.play(tracks[0], queue: tracks, using: resolver, origin: .init(kind: "playlist", id: "owned-mixed-layout", name: "Owned mixed playlist"))
        for _ in 0..<200 { if player.loaded { break }; try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertTrue(player.loaded); XCTAssertNil(player.current)
        let layout = SharedMusicMountLayout(), host = UIHostingController(rootView: SharedMusicMountedPlayer(player: player, layout: layout))
        window.rootViewController = host; window.makeKeyAndVisible()
        try await Task.sleep(for: .milliseconds(400))
        for (label, size) in [("compact", CGSize(width: 390, height: 844)), ("regular", CGSize(width: 834, height: 1194))] {
            layout.regular = size.width > 600
            UIView.performWithoutAnimation { window.frame = CGRect(origin: .zero, size: size); host.view.frame = window.bounds; window.layoutIfNeeded() }
            try await Task.sleep(for: .milliseconds(400)); window.layoutIfNeeded()
            let scroll = try XCTUnwrap(scrolls(window).first { $0.bounds.width > 250 && $0.contentSize.height > $0.bounds.height + 100 })
            try await decoded(window)
            try await settle(scroll, in: window, bottom: false); capture(window, "music-shared-top-" + label)
            try await settle(scroll, in: window, bottom: true); capture(window, "music-shared-queue-" + label)
            XCTAssertEqual(host.view.bounds.width, size.width, accuracy: 1)
            XCTAssertEqual(player.items.count, 14); XCTAssertEqual(player.upcomingItems.count, 13)
        }
        window.isHidden = true; try await Task.sleep(for: .milliseconds(400))
    }
    private func scrolls(_ view: UIView) -> [UIScrollView] { ((view as? UIScrollView).map { [$0] } ?? []) + view.subviews.flatMap(scrolls) }
    private func settle(_ scroll: UIScrollView, in window: UIWindow, bottom: Bool) async throws {
        var stable = 0
        for _ in 0..<120 {
            window.layoutIfNeeded()
            let target = bottom ? max(-scroll.adjustedContentInset.top, scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom) : -scroll.adjustedContentInset.top
            if abs(scroll.contentOffset.y - target) < 0.5 { stable += 1 } else { stable = 0 }
            scroll.setContentOffset(CGPoint(x: 0, y: target), animated: false)
            if stable >= 6 { window.layoutIfNeeded(); return }
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTFail("The resized player's real scroll offset must settle before photographing its top or queue")
        throw HarborError(code: "owned-shared-player-offset")
    }
    private func decoded(_ window: UIWindow) async throws {
        func count(_ view: UIView) -> Int {
            let own = (view as? UIImageView).map { $0.image?.cgImage != nil && $0.bounds.width >= 40 && $0.bounds.height >= 40 ? 1 : 0 } ?? 0
            return own + view.subviews.reduce(0) { $0 + count($1) }
        }
        for _ in 0..<160 {
            window.layoutIfNeeded()
            if count(window) > 0 { try await Task.sleep(for: .milliseconds(300)); window.layoutIfNeeded(); return }
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTFail("Actual owned artwork must decode in the production player before capture"); throw HarborError(code: "owned-shared-player-artwork")
    }
    private func capture(_ window: UIWindow, _ name: String) {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let image = UIGraphicsImageRenderer(bounds: window.bounds, format: format).image { _ in
            XCTAssertTrue(window.drawHierarchy(in: window.bounds, afterScreenUpdates: true))
        }
        let attachment = XCTAttachment(image: image); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}

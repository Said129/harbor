import Observation
import SwiftUI
import UIKit
import XCTest
@testable import Harbor

@MainActor @Observable private final class CoverMountLayout { var regular = false }
@MainActor private struct MountedCoverPlaylist: View {
    let library: MusicLibrary
    let store: MusicPlaylistStore
    let playlist: String
    @Bindable var layout: CoverMountLayout
    var body: some View {
        NavigationStack { MusicPlaylistView(id: playlist, library: library, store: store) }
            .environment(\.horizontalSizeClass, layout.regular ? .regular : .compact)
            .environment(\.locale, Locale(identifier: "en")).environment(\.layoutDirection, .leftToRight)
            .foregroundStyle(HarborTheme.ink).preferredColorScheme(.dark).transaction { $0.disablesAnimations = true }
    }
}

@MainActor final class MusicPlaylistCoverMountTests: XCTestCase {
    func testProductionPlaylistShowsItsActualCustomCoverThenRestoresTheMosaicInBothSizes() async throws {
        let owner = "owned-custom-cover-interface-" + UUID().uuidString
        let ownedLibrary = MusicLibrary(owner: owner), store = MusicPlaylistStore(owner: owner, persistence: SharedMusicDisk())
        let list = try XCTUnwrap(store.create("Owned custom cover")), layout = CoverMountLayout()
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow), window = UIWindow(windowScene: scene)
        let oldLanguage = UserDefaults.standard.object(forKey: "uiLanguage")
        var publishers: [SharedMusicPublisher] = []
        defer {
            try? MusicPlaylistCoverStore.shared.clear(owner: owner, playlist: list.id, allowed: { true })
            window.isHidden = true; window.rootViewController = nil; previous?.makeKey(); publishers.forEach { $0.stop() }
            if let oldLanguage { UserDefaults.standard.set(oldLanguage, forKey: "uiLanguage") } else { UserDefaults.standard.removeObject(forKey: "uiLanguage") }
        }
        UserDefaults.standard.set("en", forKey: "uiLanguage")
        var tracks: [Harbor.MusicTrack] = []
        for (index, color) in [UIColor.systemOrange, .systemTeal, .systemPurple].enumerated() {
            let publisher = try SharedMusicPublisher(audio: Data(), artwork: MusicPlaylistCoverTests.png(size: CGSize(width: 120, height: 120), color: color))
            publishers.append(publisher); let base = try await publisher.start()
            tracks.append(SharedMusicPlaybackTests.track("owned-cover-track-\(index)", source: String(index), artwork: base.appendingPathComponent("cover.png").absoluteString))
        }
        XCTAssertNotNil(store.add(tracks, to: list.id))
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let custom = UIGraphicsImageRenderer(size: CGSize(width: 360, height: 360), format: format).image { context in
            context.cgContext.setFillColor(UIColor.systemYellow.cgColor); context.cgContext.fill(CGRect(x: 0, y: 0, width: 360, height: 360))
            ("OWNED\nCUSTOM" as NSString).draw(in: CGRect(x: 48, y: 140, width: 280, height: 130), withAttributes: [.font: UIFont.boldSystemFont(ofSize: 42), .foregroundColor: UIColor.black])
        }.pngData()!
        let host = UIHostingController(rootView: MountedCoverPlaylist(library: ownedLibrary, store: store, playlist: list.id, layout: layout))
        window.rootViewController = host; window.makeKeyAndVisible(); try await Task.sleep(for: .milliseconds(400))
        for (label, size) in [("compact", CGSize(width: 390, height: 844)), ("regular", CGSize(width: 834, height: 1194))] {
            layout.regular = size.width > 600
            UIView.performWithoutAnimation { window.frame = CGRect(origin: .zero, size: size); host.view.frame = window.bounds; window.layoutIfNeeded() }
            try await MusicPlaylistCoverStore.shared.save(custom, owner: owner, playlist: list.id, allowed: { true })
            try await painted(window, custom: true); capture(window, "music-custom-cover-" + label)
            try MusicPlaylistCoverStore.shared.clear(owner: owner, playlist: list.id, allowed: { true })
            try await painted(window, custom: false); capture(window, "music-cleared-cover-" + label)
        }
        window.isHidden = true; try await Task.sleep(for: .milliseconds(400))
    }
    private func painted(_ window: UIWindow, custom: Bool) async throws {
        func count(_ view: UIView) -> Int {
            let own = (view as? UIImageView).map { imageView -> Int in
                guard let image = imageView.image?.cgImage else { return 0 }
                if custom { return imageView.bounds.width >= 100 && imageView.bounds.height >= 100 && image.width == 360 && image.height == 360 ? 1 : 0 }
                return imageView.bounds.width >= 50 && imageView.bounds.height >= 40 && image.width == 120 && image.height == 120 ? 1 : 0
            } ?? 0
            return own + view.subviews.reduce(0) { $0 + count($1) }
        }
        for _ in 0..<160 {
            window.layoutIfNeeded()
            if count(window) >= (custom ? 1 : 3) { try await Task.sleep(for: .milliseconds(500)); window.layoutIfNeeded(); return }
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTFail("Paint the actual custom bitmap or all three restored mosaic tiles before capture"); throw HarborError(code: "owned-cover-paint")
    }
    private func capture(_ window: UIWindow, _ name: String) {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let image = UIGraphicsImageRenderer(bounds: window.bounds, format: format).image { _ in XCTAssertTrue(window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)) }
        let attachment = XCTAttachment(image: image); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}

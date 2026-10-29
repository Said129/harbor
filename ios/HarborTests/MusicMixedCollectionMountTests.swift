import Observation
import SwiftUI
import UIKit
import XCTest
@testable import Harbor

@MainActor @Observable private final class MixedCollectionMountLayout {
    var regular = false
    var recent = false
    var adding = false
}
@MainActor private struct MixedCollectionMountedRoot: View {
    let library: MusicLibrary
    let store: MusicPlaylistStore
    let playlistID: String
    @Bindable var layout: MixedCollectionMountLayout
    var body: some View {
        NavigationStack {
            Group {
                if layout.recent { MusicPersonalCollectionView(collection: .recent, library: library, playlists: store) }
                else { MusicPlaylistView(id: playlistID, library: library, store: store) }
            }
        }.sheet(isPresented: $layout.adding) { MusicPlaylistAddView(id: playlistID, library: library, store: store) }
            .environment(\.horizontalSizeClass, layout.regular ? .regular : .compact)
            .environment(\.locale, Locale(identifier: "en")).environment(\.layoutDirection, .leftToRight)
            .preferredColorScheme(.dark).foregroundStyle(HarborTheme.ink).transaction { $0.disablesAnimations = true }
    }
}

@MainActor final class MusicMixedCollectionMountTests: XCTestCase {
    func testMixedPlaylistCompactRowsRecentAndAddTrayMountWithDecodedRemoteMosaicsInBothSizes() async throws {
        let owner = "owned-mixed-interface-" + UUID().uuidString
        let library = MusicLibrary(owner: owner), store = MusicPlaylistStore(owner: owner, persistence: SharedMusicDisk())
        let collections = MusicCollections.shared, layout = MixedCollectionMountLayout()
        let oldLanguage = UserDefaults.standard.object(forKey: "uiLanguage"), oldLayout = UserDefaults.standard.object(forKey: "harbor.music.playlistView")
        var publishers: [SharedMusicPublisher] = []
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow), window = UIWindow(windowScene: scene)
        defer {
            window.isHidden = true; window.rootViewController = nil; previous?.makeKey(); publishers.forEach { $0.stop() }
            if let oldLanguage { UserDefaults.standard.set(oldLanguage, forKey: "uiLanguage") } else { UserDefaults.standard.removeObject(forKey: "uiLanguage") }
            if let oldLayout { UserDefaults.standard.set(oldLayout, forKey: "harbor.music.playlistView") } else { UserDefaults.standard.removeObject(forKey: "harbor.music.playlistView") }
            try? KeychainStore().remove("music-library-" + EBookShelf.hash(owner)); try? KeychainStore().remove("music-collections-" + EBookShelf.hash(owner))
        }
        UserDefaults.standard.set("en", forKey: "uiLanguage"); UserDefaults.standard.set("list", forKey: "harbor.music.playlistView")
        do {
            let wav = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "owned-tone", withExtension: "wav", subdirectory: "Fixtures"))
            library.importFiles([wav])
            for _ in 0..<500 { if !library.importing { break }; try await Task.sleep(for: .milliseconds(20)) }
            XCTAssertNil(library.error); XCTAssertEqual(library.records.count, 1)
            let local = try XCTUnwrap(library.records.first), list = try XCTUnwrap(store.create("Owned mixed playlist"))
            var remote: [MusicTrack] = []
            for (offset, color) in [UIColor.systemOrange, .systemTeal, .systemPurple].enumerated() {
                let format = UIGraphicsImageRendererFormat(); format.scale = 1
                let art = UIGraphicsImageRenderer(size: CGSize(width: 300, height: 300), format: format).image { context in
                    context.cgContext.setFillColor(color.cgColor); context.cgContext.fill(CGRect(x: 0, y: 0, width: 300, height: 300))
                    ("OWNED\n\(offset + 1)" as NSString).draw(in: CGRect(x: 65, y: 100, width: 200, height: 100), withAttributes: [.font: UIFont.boldSystemFont(ofSize: 34), .foregroundColor: UIColor.black])
                }
                let publisher = try SharedMusicPublisher(audio: Data(), artwork: try XCTUnwrap(art.pngData())); publishers.append(publisher)
                let base = try await publisher.start()
                remote.append(SharedMusicPlaybackTests.track("subsonic:owned-\(offset + 1)", source: "owned-\(offset + 1)", connector: "subsonic", artwork: base.appendingPathComponent("cover.png").absoluteString))
            }
            XCTAssertTrue(store.remember(remote))
            XCTAssertNotNil(store.add([remote[0], local.local.track, remote[1], remote[2]], to: list.id))
            collections.prepare(owner: owner)
            for track in [local.local.track] + remote { XCTAssertTrue(collections.recordPlayed(track.id, owner: owner)) }
            for track in remote { XCTAssertTrue(collections.setLiked(track.id, liked: true, owner: owner)) }
            let host = UIHostingController(rootView: MixedCollectionMountedRoot(library: library, store: store, playlistID: list.id, layout: layout))
            window.rootViewController = host; window.makeKeyAndVisible(); try await Task.sleep(for: .milliseconds(400))
            for (label, size) in [("compact", CGSize(width: 390, height: 844)), ("regular", CGSize(width: 834, height: 1194))] {
                layout.regular = size.width > 600; layout.recent = false; layout.adding = false
                UserDefaults.standard.set("list", forKey: "harbor.music.playlistView")
                UIView.performWithoutAnimation { window.frame = CGRect(origin: .zero, size: size); host.view.frame = window.bounds; window.layoutIfNeeded() }
                try await decoded(window, minimum: 3, minimumWidth: 50); capture(window, "music-mixed-playlist-" + label)
                UserDefaults.standard.set("compact", forKey: "harbor.music.playlistView")
                try await decoded(window, minimum: 3, minimumWidth: 50); capture(window, "music-mixed-compact-" + label)
                layout.recent = true
                try await decoded(window, minimum: 3, minimumWidth: 50, recent: true); capture(window, "music-mixed-recent-" + label)
                // Leave only the first source and actual local file in the list,
                // so the production tray must offer the two other saved sources.
                store.remove(remote[1].id, from: list.id); store.remove(remote[2].id, from: list.id)
                layout.adding = true
                for _ in 0..<100 { if host.presentedViewController?.view.window != nil { break }; try await Task.sleep(for: .milliseconds(20)) }
                let sheet = try XCTUnwrap(host.presentedViewController?.view)
                try await decoded(sheet, minimum: 2, minimumWidth: 30); capture(window, "music-mixed-add-" + label)
                layout.adding = false; try await Task.sleep(for: .milliseconds(400))
                XCTAssertNotNil(store.add([remote[1], remote[2]], to: list.id))
                XCTAssertEqual(host.view.bounds.width, size.width, accuracy: 1)
            }
            XCTAssertTrue(publishers.allSatisfy { $0.requests.contains { $0.hasPrefix("GET /cover.png") } })
            window.isHidden = true; try await Task.sleep(for: .milliseconds(400))
            for record in library.records { await library.remove(record) }
        } catch { for record in library.records { await library.remove(record) }; throw error }
    }
    private func decoded(_ window: UIView, minimum: Int, minimumWidth: CGFloat, recent: Bool = false) async throws {
        func images(_ view: UIView) -> [UIImageView] {
            guard !view.isHidden, view.alpha > 0.01 else { return [] }
            let own = (view as? UIImageView).map { image -> [UIImageView] in
                guard image.image?.cgImage?.width == 300, image.image?.cgImage?.height == 300,
                      image.convert(image.bounds, to: window).intersects(window.bounds) else { return [] }
                return [image]
            } ?? []
            return own + view.subviews.flatMap(images)
        }
        func ready() -> Bool {
            let painted = images(window)
            if recent {
                // The old playlist can retain decoded images during route replacement.
                // Require the actual 120-point recent mosaic AND its compact track rows.
                return painted.filter { abs($0.bounds.height - 60) < 1 && $0.bounds.width >= 59 }.count >= 3 &&
                    painted.filter { abs($0.bounds.width - 32) < 1 && abs($0.bounds.height - 32) < 1 }.count >= 3
            }
            return painted.filter { $0.bounds.width >= minimumWidth && $0.bounds.height >= 30 }.count >= minimum
        }
        for _ in 0..<160 {
            window.layoutIfNeeded()
            if ready() {
                try await Task.sleep(for: .milliseconds(500)); window.layoutIfNeeded()
                if ready() { return }
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTFail("Decode owned source artwork in the production mixed collection before capture"); throw HarborError(code: "owned-mixed-artwork")
    }
    private func capture(_ window: UIWindow, _ name: String) {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let result = UIGraphicsImageRenderer(bounds: window.bounds, format: format).image { _ in
            XCTAssertTrue(window.drawHierarchy(in: window.bounds, afterScreenUpdates: true))
        }
        let attachment = XCTAttachment(image: result); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}

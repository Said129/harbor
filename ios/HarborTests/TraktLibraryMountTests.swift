import SwiftUI
import UIKit
import XCTest
@testable import Harbor

@MainActor final class TraktLibraryMountTests: XCTestCase {
    func testActualLibraryHistoryAndTransferControlsMountDecodedArtworkInBothNativeSizes() async throws {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let cover = UIGraphicsImageRenderer(size: .init(width: 400, height: 600), format: format).pngData { context in
            UIColor.systemIndigo.setFill(); context.fill(.init(x: 0, y: 0, width: 400, height: 600))
            ("OWNED\nTRAKT\nLIBRARY" as NSString).draw(in: .init(x: 32, y: 150, width: 336, height: 300), withAttributes: [.font: UIFont.boldSystemFont(ofSize: 44), .foregroundColor: UIColor.white])
        }
        let publisher = try OwnedPosterImagePublisher(poster: cover, wide: cover), base = try await publisher.start(); defer { publisher.stop() }
        let account = TraktAccountStore(owner: "owned-trakt-library-mount", persistence: OwnedTraktPersistence()); try account.load()
        try account.set(.init(accessToken: "owned-access", refreshToken: "owned-refresh", createdAt: 1_700_000_000, expiresIn: 7_776_000))
        let store = TraktLibraryStore(owner: account.owner, disk: OwnedTraktLibraryDisk()); store.bind(account.session?.trackingID)
        let movie = TraktLibraryItem(type: .movie, title: "Owned Trakt Movie", year: 2024, ids: .init(.object(["imdb": .string("tt1234567")])), contextDate: "2026-10-27T00:00:00Z")
        let show = TraktLibraryItem(type: .show, title: "Owned Trakt Show", year: 2022, ids: .init(.object(["imdb": .string("tt1234568")])), contextDate: "2026-10-27T00:00:00Z")
        try await store.commit(.init(watchlist: [movie, show], history: [show, movie]), fingerprint: XCTUnwrap(store.fingerprint), revision: store.revision)
        let noNetwork = TraktClient(transport: { _ in throw HarborError(code: "unexpected-trakt-network") })
        let model = TraktLibraryModel(account: account, store: store, client: noNetwork, active: { true }), app = AppModel()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("owned-trakt-transfer-mount-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true); defer { try? FileManager.default.removeItem(at: root) }
        let service = OwnedRetirementOfflineService(), local = LibraryModel(service: service, writeQueue: .init(service: service, directory: root), cache: .init(directory: root))
        await local.setSession(nil, personalOwner: account.owner, guestOwner: account.owner, synchronize: false)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow), window = UIWindow(windowScene: scene)
        defer { window.isHidden = true; window.rootViewController = nil; previous?.makeKey() }
        for (label, size) in [("compact", CGSize(width: 390, height: 844)), ("regular", CGSize(width: 834, height: 1194))] {
            window.frame = CGRect(origin: .zero, size: size)
            for history in [false, true] {
                let content = ScrollViewReader { proxy in
                    ScrollView { TraktLibraryContent(app: app, model: model, metadata: { media in var value = media; value.poster = base + "/poster.png"; return value }).padding(20) }
                        .task { if history { try? await Task.sleep(for: .milliseconds(900)); proxy.scrollTo("trakt-history", anchor: .top) } }
                }.background(HarborTheme.background).foregroundStyle(HarborTheme.ink).preferredColorScheme(.dark)
                window.rootViewController = UIHostingController(rootView: content); window.makeKeyAndVisible()
                try await settle(window); try await waitForDecodedCover(window)
                if history { try await Task.sleep(for: .milliseconds(700)); window.layoutIfNeeded() }
                capture(window, "trakt-library-native-" + (history ? "history-" : "watchlist-") + label)
            }
            window.rootViewController = UIHostingController(rootView: ScrollView { TraktWatchlistTransferView(model: model, library: local).padding(20) }.background(HarborTheme.background).foregroundStyle(HarborTheme.ink).preferredColorScheme(.dark))
            try await settle(window); capture(window, "trakt-library-native-transfer-" + label)
        }
        XCTAssertEqual(model.watchlist.count, 2); XCTAssertEqual(model.history.count, 2); XCTAssertNil(model.error)
    }
    private func settle(_ window: UIWindow) async throws {
        window.layoutIfNeeded(); try await Task.sleep(for: .milliseconds(700)); window.layoutIfNeeded()
        XCTAssertGreaterThan(window.rootViewController?.view.bounds.width ?? 0, 300)
    }
    private func waitForDecodedCover(_ window: UIWindow) async throws {
        func contains(_ view: UIView) -> Bool {
            if let image = view as? UIImageView, image.image?.cgImage != nil, image.bounds.width > 80, image.bounds.height > 120 { return true }
            return view.subviews.contains(where: contains)
        }
        for _ in 0..<100 { window.layoutIfNeeded(); if contains(window) { return }; try await Task.sleep(for: .milliseconds(50)) }
        XCTFail("The actual Trakt library must decode the owned cover before capture"); throw HarborError(code: "owned-trakt-cover")
    }
    private func capture(_ window: UIWindow, _ name: String) {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let image = UIGraphicsImageRenderer(bounds: window.bounds, format: format).image { _ in _ = window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
        let attachment = XCTAttachment(image: image); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}

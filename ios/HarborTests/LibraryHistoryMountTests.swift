import SwiftUI
import UIKit
import XCTest
@testable import Harbor

@MainActor final class LibraryHistoryMountTests: XCTestCase {
    func testActualHistoryPosterAndEpisodeModesRenderDecodedArtworkInBothNativeSizesWithoutStremio() async throws {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let poster = UIGraphicsImageRenderer(size: .init(width: 400, height: 600), format: format).pngData { context in
            UIColor.systemIndigo.setFill(); context.fill(.init(x: 0, y: 0, width: 400, height: 600))
            ("OWNED\nHISTORY" as NSString).draw(in: .init(x: 30, y: 150, width: 340, height: 240), withAttributes: [.font: UIFont.boldSystemFont(ofSize: 44), .foregroundColor: UIColor.white])
        }
        let wide = UIGraphicsImageRenderer(size: .init(width: 640, height: 360), format: format).pngData { context in
            UIColor.systemTeal.setFill(); context.fill(.init(x: 0, y: 0, width: 640, height: 360))
            ("OWNED EPISODE 23" as NSString).draw(in: .init(x: 50, y: 130, width: 540, height: 100), withAttributes: [.font: UIFont.boldSystemFont(ofSize: 36), .foregroundColor: UIColor.white])
        }
        let publisher = try OwnedPosterImagePublisher(poster: poster, wide: wide), base = try await publisher.start(); defer { publisher.stop() }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("owned-history-mount-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true); defer { try? FileManager.default.removeItem(at: root) }
        let account = TraktAccountStore(owner: "owned-history-mount-" + UUID().uuidString, persistence: OwnedTraktPersistence()); try account.load()
        defer { try? KeychainStore().remove(LibraryPresentation.key(owner: account.owner)) }
        let cache = LibraryCache(directory: root), service = OwnedRetirementOfflineService()
        let records: [JSONValue] = [
            .object(["_id": .string("tt7654321"), "name": .string("Owned episode"), "type": .string("series"), "poster": .string(base + "/poster.png"), "background": .string(base + "/wide.png"), "_mtime": .string("2026-10-28T00:00:00Z"), "state": .object(["season": .integer(5), "episode": .integer(23), "video_id": .string("tt7654321:5:23"), "duration": .integer(3_600_000), "timeOffset": .integer(1_440_000)])]),
            .object(["_id": .string("tt1234567"), "name": .string("Owned finished movie"), "type": .string("movie"), "poster": .string(base + "/poster.png"), "background": .string(base + "/wide.png"), "_mtime": .string("2026-10-27T00:00:00Z"), "state": .object(["flaggedWatched": .integer(1)])]),
        ]
        try await cache.save(records, owner: account.owner)
        let library = LibraryModel(service: service, writeQueue: .init(service: service, directory: root), cache: cache)
        await library.setSession(nil, personalOwner: account.owner, guestOwner: account.owner, synchronize: false)
        library.changeDisplay { $0.filter = .watched; $0.grouped = false }
        let client = TraktClient(transport: { _ in throw HarborError(code: "unexpected-history-account-request") })
        let model = LibraryHistoryModel(library: library, account: account, store: .init(owner: account.owner, disk: OwnedTraktLibraryDisk()), client: client, active: { true })
        let app = AppModel(), scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow), window = UIWindow(windowScene: scene)
        defer { window.isHidden = true; window.rootViewController = nil; previous?.makeKey() }
        for (label, size) in [("compact", CGSize(width: 390, height: 844)), ("regular", CGSize(width: 834, height: 1194))] {
            window.frame = CGRect(origin: .zero, size: size)
            for mode in LibraryHistoryView.allCases {
                library.changeDisplay { $0.historyView = mode }
                let content = NavigationStack {
                    ScrollView { LibraryHistoryContent(app: app, model: model, metadata: { media in
                        var value = media; value.poster = base + "/poster.png"; value.background = base + "/wide.png"
                        if value.type == "series" { value.videos = [Episode(id: "tt7654321:5:23", season: 5, episode: 23, name: "Owned episode title", thumbnail: base + "/wide.png")] }
                        return value
                    }).padding(20) }.background(HarborTheme.background)
                }.foregroundStyle(HarborTheme.ink).preferredColorScheme(.dark).environment(\.locale, Locale(identifier: "en"))
                window.rootViewController = UIHostingController(rootView: content); window.makeKeyAndVisible(); window.layoutIfNeeded()
                try await waitForDecodedArtwork(window); try await Task.sleep(for: .milliseconds(600)); window.layoutIfNeeded()
                let image = UIGraphicsImageRenderer(bounds: window.bounds, format: format).image { _ in _ = window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
                let attachment = XCTAttachment(image: image); attachment.name = "library-history-native-" + mode.rawValue + "-" + label; attachment.lifetime = .keepAlways; add(attachment)
                XCTAssertEqual(model.entries.count, 2); XCTAssertNil(model.error)
            }
        }
        XCTAssertFalse(library.hasCloudSession); let requests = await service.requests; XCTAssertEqual(requests, 0)
    }
    private func waitForDecodedArtwork(_ window: UIWindow) async throws {
        func decoded(_ view: UIView) -> Int {
            let own = (view as? UIImageView).map { $0.image?.cgImage != nil && $0.bounds.width > 80 && $0.bounds.height > 60 ? 1 : 0 } ?? 0
            return own + view.subviews.reduce(0) { $0 + decoded($1) }
        }
        for _ in 0..<100 { window.layoutIfNeeded(); if decoded(window) >= 2 { return }; try await Task.sleep(for: .milliseconds(50)) }
        XCTFail("Both actual history cards must decode their artwork before capture"); throw HarborError(code: "owned-history-artwork")
    }
}

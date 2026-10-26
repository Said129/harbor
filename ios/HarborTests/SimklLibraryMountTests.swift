import XCTest
import SwiftUI
import UIKit
@testable import Harbor

@MainActor final class SimklLibraryMountTests: XCTestCase {
    func testProductionLibraryAndHalfStarActionsRenderInCompactAndRegularNativeLayouts() async throws {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let cover = UIGraphicsImageRenderer(size: .init(width: 400, height: 600), format: format).pngData { context in
            UIColor.systemIndigo.setFill(); context.fill(.init(x: 0, y: 0, width: 400, height: 600))
            let text = "OWNED\nSIMKL\nCOVER" as NSString
            text.draw(in: .init(x: 30, y: 140, width: 340, height: 300), withAttributes: [.font: UIFont.boldSystemFont(ofSize: 48), .foregroundColor: UIColor.white])
        }
        let publisher = try OwnedPosterImagePublisher(poster: cover, wide: cover), base = try await publisher.start()
        defer { publisher.stop() }
        let account = SimklAccountStore(owner: "owned-mounted-simkl", persistence: OwnedSimklLibraryAccount()); try account.load()
        let store = SimklLibraryStore(owner: account.owner, disk: OwnedSimklLibraryDisk()); store.bind(account.session?.accessToken)
        var snapshot = SimklLibrarySnapshot()
        for (id, kind, title, status) in [(1, SimklMediaKind.movie, "Owned Movie", SimklListStatus.plantowatch), (2, .anime, "Owned Saga", .completed), (3, .anime, "Owned Saga Season 2", .watching)] {
            let item = SimklListItem(kind: kind, ids: .init(.object(["simkl": .integer(Int64(id))])), title: title, year: 2020 + id,
                status: status, userRating: 7, addedAt: "2023-01-01T00:00:00Z", watchedEpisodes: [], poster: base + "/poster.png")
            snapshot.items[item.id] = item
        }
        snapshot.lastSync = "2023-01-01T00:00:00Z"
        try await store.commit(snapshot, fingerprint: XCTUnwrap(store.fingerprint), expectedRevision: store.revision)
        let client = SimklClient(transport: { _ in .init(status: 200, data: Data("{}".utf8)) }, sleep: { _ in })
        let model = SimklLibraryModel(account: account, store: store, client: client, active: { true })
        let app = AppModel(), owner = "owned-simkl-mount-" + UUID().uuidString
        await app.library.setSession(nil, personalOwner: owner, guestOwner: owner, synchronize: false)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow), window = UIWindow(windowScene: scene)
        defer { window.isHidden = true; window.rootViewController = nil; previous?.makeKey() }
        for (label, size) in [("compact", CGSize(width: 390, height: 844)), ("regular", CGSize(width: 834, height: 1194))] {
            window.frame = CGRect(origin: .zero, size: size)
            let movies = ScrollView { SimklLibraryContent(app: app, model: model).padding(20) }.background(HarborTheme.background).preferredColorScheme(.dark)
            window.rootViewController = UIHostingController(rootView: movies); window.makeKeyAndVisible()
            try await settle(window); capture(window, "simkl-library-native-movies-" + label)
            let anime = ScrollView { SimklLibraryContent(app: app, model: model, kind: .anime, status: .watching).padding(20) }.background(HarborTheme.background).preferredColorScheme(.dark)
            window.rootViewController = UIHostingController(rootView: anime)
            try await settle(window); capture(window, "simkl-library-native-anime-" + label)
            let item = try XCTUnwrap(snapshot.items["movie:1"])
            window.rootViewController = UIHostingController(rootView: SimklTitleActions(media: item.media, target: item.target, model: model, ratings: true).preferredColorScheme(.dark))
            try await settle(window); capture(window, "simkl-library-native-actions-" + label)
            let accountModel = SimklAccountModel(store: account, client: client, active: { true })
            window.rootViewController = UIHostingController(rootView: NavigationStack { SimklSettingsView(model: accountModel) }.preferredColorScheme(.dark))
            try await settle(window); capture(window, "simkl-library-native-settings-" + label)
        }
        XCTAssertNil(model.error); XCTAssertEqual(store.snapshot.items.count, 3)
    }
    private func settle(_ window: UIWindow) async throws {
        window.layoutIfNeeded(); try await Task.sleep(for: .milliseconds(750)); window.layoutIfNeeded()
        XCTAssertGreaterThan(window.rootViewController?.view.bounds.width ?? 0, 300)
    }
    private func capture(_ window: UIWindow, _ name: String) {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let image = UIGraphicsImageRenderer(bounds: window.bounds, format: format).image { _ in _ = window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
        let attachment = XCTAttachment(image: image); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}

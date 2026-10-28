import SwiftUI
import UIKit
import XCTest
@testable import Harbor

@MainActor final class TraktHomeMountTests: XCTestCase {
    func testActualPersonalizedRailsViewAllAndExistingCustomizationMountDecodedCoversInBothSizes() async throws {
        let previousLanguage = UserDefaults.standard.string(forKey: "uiLanguage")
        UserDefaults.standard.set("en", forKey: "uiLanguage")
        defer { if let previousLanguage { UserDefaults.standard.set(previousLanguage, forKey: "uiLanguage") } else { UserDefaults.standard.removeObject(forKey: "uiLanguage") } }
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let cover = UIGraphicsImageRenderer(size: .init(width: 400, height: 600), format: format).pngData { context in
            UIColor.systemIndigo.setFill(); context.fill(.init(x: 0, y: 0, width: 400, height: 600))
            ("OWNED\nTRAKT\nHOME" as NSString).draw(in: .init(x: 30, y: 140, width: 340, height: 320), withAttributes: [.font: UIFont.boldSystemFont(ofSize: 48), .foregroundColor: UIColor.white])
        }
        let publisher = try OwnedPosterImagePublisher(poster: cover, wide: cover), base = try await publisher.start(); defer { publisher.stop() }
        let scenario = try XCTUnwrap(TraktHomeTests.reference()["cases"].array.first), account = try TraktHomeTests.account()
        let transport = TraktHomeTests.transport(scenario)
        let hydrator = TraktHomeHydrator(tmdb: { _, _ in throw HarborError(code: "unexpected-owned-tmdb-request") }, cinemeta: { id, kind in
            var media = Media.parse(scenario["cinemetaRaw"][id], kind: kind); media?.poster = base + "/poster.png"; return media
        })
        let model = TraktHomeModel(account: account, client: .init(transport: { try await transport.send($0) }), hydrator: hydrator, active: { true })
        await model.load(configuration: .init(tmdbKey: "", region: "US", language: "en-US", translateTitles: true))
        XCTAssertEqual(model.rows.count, 4)
        let app = AppModel(), owner = "owned-trakt-home-mount-" + UUID().uuidString
        let customization = PageCustomization(owner: owner, page: "home"), rows = model.rows.map(PageRail.discovery)
        defer { UserDefaults.standard.removeObject(forKey: "page-layout-" + EBookShelf.hash(owner + "|home")) }
        customization.setEditingRails(rows)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow), window = UIWindow(windowScene: scene)
        defer { window.isHidden = true; window.rootViewController = nil; previous?.makeKey() }
        for (label, size) in [("compact", CGSize(width: 390, height: 844)), ("regular", CGSize(width: 834, height: 1194))] {
            window.frame = CGRect(origin: .zero, size: size)
            window.rootViewController = UIHostingController(rootView: NavigationStack {
                ScrollView { DiscoveryRails(rows: Array(model.rows.prefix(2)), app: app).padding(.vertical, 20) }
                    .navigationDestination(for: Media.self) { DetailView(media: $0, app: app) }
            }.background(HarborTheme.background).foregroundStyle(HarborTheme.ink).environment(\.locale, Locale(identifier: "en")).preferredColorScheme(.dark))
            window.makeKeyAndVisible(); try await decoded(window, minimum: 4); capture(window, "trakt-home-watchlist-" + label)
            window.rootViewController = UIHostingController(rootView: NavigationStack {
                ScrollView { DiscoveryRails(rows: Array(model.rows.suffix(2)), app: app).padding(.vertical, 20) }
            }.background(HarborTheme.background).foregroundStyle(HarborTheme.ink).environment(\.locale, Locale(identifier: "en")).preferredColorScheme(.dark))
            try await decoded(window, minimum: 4); capture(window, "trakt-home-recommendations-" + label)
            window.rootViewController = UIHostingController(rootView: NavigationStack {
                DiscoveryGrid(rail: model.rows[0], app: app)
            }.background(HarborTheme.background).foregroundStyle(HarborTheme.ink).environment(\.locale, Locale(identifier: "en")).preferredColorScheme(.dark))
            try await decoded(window, minimum: 4); capture(window, "trakt-home-view-all-" + label)
            customization.editing = true
            window.rootViewController = UIHostingController(rootView: NavigationStack {
                ScrollView {
                    PageCustomizeButton(rails: rows, customization: customization)
                    CustomizedRails(rails: Array(rows.prefix(1)), app: app, customization: customization)
                }
            }.background(HarborTheme.background).foregroundStyle(HarborTheme.ink).environment(\.locale, Locale(identifier: "en")).preferredColorScheme(.dark))
            try await decoded(window, minimum: 2); capture(window, "trakt-home-customization-" + label)
            customization.editing = false
        }
        let pager = try XCTUnwrap(model.rows.first?.personal)
        let page = try await pager.page(2); XCTAssertEqual(page.count, 4)
        try account.set(nil); XCTAssertTrue(model.rows.isEmpty); XCTAssertFalse(pager.available())
    }
    private func decoded(_ window: UIWindow, minimum: Int) async throws {
        func count(_ view: UIView) -> Int {
            let own = (view as? UIImageView).map { $0.image?.cgImage != nil && $0.bounds.width > 70 && $0.bounds.height > 100 ? 1 : 0 } ?? 0
            return own + view.subviews.reduce(0) { $0 + count($1) }
        }
        for _ in 0..<120 {
            window.layoutIfNeeded()
            if count(window) >= minimum { try await Task.sleep(for: .milliseconds(300)); window.layoutIfNeeded(); return }
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTFail("Decode actual owned cover images in the production SwiftUI controls before capture")
        throw HarborError(code: "owned-trakt-home-cover")
    }
    private func capture(_ window: UIWindow, _ name: String) {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let result = UIGraphicsImageRenderer(bounds: window.bounds, format: format).image { _ in _ = window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
        let attachment = XCTAttachment(image: result); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}

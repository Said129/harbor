import XCTest
import SwiftUI
import UIKit
@testable import Harbor

@MainActor final class TraktAccountMountTests: XCTestCase {
    func testActualSettingsAuthorizationFailureAndDecodedContinuationRenderInBothNativeLayouts() async throws {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let cover = UIGraphicsImageRenderer(size: .init(width: 1024, height: 576), format: format).pngData { context in
            UIColor.systemIndigo.setFill(); context.fill(.init(x: 0, y: 0, width: 1024, height: 576))
            ("OWNED TRAKT PLAYBACK" as NSString).draw(at: .init(x: 48, y: 180), withAttributes: [.font: UIFont.boldSystemFont(ofSize: 48), .foregroundColor: UIColor.white])
        }
        let publisher = try OwnedPosterImagePublisher(poster: cover, wide: cover), base = try await publisher.start(); defer { publisher.stop() }
        let record = try XCTUnwrap(TraktPlaybackImport.items(try JSONDecoder().decode(JSONValue.self, from: Data(#"[{"progress":50,"paused_at":"2024-01-01T00:00:00Z","show":{"title":"Owned Trakt Show","ids":{"imdb":"tt1234567"}},"episode":{"season":1,"number":7}}]"#.utf8))).first)
        var media = try XCTUnwrap(record.media); media.background = base + "/wide.png"; media.poster = base + "/poster.png"
        let presentation = ContinueWatchingPresentation(record: record, media: media, watched: [])
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow), window = UIWindow(windowScene: scene)
        defer { window.isHidden = true; window.rootViewController = nil; previous?.makeKey() }
        for (label, size) in [("compact", CGSize(width: 390, height: 844)), ("regular", CGSize(width: 834, height: 1194))] {
            window.frame = CGRect(origin: .zero, size: size)
            let memory = OwnedTraktPersistence(), store = TraktAccountStore(owner: "owned-mounted-trakt-" + label, persistence: memory)
            try store.load()
            let noNetwork = TraktClient(transport: { _ in throw HarborError(code: "unexpected-network-request") })
            let settings = TraktAccountModel(store: store, client: noNetwork, active: { true })
            window.rootViewController = UIHostingController(rootView: NavigationStack { TraktSettingsView(model: settings) }.preferredColorScheme(.dark))
            window.makeKeyAndVisible(); try await settle(window); capture(window, "trakt-native-disconnected-" + label)
            try store.set(.init(accessToken: "owned-access", refreshToken: "owned-refresh", createdAt: 1_700_000_000, expiresIn: 7_776_000, username: "Owned Trakt"))
            try await settle(window); capture(window, "trakt-native-connected-" + label)
            try store.set(nil)
            let pin: JSONValue = .object(["device_code": .string("owned-device"), "user_code": .string("OWNED-123"), "expires_in": .integer(60), "interval": .integer(2)])
            let transport = OwnedTraktTransport([.init(status: 200, data: try JSONEncoder().encode(pin)), .init(status: 418, data: Data())])
            await transport.hold("/api/trakt/device-token")
            let pending = TraktAccountModel(store: store, client: TraktClient(transport: { try await transport.send($0) }, sleep: { _ in }), active: { true })
            window.rootViewController = UIHostingController(rootView: TraktDeviceAuthorizationView(model: pending).preferredColorScheme(.dark))
            for _ in 0..<100 { if await transport.isHolding { break }; try await Task.sleep(for: .milliseconds(50)) }
            let held = await transport.isHolding; XCTAssertTrue(held); XCTAssertEqual(pending.pin?.userCode, "OWNED-123")
            try await settle(window); capture(window, "trakt-native-code-" + label)
            await transport.release()
            for _ in 0..<100 { if pending.error != nil { break }; try await Task.sleep(for: .milliseconds(50)) }
            XCTAssertEqual(pending.error, "Authorization was denied. Try again."); XCTAssertNil(store.session)
            try await settle(window); capture(window, "trakt-native-denied-" + label)
            window.rootViewController = UIHostingController(rootView:
                ScrollView { VStack(alignment: .leading, spacing: 28) {
                    Text(DesktopInterfaceText.value("Continue Watching")).font(HarborTheme.font(22, weight: .semibold))
                    ContinueWatchingArtwork(record: record, media: media, presentation: presentation)
                }.padding(20).frame(maxWidth: 680, alignment: .leading).frame(maxWidth: .infinity, alignment: .leading) }
                    .background(HarborTheme.background).foregroundStyle(HarborTheme.ink).preferredColorScheme(.dark))
            for _ in 0..<100 { window.layoutIfNeeded(); if hasCover(window) { break }; try await Task.sleep(for: .milliseconds(50)) }
            XCTAssertTrue(hasCover(window)); capture(window, "trakt-native-card-" + label)
            window.rootViewController = nil
        }
    }
    private func hasCover(_ view: UIView) -> Bool {
        if let image = view as? UIImageView, image.image?.cgImage != nil, image.bounds.width > 200, image.bounds.height > 100 { return true }
        return view.subviews.contains { hasCover($0) }
    }
    private func settle(_ window: UIWindow) async throws {
        window.layoutIfNeeded(); try await Task.sleep(for: .milliseconds(650)); window.layoutIfNeeded()
        XCTAssertGreaterThan(window.rootViewController?.view.bounds.width ?? 0, 300)
    }
    private func capture(_ window: UIWindow, _ name: String) {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let image = UIGraphicsImageRenderer(bounds: window.bounds, format: format).image { _ in _ = window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
        let attachment = XCTAttachment(image: image); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}

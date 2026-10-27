import XCTest
import SwiftUI
import UIKit
@testable import Harbor

@MainActor final class SimklPlaybackImportMountTests: XCTestCase {
    func testProductionImportedCardDrawsDecodedArtworkAndTheTrackerBadgeInBothNativeLayouts() async throws {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let cover = UIGraphicsImageRenderer(size: .init(width: 1024, height: 576), format: format).pngData { context in
            UIColor.systemIndigo.setFill(); context.fill(.init(x: 0, y: 0, width: 1024, height: 576))
            ("OWNED SIMKL PLAYBACK" as NSString).draw(at: .init(x: 48, y: 180), withAttributes: [.font: UIFont.boldSystemFont(ofSize: 48), .foregroundColor: UIColor.white])
        }
        let publisher = try OwnedPosterImagePublisher(poster: cover, wide: cover), base = try await publisher.start(); defer { publisher.stop() }
        let record = try XCTUnwrap(SimklPlaybackImport.item(try JSONDecoder().decode(JSONValue.self, from: Data(#"{"progress":50,"paused_at":"2024-01-01T00:00:00Z","show":{"title":"Owned Simkl Show","ids":{"imdb":"tt1234567"}},"episode":{"season":1,"number":7}}"#.utf8))))
        var media = try XCTUnwrap(record.media); media.background = base + "/wide.png"; media.poster = base + "/poster.png"
        let presentation = ContinueWatchingPresentation(record: record, media: media, watched: [])
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow), window = UIWindow(windowScene: scene)
        defer { window.isHidden = true; window.rootViewController = nil; previous?.makeKey() }
        for (label, size) in [("compact", CGSize(width: 390, height: 780)), ("regular", CGSize(width: 834, height: 1000))] {
            window.frame = CGRect(origin: .zero, size: size)
            window.rootViewController = UIHostingController(rootView:
                ScrollView { VStack(alignment: .leading, spacing: 28) {
                    Text(DesktopInterfaceText.value("Continue Watching")).font(HarborTheme.font(22, weight: .semibold))
                    ContinueWatchingArtwork(record: record, media: media, presentation: presentation)
                }.padding(20).frame(maxWidth: 680, alignment: .leading).frame(maxWidth: .infinity, alignment: .leading) }
                    .background(HarborTheme.background).foregroundStyle(HarborTheme.ink).preferredColorScheme(.dark))
            window.makeKeyAndVisible()
            try await wait(window) { self.hasDecodedCover(window) }
            capture(window, "simkl-playback-native-card-" + label)
            window.rootViewController = nil
        }
    }
    private func hasDecodedCover(_ view: UIView) -> Bool {
        if let image = view as? UIImageView, image.image?.cgImage != nil, image.bounds.width > 200, image.bounds.height > 100 { return true }
        return view.subviews.contains { hasDecodedCover($0) }
    }
    private func wait(_ window: UIWindow, until condition: () -> Bool) async throws {
        for _ in 0..<100 { window.layoutIfNeeded(); if condition() { return }; try await Task.sleep(for: .milliseconds(50)) }
        XCTFail("The decoded production continuation card did not reach its required state")
        throw HarborError(code: "owned-playback-mount")
    }
    private func capture(_ window: UIWindow, _ name: String) {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let image = UIGraphicsImageRenderer(bounds: window.bounds, format: format).image { _ in _ = window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
        let attachment = XCTAttachment(image: image); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}

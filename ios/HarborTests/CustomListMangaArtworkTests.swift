import XCTest
import SwiftUI
import UIKit
@testable import Harbor

@MainActor final class CustomListMangaArtworkTests: XCTestCase {
    func testAnOwnedPDFCoverActuallyDecodesThroughTheListArtworkViewWithoutAReadingPlugin() async throws {
        let owner = "owned-home-cover-" + UUID().uuidString
        let book = try await OwnedHomeMangaFixture.create(owner: owner)
        do {
            let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
            let previous = scene.windows.first { $0.isKeyWindow }, window = UIWindow(windowScene: scene)
            window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
            defer { window.isHidden = true; window.rootViewController = nil; previous?.makeKeyAndVisible() }
            let context = CustomListMangaArtworkContext(activation: owner, owner: owner, books: [book], client: nil, reading: nil, isCurrent: { true })
            var decoded = false
            let media = CustomListItem(raw: CustomListItem.input(book)).media
            window.rootViewController = UIHostingController(rootView:
                VStack(spacing: 16) {
                    Text("OWNED MANGA COVER").font(.headline)
                    CustomListArtwork(media: media, url: media.poster, maxPixels: 600, onImageAvailability: { if $0 { decoded = true } })
                        .frame(width: 200, height: 300)
                    Poster(media: media, width: nil).frame(width: 150)
                }.padding().frame(maxWidth: .infinity, maxHeight: .infinity).background(HarborTheme.background)
                    .environment(\.customListMangaArtwork, context))
            window.makeKeyAndVisible()
            for _ in 0..<120 { if decoded { break }; try await Task.sleep(for: .milliseconds(50)) }
            XCTAssertTrue(decoded, "Decode the real imported PDF cover, rather than accepting a placeholder")
            XCTAssertNil(context.reading); XCTAssertNil(context.client)
            try await Task.sleep(for: .milliseconds(250)); window.layoutIfNeeded()
            let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
            let capture = XCTAttachment(image: image); capture.name = "native-home-manga-cover"; capture.lifetime = .keepAlways; add(capture)
            try await MangaLocalStore.shared.remove(book, owner: owner)
        } catch { try? await MangaLocalStore.shared.remove(book, owner: owner); throw error }
    }
}

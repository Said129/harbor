import XCTest
import ImageIO
import UIKit
import SwiftUI
@testable import Harbor

final class MangaArchiveTests: XCTestCase {
    @MainActor func testActualCBZImagesUseNaturalOrderAndNeverExposeUnsafePaths() async throws {
        XCTAssertNotNil(UIFont(name: "QRAmesBeta-Regular", size: 28), "The original Manga title font must be registered in the app host")
        let file = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "reader", withExtension: "cbz", subdirectory: "Fixtures"))
        let reader = try MangaArchive(file: file)
        XCTAssertEqual(reader.paths, ["page1.png", "page2.png", "page10.png"])
        for path in reader.paths {
            let image = try XCTUnwrap(CGImageSourceCreateWithData(reader.data(path) as CFData, nil))
            let bitmap = try XCTUnwrap(CGImageSourceCreateImageAtIndex(image, 0, nil))
            XCTAssertEqual(bitmap.width, 4); XCTAssertEqual(bitmap.height, 6)
        }
        XCTAssertThrowsError(try reader.data("../escape.png"))
        let server = try MangaServer.normalized("http://127.0.0.1:4567/api/v1", username: "user", password: "password")
        XCTAssertEqual(server.base, "http://127.0.0.1:4567")
        XCTAssertThrowsError(try server.url("https://outside.invalid/image"))
        XCTAssertFalse(MangaServer.sameOrigin(URL(string: "https://example.test:443/a")!, URL(string: "https://example.test:444/b")!))
        let owner = "manga-review-" + UUID().uuidString
        let book = try await MangaLocalStore.shared.importArchive(file, owner: owner)
        do {
            let chapters = try await MangaLocalStore.shared.chapters(book, owner: owner)
            XCTAssertEqual(chapters.count, 1)
            XCTAssertEqual(chapters.first?.pages, 3)
            let shelf = MangaShelf(owner: owner)
            var record = MangaRecord(book: book, chapter: "local")
            record.progress["local"] = MangaProgress(page: 1)
            try shelf.save(record)
            defer { try? shelf.remove(book) }
            XCTAssertNil(MangaShelf(owner: owner + ".other").record(book))
            let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
            let previous = scene.windows.first { $0.isKeyWindow }
            let window = UIWindow(windowScene: scene)
            window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
            defer { window.isHidden = true; window.rootViewController = nil; previous?.makeKeyAndVisible() }
            window.rootViewController = UIHostingController(rootView: NavigationStack { MangaDetailView(book: book, shelf: shelf, client: nil) })
            window.makeKeyAndVisible()
            try await Task.sleep(for: .milliseconds(700))
            window.layoutIfNeeded()
            let snapshot = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
            let attachment = XCTAttachment(image: snapshot)
            attachment.name = "native-manga-local-detail"
            attachment.lifetime = .keepAlways
            add(attachment)
            try await MangaLocalStore.shared.remove(book, owner: owner)
        } catch {
            try? await MangaLocalStore.shared.remove(book, owner: owner)
            throw error
        }
    }
}

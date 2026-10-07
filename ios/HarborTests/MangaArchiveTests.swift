import XCTest
import ImageIO
import UIKit
@testable import Harbor

final class MangaArchiveTests: XCTestCase {
    @MainActor func testActualCBZImagesUseNaturalOrderAndNeverExposeUnsafePaths() throws {
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
    }
}

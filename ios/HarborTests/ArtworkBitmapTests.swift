import XCTest
import UIKit
@testable import Harbor

@MainActor final class ArtworkBitmapTests: XCTestCase {
    private func picture(_ size: CGSize) throws -> Data {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.orange.setFill(); context.fill(CGRect(origin: .zero, size: size))
        }
        return try XCTUnwrap(image.pngData())
    }
    func testNativeWorkerDownsamplesRealImageDataToTheRequestedPixelBudget() async throws {
        let image = try await ArtworkBitmapDecoder.thumbnail(picture(CGSize(width: 1_000, height: 600)), maxPixels: 200).image
        XCTAssertEqual(image.cgImage?.width, 200); XCTAssertEqual(image.cgImage?.height, 120)
        XCTAssertThrowsError(try ArtworkBitmapDecoder.decode(Data("owned invalid image".utf8), maxPixels: 200))
    }
    func testOriginalResolutionUsesTheImageDimensionsAndDoesNotUpscaleSmallArtwork() async throws {
        let data = try picture(CGSize(width: 300, height: 180))
        let original = try await ArtworkBitmapDecoder.thumbnail(data, maxPixels: 0).image
        XCTAssertEqual(original.cgImage?.width, 300); XCTAssertEqual(original.cgImage?.height, 180)
        let small = try await ArtworkBitmapDecoder.thumbnail(data, maxPixels: 1_000).image
        XCTAssertEqual(small.cgImage?.width, 300); XCTAssertEqual(small.cgImage?.height, 180)
    }
}

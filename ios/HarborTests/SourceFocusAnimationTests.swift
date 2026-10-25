import XCTest
@testable import Harbor

@MainActor final class SourceFocusAnimationTests: XCTestCase {
    func testTheOwnedFocusGIFKeepsItsFrameTimingAndIsDecodedWithinTheMobileImageBudget() throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "owned-source-focus", withExtension: "gif", subdirectory: "Fixtures"))
        let decoded = try SourceAnimationDecoder.decode(Data(contentsOf: url))
        XCTAssertEqual(decoded.images.count, 3); XCTAssertEqual(decoded.duration, 0.3, accuracy: 0.01); XCTAssertEqual(decoded.repeats, 0)
        for image in decoded.images { XCTAssertLessThanOrEqual(max(image.size.width, image.size.height), 480) }
    }
}

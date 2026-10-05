import XCTest
import UIKit
@testable import Harbor

final class EPUBReaderTests: XCTestCase {
    @MainActor func testRealArchiveUsesSpineOrderAndPreservesInlineTextWithoutExecutingBookContent() throws {
        XCTAssertNotNil(UIFont(name: "SwitzerVariable-Regular", size: 16), "The original interface font must be registered in the app host")
        let file = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "reader", withExtension: "epub", subdirectory: "Fixtures"))
        let reader = try EPUBReader(data: Data(contentsOf: file))
        XCTAssertEqual(reader.publication.title, "Harbor reader fixture")
        XCTAssertEqual(reader.publication.authors, ["Harbor tests"])
        XCTAssertEqual(reader.publication.chapters.map(\.title), ["First section", "Second section"])
        let first = try reader.blocks(reader.publication.chapters[0])
        XCTAssertEqual(first.map(\.text), ["First section", "One two three & four.", "Literal <text>"])
        XCTAssertEqual(try reader.blocks(reader.publication.chapters[1]).map(\.text), ["Second section", "Five six seven."])
        XCTAssertTrue(first.allSatisfy { $0.image == nil })
    }
}

import XCTest
@testable import Harbor

final class ReaderHeadingInterfaceSeedTests: XCTestCase {
    @MainActor func testPrepareOwnedEmbeddedCoverEPUBInOneFreshGuest() async throws {
        try await EBookDetailInterfaceSeedTests.prepare()
        let owner = try XCTUnwrap(AppProfileContext.shared.binding?.personalOwner)
        let file = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "reader-cover", withExtension: "epub", subdirectory: "Fixtures"))
        let book = try await EBookService.shared.importDocument(file, owner: owner)
        XCTAssertEqual(book.title, "Owned cover book"); XCTAssertTrue(book.readable)
        let cover = try await EBookService.shared.cover(book, owner: owner)
        XCTAssertNotNil(cover); XCTAssertGreaterThan(cover?.count ?? 0, 100)
        try EBookShelf(owner: owner).addImported(book)
        UserDefaults.standard.set("harbor", forKey: "ebook.mode"); UserDefaults.standard.set(false, forKey: "ebook.focusMode")
    }
}

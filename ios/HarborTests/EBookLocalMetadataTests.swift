import XCTest
@testable import Harbor

@MainActor final class EBookLocalMetadataTests: XCTestCase {
    func testImportedAndLegacyEPUBRemainReadableAfterPublicMetadataAndShelfRestoration() async throws {
        let owner = "owned-local-metadata-" + UUID().uuidString, service = EBookService()
        let file = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "reader", withExtension: "epub", subdirectory: "Fixtures"))
        let imported = try await service.importDocument(file, owner: owner)
        addTeardownBlock { @MainActor in
            try? await service.remove(imported, owner: owner)
            try? KeychainStore().remove("ebook-shelf-" + EBookShelf.hash(owner))
        }
        XCTAssertNil(imported.epub); XCTAssertTrue(imported.readable)
        var legacy = try JSONValue.encoded(imported).objectValue
        legacy["format"] = nil
        let restored = try JSONValue.object(legacy).decoded(EBook.self)
        XCTAssertTrue(restored.readable)
        let metadata: JSONValue = .object(["id": .string("openlibrary:owned"), "source": .string("openlibrary"), "title": .string("Harbor reader fixture"), "description": .string("Public description"), "authors": .array([])])
        let enriched = EBookMetadataMapping.detail(metadata, preserving: restored)
        XCTAssertEqual(enriched.id, imported.id); XCTAssertTrue(enriched.readable); XCTAssertNil(enriched.epub)
        XCTAssertEqual(enriched.authors, ["Harbor tests"])
        let shelf = EBookShelf(owner: owner); try shelf.addImported(enriched)
        let held = try XCTUnwrap(EBookShelf(owner: owner).record(enriched)?.book)
        XCTAssertTrue(held.readable)
        let publication = try await EBookService().open(held, owner: owner)
        XCTAssertEqual(publication.title, "Harbor reader fixture")
        let blocks = try await service.blocks(held, owner: owner, chapter: 1)
        XCTAssertEqual(blocks.map(\.text), ["Second section", "Five six seven."])
    }
}

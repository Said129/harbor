import XCTest
@testable import Harbor

@MainActor final class EBookMetadataPublicTests: XCTestCase {
    func testActualPublicMetadataSearchReturnsTheNamedBookAndAuthorWithoutAnAccountOrAPIKey() async throws {
        guard ProcessInfo.processInfo.environment["HARBOR_LIVE_INTEGRATION"] == "1" else { throw XCTSkip("Public metadata requires explicit live integration selection") }
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("public-book-metadata-" + UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: file) }
        let scope = PluginExecutionScope(owner: "public-metadata-contract", activation: UUID())
        let client = try EBookMetadataClient(scope: scope, currentScope: { scope }, cache: EBookMetadataCache(owner: scope.owner, file: file), googleKey: "", language: "en")
        defer { client.dispose() }
        let books = try await client.books("search", arguments: ["query": .string("Pride and Prejudice")])
        let found = try XCTUnwrap(books.first {
            $0.title.localizedCaseInsensitiveContains("prejudice") && $0.authors.contains { $0.localizedCaseInsensitiveContains("austen") }
        }, "The actual public provider must return the requested book and author")
        XCTAssertFalse(found.id.isEmpty)
        XCTAssertNotNil(found.metadata?["source"].string)
        print("Actual public ebook metadata: named book and author resolved without account or API key")
    }
}

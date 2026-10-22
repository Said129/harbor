import XCTest
@testable import Harbor

final class EBookMetadataInterfaceSeedTests: XCTestCase {
    @MainActor func testPrepareReadingSourcesAndOriginalPublicBookCacheOnAFreshGuest() async throws {
        try await HarborReadingPluginInterfaceSeedTests.prepareAllPendingReadingInterfaces()
        let context = AppProfileContext.shared
        guard let owner = context.binding?.personalOwner, context.profiles.profiles.count == 1, context.configuration?.account == nil else { XCTFail("Refuse configured profiles"); return }
        let file = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "ebook-metadata-reference", withExtension: "json", subdirectory: "Fixtures"))
        var fixture = try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: file)).objectValue
        var open = fixture["open"]?.objectValue ?? [:]
        open["title"] = .string("Owned Book"); open["author_name"] = .array([.string("Owned author")]); fixture["open"] = .object(open)
        let scope = PluginExecutionScope(owner: owner, activation: UUID())
        let htmlFile = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "reading-html-reference", withExtension: "json", subdirectory: "Fixtures"))
        let html = try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: htmlFile))
        let manager = HarborReadingPluginManager(scope: scope, currentScope: { scope }, store: try HarborReadingPluginStore())
        defer { manager.dispose() }; try await manager.load()
        try await HarborReadingHTMLInterfaceSeedTests.installManualSources(manager, fixture: html)
        let client = try EBookMetadataClient(scope: scope, currentScope: { scope }, network: MetadataNetwork(.object(fixture)), googleKey: "", language: "es")
        defer { client.dispose() }
        let popular = try await client.books("popular"); XCTAssertEqual(popular.first?.title, "Owned Book")
        _ = try await client.query("category", arguments: ["category": .string("Fantasy")])
        _ = try await client.query("search", arguments: ["query": .string("Owned"), "category": .string("Fantasy")])
        try await client.flush()
    }
}

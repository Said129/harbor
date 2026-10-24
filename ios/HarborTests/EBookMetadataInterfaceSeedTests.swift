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
        let persisted = try await EBookMetadataCache(owner: owner).load()
        XCTAssertFalse(persisted.isEmpty, "The following UI process must receive a persisted public catalog")
        let coldNetwork = MetadataNetwork(.object(fixture))
        let reopened = try EBookMetadataClient(scope: scope, currentScope: { scope }, network: coldNetwork, googleKey: "", language: "es")
        defer { reopened.dispose() }
        let restored = try await reopened.books("search", arguments: ["query": .string("Owned"), "category": .string("Fantasy")])
        XCTAssertEqual(restored.first?.title, "Owned Book")
        let outbound = await coldNetwork.requests
        let diagnostic = XCTAttachment(string: "Owner: " + EBookShelf.hash(owner) + "\nPersisted public keys:\n" + persisted.keys.sorted().joined(separator: "\n") + "\nFresh worker requests:\n" + outbound.map(\.url).joined(separator: "\n"))
        diagnostic.name = "owned-public-catalog-cold-cache"; diagnostic.lifetime = .keepAlways; add(diagnostic)
        XCTAssertTrue(outbound.isEmpty, "A fresh worker must read the prepared catalog without another network request")
    }
}

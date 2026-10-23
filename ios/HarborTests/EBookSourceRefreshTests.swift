import XCTest
@testable import Harbor

private actor HeldReadingCatalog {
    private var released = false
    private var waiters: [CheckedContinuation<[EBook], Never>] = []
    private(set) var waiting = false
    func search(_ query: String) async -> [EBook] {
        if released { return [] }; waiting = true
        return await withCheckedContinuation { waiters.append($0) }
    }
    func release() { released = true; let pending = waiters; waiters = []; pending.forEach { $0.resume(returning: []) } }
}

@MainActor final class EBookSourceRefreshTests: XCTestCase {
    func testFreshProviderSearchReplacesTheEnrichedAliasAndPublishesBeforeTheSlowCatalogFinishes() async throws {
        let previousLanguage = UserDefaults.standard.object(forKey: "uiLanguage")
        UserDefaults.standard.set("en", forKey: "uiLanguage")
        defer { if let previousLanguage { UserDefaults.standard.set(previousLanguage, forKey: "uiLanguage") } else { UserDefaults.standard.removeObject(forKey: "uiLanguage") } }
        let file = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "ebook-metadata-reference", withExtension: "json", subdirectory: "Fixtures"))
        let fixture = try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: file)), network = MetadataNetwork(fixture)
        let store = FileManager.default.temporaryDirectory.appendingPathComponent("source-refresh-" + UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: store) }
        let scope = PluginExecutionScope(owner: "source-refresh-" + UUID().uuidString, activation: UUID())
        let manager = HarborReadingPluginManager(scope: scope, currentScope: { scope }, store: try HarborReadingPluginStore(file: store), network: network)
        defer { manager.dispose() }; try await manager.load()
        try await manager.addRepository("https://example.org/metadata/repo.json", kind: .ebook)
        let repository = try XCTUnwrap(manager.document.repositories.first)
        try await manager.install(XCTUnwrap(repository.entries.first), repository: repository)
        let plugin = try XCTUnwrap(manager.installed(.ebook).first), client = try manager.ebookMetadata()
        let fresh = try await manager.ebookBrowse(plugin, query: "Owned Book", offset: 0)
        XCTAssertEqual(fresh.first?.title, "Owned Book")
        let stale = try await client.books("cached", arguments: ["books": .array(fresh.map(EBookMetadataMapping.raw))], preserving: fresh)
        XCTAssertEqual(stale.first?.title, "one")
        var open = fixture["open"].objectValue; open["title"] = .string("Owned Book"); open["author_name"] = .array([.string("Owned Writer")])
        let mapped = try await client.query("map", arguments: ["kind": .string("openlibrary"), "raw": .object(open)])
        let targets = EBookMetadataMapping.books(.array([mapped]))
        let target = try XCTUnwrap(targets.first)
        let gate = HeldReadingCatalog(); var partial: [[EBook]] = []
        let pending = Task { try await manager.resolveEBook(target, candidates: stale, catalog: { await gate.search($0) }) { partial.append($0) } }
        defer { pending.cancel(); Task { await gate.release() } }
        for _ in 0..<300 {
            if partial.contains(where: { !$0.isEmpty }), await gate.waiting { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        let catalogBlocked = await gate.waiting
        XCTAssertTrue(catalogBlocked); XCTAssertTrue(partial.contains { !$0.isEmpty }, "A fresh readable provider result must be published while another catalogue is still held")
        let route = try XCTUnwrap(partial.first(where: { !$0.isEmpty })?.first)
        XCTAssertEqual(route.id, fresh.first?.id); XCTAssertEqual(route.pluginID, fresh.first?.pluginID); XCTAssertEqual(route.itemID, "one"); XCTAssertEqual(route.title, "Owned Book")
        await gate.release(); let final = try await pending.value
        let readable = try XCTUnwrap(final.first), publication = try await manager.ebookPublication(readable)
        let blocks = try await manager.ebookBlocks(readable, chapter: XCTUnwrap(publication.chapters.first))
        XCTAssertEqual(blocks.first?.text, "Owned readable paragraph.")
    }
}

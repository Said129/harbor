import XCTest
@testable import Harbor

final class ReaderContentsInterfaceSeedTests: XCTestCase {
    @MainActor func testPrepareOwnedVolumesAndSavedBookInOneFreshGuest() async throws {
        try await EBookDetailInterfaceSeedTests.prepare()
        let owner = try XCTUnwrap(AppProfileContext.shared.binding?.personalOwner)
        let scope = PluginExecutionScope(owner: owner, activation: UUID())
        let manager = HarborReadingPluginManager(scope: scope, currentScope: { scope }, store: try HarborReadingPluginStore(), network: BookChapterNetwork())
        defer { manager.dispose() }; try await manager.load()
        let plugin = try XCTUnwrap(manager.installed(.ebook).first)
        let books = try await manager.ebookBrowse(plugin, query: "", offset: 0)
        try EBookShelf(owner: owner).addImported(XCTUnwrap(books.first))
        UserDefaults.standard.set("harbor", forKey: "ebook.mode")
        UserDefaults.standard.set(false, forKey: "ebook.focusMode")
    }
}

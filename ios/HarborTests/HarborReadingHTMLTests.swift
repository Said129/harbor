import XCTest
@testable import Harbor

private actor ReadingHTMLNetwork: HarborNativeNetworkCalling {
    let documents: JSONValue
    private var holding = false
    private var held: CheckedContinuation<Void, Never>?
    private(set) var requests: [HarborNetworkRequest] = []
    init(_ documents: JSONValue) { self.documents = documents }
    func perform(_ request: HarborNetworkRequest) async throws -> HarborNetworkResponse {
        requests.append(request)
        let url = try XCTUnwrap(URL(string: request.url))
        if holding && url.path == "/popular" { await withCheckedContinuation { held = $0 } }
        try Task.checkCancellation()
        let data: Data
        if url.path.hasSuffix(".png") { data = Data([1, 2, 3]) }
        else {
            let key = url.path.isEmpty || url.path == "/" ? "favicon" : url.path.contains("/book/") ? "detail" : url.path.contains("/chapter/") ? "chapter" : "catalog"
            data = Data(try XCTUnwrap(documents[key].string).utf8)
        }
        return .init(status: 200, ok: true, headers: [:], bodyBase64: data.base64EncodedString(), url: request.url)
    }
    func holdPopular() { holding = true }
    func waitUntilHeld() async throws {
        for _ in 0..<900 { if held != nil { return }; try await Task.sleep(for: .milliseconds(50)) }
        throw HarborPluginRepositoryError("owned-html-timeout")
    }
    func release() { holding = false; let continuation = held; held = nil; continuation?.resume() }
}

@MainActor private final class ReadingHTMLScope {
    var value = PluginExecutionScope(owner: "owned-html", activation: UUID())
}

@MainActor final class HarborReadingHTMLTests: XCTestCase {
    private func fixture() throws -> JSONValue {
        let file = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "reading-html-reference", withExtension: "json", subdirectory: "Fixtures"))
        return try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: file))
    }
    private func source(kind: String, config: JSONValue) throws -> String {
        let raw = String(decoding: try JSONEncoder().encode(config), as: UTF8.self)
        return String(decoding: try JSONEncoder().encode(["kind": kind, "raw": raw]), as: UTF8.self)
    }
    private func runtime(kind: String, config: JSONValue, context: ReadingHTMLScope, network: ReadingHTMLNetwork) throws -> HarborPluginRuntime {
        HarborPluginRuntime(id: "owned-html-" + kind, name: "Owned HTML", source: try source(kind: kind, config: config), format: .trustedHTML,
            scope: context.value, currentScope: { context.value }, transport: HarborNativePluginTransport(policy: .reading(baseURL: "https://example.org", blockedHosts: []), network: network))
    }
    func testActualWebKitDOMMatchesAllNineOriginalManualHTMLProviderCases() async throws {
        let fixture = try fixture(), context = ReadingHTMLScope(), network = ReadingHTMLNetwork(fixture["documents"])
        var runtimes: [String: HarborPluginRuntime] = [:]
        defer { runtimes.values.forEach { $0.dispose() } }
        XCTAssertEqual(fixture["fixtures"].array.count, 9)
        for row in fixture["fixtures"].array {
            let kind = try XCTUnwrap(row["kind"].string)
            let current: HarborPluginRuntime
            if let existing = runtimes[kind] { current = existing }
            else { current = try runtime(kind: kind, config: row["config"], context: context, network: network); runtimes[kind] = current }
            let actual = try await current.call(XCTUnwrap(row["method"].string), arguments: row["args"].array)
            XCTAssertEqual(actual, row["expected"], row["name"].string ?? "HTML source")
        }
        let requests = await network.requests
        XCTAssertTrue(requests.contains { $0.url.contains("q=A%20%2B%20B&page=2") })
        XCTAssertTrue(requests.allSatisfy { $0.headers.first(where: { $0.key.lowercased() == "referer" })?.value == "https://example.org/" })
        let ebook = try XCTUnwrap(runtimes["ebook"])
        _ = try await ebook.call("popular", arguments: [.integer(1)])
        let unknown = try await ebook.call("popular", arguments: [.integer(999)])
        XCTAssertEqual(unknown, .array([]))
    }
    func testManualSourceSaveReadEditDisableAndRemovalKeepDesktopRoutesAndCleanConfiguration() async throws {
        let fixture = try fixture(), context = ReadingHTMLScope(), network = ReadingHTMLNetwork(fixture["documents"])
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("manual-html-" + UUID().uuidString + ".json")
        addTeardownBlock { try? FileManager.default.removeItem(at: file) }
        let manager = HarborReadingPluginManager(scope: context.value, currentScope: { context.value }, store: try HarborReadingPluginStore(file: file), network: network)
        defer { manager.dispose() }; try await manager.load()
        for kind in HarborReadingPluginKind.allCases {
            let config = try XCTUnwrap(fixture["fixtures"].array.first { $0["kind"].string == kind.rawValue })["config"]
            try await manager.saveHTML(kind: kind, raw: String(decoding: JSONEncoder().encode(config), as: UTF8.self), language: "en")
        }
        let initialRequests = await network.requests; XCTAssertEqual(initialRequests.count, 1)
        XCTAssertEqual(initialRequests.first.flatMap { URL(string: $0.url)?.host }, "example.org")
        XCTAssertEqual(manager.document.repositories.count, 2)
        let mangaPlugin = try XCTUnwrap(manager.installed(.manga).first), ebookPlugin = try XCTUnwrap(manager.installed(.ebook).first)
        XCTAssertEqual(mangaPlugin.entry.id, "custom-html-https-example-org")
        XCTAssertEqual(mangaPlugin.entry.icon, "https://example.org/mark.svg")
        XCTAssertEqual(ebookPlugin.entry.id, "html:1n7lmeo")
        let mangaRows = try await manager.mangaBrowse(mangaPlugin, query: "", offset: 0)
        let manga = try XCTUnwrap(mangaRows.first); XCTAssertEqual(manga.id, "custom-html-https-example-org::/book/one")
        let chapters = try await manager.mangaChapters(manga)
        let pages = try await manager.mangaPages(manga, chapter: XCTUnwrap(chapters.first))
        _ = try await manager.image(XCTUnwrap(pages.first?.path), pluginID: mangaPlugin.id)
        let headers = await network.requests.last?.headers
        XCTAssertEqual(headers?.first(where: { $0.key.lowercased() == "referer" })?.value, "https://example.org/")
        let bookRows = try await manager.ebookBrowse(ebookPlugin, query: "", offset: 0)
        let book = try XCTUnwrap(bookRows.first)
        XCTAssertEqual(book.id, "source:html%3A1n7lmeo:%2Fbook%2Fone"); XCTAssertEqual(book.itemID, "/book/one")
        let publication = try await manager.ebookPublication(book)
        XCTAssertEqual(publication.chapters.count, 2)
        let blocks = try await manager.ebookBlocks(book, chapter: XCTUnwrap(publication.chapters.first))
        XCTAssertEqual(blocks.map(\.text), ["Owned heading", "First paragraph.", "Second paragraph."])
        try await manager.setEnabled(mangaPlugin, false)
        let disabled = try XCTUnwrap(manager.document.plugins.first { $0.kind == .manga })
        var updated = disabled.entry.raw["htmlConfig"].objectValue; updated["baseUrl"] = .string("https://second.example.org")
        try await manager.saveHTML(kind: .manga, raw: String(decoding: JSONEncoder().encode(JSONValue.object(updated)), as: UTF8.self), name: "Renamed manual", replacing: disabled)
        let changed = try XCTUnwrap(manager.document.plugins.first { $0.kind == .manga })
        XCTAssertFalse(changed.enabled); XCTAssertNotEqual(changed.id, disabled.id); XCTAssertEqual(changed.entry.name, "Renamed manual")
        let saved = try await HarborReadingPluginStore(file: file).load(); XCTAssertEqual(saved, manager.document)
        for plugin in manager.document.plugins { try await manager.remove(plugin) }
        XCTAssertTrue(manager.document.plugins.isEmpty); XCTAssertTrue(manager.document.repositories.isEmpty)
        let remaining = String(decoding: try Data(contentsOf: file), as: UTF8.self)
        XCTAssertFalse(remaining.contains("Referer")); XCTAssertFalse(remaining.contains("htmlConfig"))
    }
    func testInvalidManualConfigurationNeverChangesTheInstalledDocument() async throws {
        let context = ReadingHTMLScope(), network = ReadingHTMLNetwork(.object([:]))
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("invalid-html-" + UUID().uuidString + ".json")
        addTeardownBlock { try? FileManager.default.removeItem(at: file) }
        let manager = HarborReadingPluginManager(scope: context.value, currentScope: { context.value }, store: try HarborReadingPluginStore(file: file), network: network)
        defer { manager.dispose() }; try await manager.load(); let before = manager.document
        for kind in HarborReadingPluginKind.allCases {
            for raw in ["{", "{}"] {
                do { try await manager.saveHTML(kind: kind, raw: raw); XCTFail("Invalid config must fail") } catch {}
                XCTAssertEqual(manager.document, before); XCTAssertFalse(manager.busy)
            }
        }
        let requests = await network.requests; XCTAssertTrue(requests.isEmpty)
    }
    func testCancellingTrustedHTMLCallDoesNotPublishItsLatePageOrBlockOtherCallsAndScopeRetirement() async throws {
        let fixture = try fixture(), context = ReadingHTMLScope(), network = ReadingHTMLNetwork(fixture["documents"])
        let config = try XCTUnwrap(fixture["fixtures"].array.first { $0["kind"].string == "ebook" })["config"]
        let current = try runtime(kind: "ebook", config: config, context: context, network: network)
        defer { current.dispose(); Task { await network.release() } }
        _ = try await current.metadata(); await network.holdPopular()
        let pending = Task { try await current.call("popular", arguments: [.integer(0)]) }
        try await network.waitUntilHeld(); pending.cancel()
        do { _ = try await pending.value; XCTFail("Cancelled page must be rejected") } catch is CancellationError {}
        let detail = try await current.call("detail", arguments: [.string("/book/one")], jsonResult: true)
        let ordered = try JSONDecoder().decode(JSONValue.self, from: Data(XCTUnwrap(detail.string).utf8))
        XCTAssertEqual(ordered["title"].string, "The Book")
        await network.release()
        let content = try await current.call("content", arguments: [.string("/chapter/one")])
        XCTAssertTrue(content["text"].string?.contains("First paragraph.") == true)
        context.value = .init(owner: "new-owner", activation: UUID())
        do { _ = try await current.call("chapters", arguments: [.string("/book/one")]); XCTFail("Retired scope cannot call its source") }
        catch let error as HarborPluginRuntimeError { XCTAssertEqual(error.code, "plugin-scope") }
        XCTAssertTrue(current.isDisposed)
    }
}

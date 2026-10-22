import XCTest
@testable import Harbor

private actor ReadingRepositoryNetwork: HarborNativeNetworkCalling {
    private(set) var requests: [HarborNetworkRequest] = []
    func perform(_ request: HarborNetworkRequest) async throws -> HarborNetworkResponse {
        requests.append(request)
        let source: String
        switch request.url {
        case "http://127.0.0.1:18734/repo.json":
            source = #"{"plugins":[{"id":"owned.local.reading","name":"Owned local source","entry":"manga.js"}]}"#
        case "http://127.0.0.1:18734/manga.js":
            source = #"var plugin={id:'owned.local.reading',name:'Owned local source',popular:function(){return [{id:'one',title:'Owned local manga'}];},chapters:function(){return [{id:'chapter',title:'Owned chapter'}];}};"#
        default: throw HarborPluginRepositoryError("owned-reading-route")
        }
        return .init(status: 200, ok: true, headers: [:], bodyBase64: Data(source.utf8).base64EncodedString(), url: request.url)
    }
}

@MainActor final class ReadingRoutingTests: XCTestCase {
    func testReadingRepositoryCanKeepExplicitHTTPWhileOrdinaryPluginPolicyRetainsHTTPS() throws {
        XCTAssertEqual(try HarborPluginManifest.normalizeURL(" HTTP://LOCALHOST:80/reading#notes ", allowHTTP: true), "http://localhost/reading/manifest.json")
        XCTAssertEqual(try HarborPluginManifest.normalizeURL("https://example.org:443/repo.json", allowHTTP: true), "https://example.org/repo.json")
        XCTAssertThrowsError(try HarborPluginManifest.normalizeURL("http://localhost/reading"))
        for url in ["file:///tmp/source.json", "ftp://example.org/source.json", "javascript:alert(1)"] {
            XCTAssertThrowsError(try HarborPluginManifest.normalizeURL(url, allowHTTP: true))
        }
        XCTAssertFalse(HarborNetworkRequest(url: "http://localhost/").allowLocalNetwork)
        XCTAssertTrue(HarborPluginNetworkPolicy.reading(baseURL: nil, blockedHosts: []).allowLocalNetwork)
        XCTAssertFalse(HarborPluginNetworkPolicy.stream(installing: true, blockedHosts: []).allowLocalNetwork)
    }

    func testActualReadingRepositoryAndSourceDownloadCarryBoundedLocalAccessAndRemainReadableAfterRestore() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("owned-reading-route-" + UUID().uuidString, isDirectory: true)
        let file = folder.appendingPathComponent("reading.json")
        defer { try? FileManager.default.removeItem(at: folder) }
        let scope = PluginExecutionScope(owner: "owned-local-reading", activation: UUID())
        let network = ReadingRepositoryNetwork(), store = try HarborReadingPluginStore(file: file)
        let manager = HarborReadingPluginManager(scope: scope, currentScope: { scope }, store: store, network: network)
        defer { manager.dispose() }; try await manager.load()
        try await manager.addRepository("http://127.0.0.1:18734/repo.json", kind: .manga)
        let repo = try XCTUnwrap(manager.document.repositories.first)
        try await manager.install(XCTUnwrap(repo.entries.first), repository: repo)
        let requests = await network.requests
        XCTAssertEqual(requests.map(\.url), [repo.url, "http://127.0.0.1:18734/manga.js"])
        for request in requests {
            XCTAssertTrue(request.allowLocalNetwork); XCTAssertTrue(request.strictLimit)
            XCTAssertFalse(request.publicNetworkOnly); XCTAssertEqual(request.maxResponseBytes, 2 * 1024 * 1024)
        }
        let restored = HarborReadingPluginManager(scope: scope, currentScope: { scope }, store: try HarborReadingPluginStore(file: file), network: network)
        defer { restored.dispose() }; try await restored.load()
        let rows = try await restored.mangaBrowse(XCTUnwrap(restored.installed(.manga).first), query: "", offset: 0)
        let manga = try XCTUnwrap(rows.first)
        let chapters = try await restored.mangaChapters(manga)
        XCTAssertEqual(manga.title, "Owned local manga"); XCTAssertEqual(chapters.first?.id, "owned.local.reading::chapter")
    }
}

import XCTest
@testable import Harbor

private actor BillboardFixtureNetwork: HarborNativeNetworkCalling {
    private(set) var requests: [HarborNetworkRequest] = []
    private var fail = false
    private var holding = false
    private var gate: CheckedContinuation<Void, Never>?
    func perform(_ request: HarborNetworkRequest) async throws -> HarborNetworkResponse {
        requests.append(request)
        if holding { await withCheckedContinuation { gate = $0 } }
        try Task.checkCancellation()
        if fail { fail = false; return .init(status: 503, ok: false, headers: [:], bodyBase64: Data().base64EncodedString(), url: request.url) }
        let chart = try XCTUnwrap(URL(string: request.url)?.path.split(separator: "/").last.map(String.init))
        let html = Self.page(chart, rows: Self.row(1, title: "Owned song", artist: "Owned artist"))
        return .init(status: 200, ok: true, headers: [:], bodyBase64: Data(html.utf8).base64EncodedString(), url: request.url)
    }
    func failNext() { fail = true }
    func hold() { holding = true }
    func release() { holding = false; gate?.resume(); gate = nil }
    static func page(_ chart: String, rows: String, date: String = "Week of October 24, 2026") -> String {
        "<html><head><link rel='canonical' href='https://www.billboard.com/charts/\(chart)/'></head><body><h2>\(date)</h2>\(rows)</body></html>"
    }
    static func row(_ rank: Int, title: String, artist: String, artwork: String = "https://charts-static.billboard.com/owned.jpg") -> String {
        "<div class='o-chart-results-list-row-container'><ul class='o-chart-results-list-row'><li><span class='c-label'>\(rank)</span></li><li><h3 id='title-of-a-story'>\(title)</h3><span>\(artist)</span><img src='\(artwork)'></li></ul></div>"
    }
}
private actor BillboardAlbumNetwork: MusicCatalogNetworking {
    var duplicate = false
    func setDuplicate() { duplicate = true }
    func performMusicCatalog(_ request: MusicCatalogRequest) async throws -> HarborNetworkResponse {
        XCTAssertEqual(request.operation, "search"); XCTAssertEqual(request.limit, 32)
        let album: JSONValue = .object(["id": .string("deezer:album:42"), "connectorId": .string("catalog"), "title": .string("Owned Album™"), "artist": .string("Owned Artist"), "artwork": .string("")])
        let albums = duplicate ? [album, album] : [album]
        let data = try JSONEncoder().encode(JSONValue.object(["tracks": .array([]), "albums": .array(albums), "artists": .array([]), "playlists": .array([])]))
        return .init(status: 200, ok: true, headers: [:], bodyBase64: data.base64EncodedString(), url: "https://api.deezer.com/search/album")
    }
}
@MainActor private final class BillboardScope {
    var value = PluginExecutionScope(owner: "owned-billboard", activation: UUID())
}
@MainActor final class MusicBillboardNativeTests: XCTestCase {
    func testActualWorkerRetainsAllChartsParsesRanksDatesAndKindsAndRejectsWrongPageIdentity() async throws {
        let scope = BillboardScope(), network = BillboardFixtureNetwork()
        let untrusted = HarborPluginRuntime(id: "untrusted-billboard", name: "Untrusted", source: "var plugin={content(){return 'untrusted';}};", format: .trustedBillboard,
            scope: scope.value, currentScope: { scope.value }, transport: MusicBillboardTransport(network: network))
        do { _ = try await untrusted.call("content", arguments: [.object([:])]); XCTFail("Only the exact bundled Billboard program may use the document host") }
        catch let error as HarborPluginRuntimeError { XCTAssertEqual(error.code, "plugin-source") }
        untrusted.dispose()
        let client = MusicBillboardClient(scope: scope.value, currentScope: { scope.value }, transport: MusicBillboardTransport(network: network))
        defer { client.dispose() }
        let definitions = try await client.query("definitions", as: [MusicBillboardReference].self)
        XCTAssertEqual(definitions, try MusicBillboardAsset.read().charts); XCTAssertEqual(definitions.count, 196)
        let rows = BillboardFixtureNetwork.row(3, title: "Third", artist: "Third artist", artwork: "https://unrelated.example.org/spoof.jpg")
            + BillboardFixtureNetwork.row(1, title: "First &amp; original", artist: "First artist")
            + BillboardFixtureNetwork.row(1, title: "Duplicate", artist: "Other")
            + BillboardFixtureNetwork.row(0, title: "Invalid", artist: "Other")
        let parsed = try await parse(client, "hot-100", rows: rows)
        XCTAssertEqual(parsed.entries.map(\.rank), [1, 3]); XCTAssertEqual(parsed.date, "2026-10-24")
        XCTAssertEqual(parsed.entries.first?.item.title, "First & original"); XCTAssertEqual(parsed.entries.last?.item.artwork, "")
        XCTAssertEqual(parsed.entries.first?.item.id, "track|catalog|billboard:hot-100:2026-10-24:1")
        let album = try await parse(client, "billboard-200", rows: BillboardFixtureNetwork.row(1, title: "Owned album", artist: "Owned artist"))
        guard let albumEntry = album.entries.first, case .album = albumEntry.item else { XCTFail("Album chart must retain its album kind"); return }
        let artist = try await parse(client, "artist-100", rows: BillboardFixtureNetwork.row(1, title: "Owned artist", artist: ""))
        XCTAssertTrue(artist.entries.first?.item.isArtist == true)
        for html in [BillboardFixtureNetwork.page("wrong-chart", rows: rows), BillboardFixtureNetwork.page("hot-100", rows: rows, date: "Not a chart date")] {
            do { _ = try await client.query("parse", arguments: ["chart": .string("hot-100"), "html": .string(html)], as: MusicBillboardRanking.self); XCTFail("Reject mismatched chart identity or missing date") }
            catch { }
        }
        let requests = await network.requests; XCTAssertTrue(requests.isEmpty, "Parsing and directory access must not contact any provider")
    }
    func testOriginalCacheRefreshEvictionAndFailedRequestRecoveryUseActualNativeHTTP() async throws {
        let scope = BillboardScope(), network = BillboardFixtureNetwork()
        let client = MusicBillboardClient(scope: scope.value, currentScope: { scope.value }, transport: MusicBillboardTransport(network: network))
        defer { client.dispose() }
        _ = try await client.ranking("hot-100"); _ = try await client.ranking("hot-100")
        var requests = await network.requests; XCTAssertEqual(requests.count, 1)
        _ = try await client.ranking("hot-100", refresh: true)
        requests = await network.requests; XCTAssertEqual(requests.count, 2)
        await network.failNext()
        do { _ = try await client.ranking("billboard-200"); XCTFail("Failed HTTP must not become an empty success") } catch { }
        _ = try await client.ranking("billboard-200")
        let charts = try MusicBillboardAsset.read().charts
        for chart in charts.prefix(17) { _ = try await client.ranking(chart.id) }
        let before = await network.requests.count
        _ = try await client.ranking("hot-100")
        requests = await network.requests; XCTAssertEqual(requests.count, before + 1, "The original cache evicts the first chart after sixteen distinct charts")
        XCTAssertTrue(requests.allSatisfy { $0.publicNetworkOnly && !$0.allowLocalNetwork && $0.maxResponseBytes == 8 * 1024 * 1024 })
    }
    func testOriginalAlbumResolverRequiresExactlyOneMatchingTitleAndArtist() async throws {
        let scope = BillboardScope(), network = BillboardFixtureNetwork(), albums = BillboardAlbumNetwork()
        let client = MusicBillboardClient(scope: scope.value, currentScope: { scope.value }, transport: MusicBillboardTransport(network: network))
        defer { client.dispose() }
        let catalog = MusicCatalogClient(network: albums)
        let item = MusicCatalogItem.album(.init(id: "billboard:album", connectorId: "catalog", title: "Owned Album", artist: "Owned Artist", artwork: ""))
        let resolved = try await client.resolve(item, catalog: catalog)
        XCTAssertEqual(resolved?.id, "album|catalog|deezer:album:42")
        await albums.setDuplicate()
        let ambiguous = try await client.resolve(item, catalog: catalog); XCTAssertNil(ambiguous)
        let wrongArtist = MusicCatalogItem.album(.init(id: "billboard:other", connectorId: "catalog", title: "Owned Album", artist: "Other Artist", artwork: ""))
        let wrong = try await client.resolve(wrongArtist, catalog: catalog); XCTAssertNil(wrong)
        let requests = await network.requests; XCTAssertTrue(requests.isEmpty)
    }
    func testUnrelatedHostsAndMethodsAreDeniedAndRetiredProfilesCannotPublishLateCharts() async throws {
        let scope = BillboardScope(), network = BillboardFixtureNetwork(), transport = MusicBillboardTransport(network: network)
        for (url, method) in [("https://127.0.0.1/private", "GET"), ("https://www.billboard.com/charts/hot-100/", "POST"), ("https://user@www.billboard.com/charts/hot-100/", "GET")] {
            do { _ = try await transport.perform(.http, payload: .object(["url": .string(url), "opts": .object(["method": .string(method)])])); XCTFail("Deny request before connecting") }
            catch let error as HarborError { XCTAssertEqual(error.code, "music-billboard-host") }
        }
        let denied = await network.requests; XCTAssertTrue(denied.isEmpty)
        let client = MusicBillboardClient(scope: scope.value, currentScope: { scope.value }, transport: transport)
        defer { client.dispose() }; await network.hold()
        let pending = Task { try await client.ranking("hot-100") }
        for _ in 0..<250 { if await network.requests.count > 0 { break }; try await Task.sleep(for: .milliseconds(20)) }
        let held = await network.requests; XCTAssertEqual(held.count, 1)
        scope.value = .init(owner: "other-billboard-profile", activation: UUID()); await network.release()
        do { _ = try await pending.value; XCTFail("An inactive profile must not publish the previous profile's chart") }
        catch is CancellationError { }
    }
    private func parse(_ client: MusicBillboardClient, _ chart: String, rows: String) async throws -> MusicBillboardRanking {
        try await client.query("parse", arguments: ["chart": .string(chart), "html": .string(BillboardFixtureNetwork.page(chart, rows: rows))], as: MusicBillboardRanking.self)
    }
}

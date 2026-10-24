import XCTest
@testable import Harbor

private actor ExploreFixtureNetwork: HarborNativeNetworkCalling {
    private(set) var requests: [HarborNetworkRequest] = []
    private var holding = false
    private var gate: CheckedContinuation<Void, Never>?
    func perform(_ request: HarborNetworkRequest) async throws -> HarborNetworkResponse {
        requests.append(request)
        if holding { await withCheckedContinuation { gate = $0 } }
        try Task.checkCancellation()
        let url = try XCTUnwrap(URLComponents(string: request.url))
        let index = url.queryItems?.first { $0.name == "index" }?.value
        let rows: [JSONValue] = index == "24" ? [Self.track(2), Self.track(3)] : index == "74" ? [Self.track(4)] : [Self.track(1), Self.track(1), Self.track(2), .object(["id": .integer(-1)])]
        let data = try JSONEncoder().encode(JSONValue.object(["data": .array(rows)]))
        return .init(status: 200, ok: true, headers: [:], bodyBase64: data.base64EncodedString(), url: request.url)
    }
    private static func track(_ id: Int) -> JSONValue {
        .object(["id": .integer(Int64(id)), "title": .string("Owned recording \(id)"), "duration": .integer(121), "position": .integer(Int64(id)), "rank": .integer(1000),
            "artist": .object(["id": .integer(10), "name": .string("Owned artist")]),
            "album": .object(["id": .integer(20), "title": .string("Owned album"), "cover_big": .string("https://example.org/owned-cover.jpg")])])
    }
    func hold() { holding = true }
    func waitUntilHeld() async throws {
        for _ in 0..<500 { if gate != nil { return }; try await Task.sleep(for: .milliseconds(20)) }
        throw HarborError(code: "owned-explore-gate")
    }
    func release() { holding = false; gate?.resume(); gate = nil }
}
@MainActor private final class ExploreScope {
    var value = PluginExecutionScope(owner: "owned-music-explore", activation: UUID())
}
@MainActor final class MusicExploreNativeTests: XCTestCase {
    func testActualPinnedWorkerKeepsEveryGenreIdentityAndFiltersAliasesLocalizedNamesAndCountries() async throws {
        let context = ExploreScope(), network = ExploreFixtureNetwork()
        let client = MusicExploreClient(scope: context.value, currentScope: { context.value }, transport: MusicExploreTransport(network: network))
        defer { client.dispose() }
        let asset = try MusicExploreAsset.read()
        let definitions = try await client.query("definitions", as: MusicExploreDefinitions.self)
        XCTAssertEqual(definitions.genres, asset.definitions.genres); XCTAssertEqual(asset.visibleGenres.count, 158)
        XCTAssertFalse(asset.visibleGenres.contains { $0.id == 95 }); XCTAssertEqual(definitions.families.count, 8)
        let alias = try await client.filter(.init(query: "G funk"), countryNames: [:], genreNames: [:])
        XCTAssertTrue(alias.contains { $0.id == 10126 })
        let localized = try await client.filter(.init(query: "nueva york"), countryNames: [:], genreNames: ["music.genre.new-york-drill": "Drill de Nueva York"])
        XCTAssertEqual(localized.map(\.id), [10117])
        let country = try await client.filter(.init(query: "japon", countries: ["JP"], family: "asia"), countryNames: ["JP": "Japón"], genreNames: [:])
        XCTAssertTrue(country.contains { $0.id == 10008 }); XCTAssertTrue(country.allSatisfy { $0.countries.contains("JP") && $0.family == "asia" })
        let calls = await network.requests; XCTAssertTrue(calls.isEmpty, "Genre filtering must not query the music provider")
    }
    func testActualDiscoveryWorkerCoalescesProviderCallsPreservesCreditsAndKeepsOriginalDepthOffsets() async throws {
        let context = ExploreScope(), network = ExploreFixtureNetwork()
        let client = MusicExploreClient(scope: context.value, currentScope: { context.value }, transport: MusicExploreTransport(network: network))
        defer { client.dispose() }
        let first = Task { try await client.selection(152) }, second = Task { try await client.selection(152) }
        let selection = try await first.value, repeated = try await second.value
        XCTAssertEqual(selection.tracks.map(\.id), ["deezer:track:1", "deezer:track:2"])
        XCTAssertEqual(selection.tracks, repeated.tracks); XCTAssertEqual(selection.positions, [1, 2])
        XCTAssertEqual(selection.artists.first?.id, "artist|catalog|deezer:artist:10")
        XCTAssertEqual(selection.albums?.first?.id, "album|catalog|deezer:album:20")
        XCTAssertTrue(selection.tracks.allSatisfy { $0.connectorId == "catalog" && $0.playbackUrl == nil })
        _ = try await client.tracks(152, page: 0); _ = try await client.tracks(152, page: 1)
        let requests = await network.requests
        XCTAssertEqual(requests.count, 3, "The repeated chart query uses the original pending/cache maps")
        XCTAssertTrue(requests[1].url.contains("index=24")); XCTAssertTrue(requests[2].url.contains("index=74"))
        XCTAssertTrue(requests.allSatisfy { $0.publicNetworkOnly && !$0.allowLocalNetwork })
    }
    func testOnlyAnonymousProviderGETRequestsRunAndRetiredScopeCannotPublishALateChart() async throws {
        let context = ExploreScope(), network = ExploreFixtureNetwork()
        let transport = MusicExploreTransport(network: network)
        do {
            _ = try await transport.perform(.http, payload: .object(["url": .string("https://127.0.0.1/private"), "opts": .object(["method": .string("GET")])]))
            XCTFail("An unrelated host must be rejected before any connection")
        } catch let error as HarborError { XCTAssertEqual(error.code, "music-explore-host") }
        let denied = await network.requests; XCTAssertTrue(denied.isEmpty)
        let client = MusicExploreClient(scope: context.value, currentScope: { context.value }, transport: MusicExploreTransport(network: network))
        defer { client.dispose() }; await network.hold()
        let pending = Task { try await client.selection(152) }
        try await network.waitUntilHeld(); context.value = .init(owner: "other-owned-profile", activation: UUID()); await network.release()
        do { _ = try await pending.value; XCTFail("An inactive profile cannot publish a late genre result") }
        catch is CancellationError { }
    }
}

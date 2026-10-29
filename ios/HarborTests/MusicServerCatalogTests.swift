import Foundation
import XCTest
@testable import Harbor

@MainActor final class MusicServerCatalogTests: XCTestCase {
    func testTypedFanOutRetainsDesktopInterleavingIdentityDeduplicationAndIndependentLimits() throws {
        let first = MusicCatalogSearch(top: nil, tracks: [track("a", " Same "), track("b", "Second")],
            albums: [.init(id: "a", connectorId: "catalog", title: " ALBUM ", artist: " Artist ", artwork: "")],
            artists: [.init(id: "a", connectorId: "catalog", name: " ARTIST ")],
            playlists: [.init(id: "a", connectorId: "catalog", name: " Mix ", artwork: [])])
        let second = MusicCatalogSearch(top: .track(track("top", "Top")), tracks: [track("c", "same"), track("d", "Fourth")],
            albums: [.init(id: "b", connectorId: "subsonic", title: "album", artist: "artist", artwork: "")],
            artists: [.init(id: "b", connectorId: "subsonic", name: "artist")],
            playlists: [.init(id: "b", connectorId: "subsonic", name: "mix", artwork: []), .init(id: "c", connectorId: "catalog", name: "MIX", artwork: [])])
        let merged = try MusicCatalogMerge.search([.success(first), .failure, .success(second)], limit: 3)
        XCTAssertEqual(merged.tracks.map(\.id), ["a", "b", "d"])
        XCTAssertEqual(merged.top?.title, "Top"); XCTAssertEqual(merged.albums.map(\.id), ["a"])
        XCTAssertEqual(merged.artists.map(\.id), ["a"]); XCTAssertEqual(merged.playlists.map(\.id), ["a", "b"])
        XCTAssertEqual(try MusicCatalogMerge.search([.success(first), .success(second)], limit: 1).tracks.map(\.id), ["a"])
        XCTAssertTrue(try MusicCatalogMerge.search([.success(first)], limit: 0).tracks.isEmpty)
        XCTAssertTrue(try MusicCatalogMerge.search([.failure, .success(empty)], limit: 2).tracks.isEmpty)
        XCTAssertThrowsError(try MusicCatalogMerge.search([.failure], limit: 2))
        XCTAssertThrowsError(try MusicCatalogMerge.search([.success(first), .cancelled], limit: 2)) { XCTAssertTrue($0 is CancellationError) }
    }
    func testCombinedHomeSettlesConcurrentlyRetainsGoodSourcesAndCancelsItsBrowseBudget() async throws {
        let owner = ServerCatalogOwner(), disk = ServerCatalogDisk(); disk.pairing = pair
        let wire = ServerCatalogWire { request in
            try await Task.sleep(for: .milliseconds(15))
            if request.url?.lastPathComponent == "getAlbumList2" {
                return try Self.response(["albumList2": .object(["album": .array([.object(["id": .string("owned-album"), "name": .string("Server album")])])])])
            }
            return try Self.response([:])
        }
        let service = makeService(owner, disk: disk, wire: wire), catalog = ServerCatalogPublic()
        let client = MusicServerCatalogClient(server: service, catalog: catalog, currentScope: { owner.scope })
        await catalog.setHome([row("public", "catalog"), row("subsonic:home:newest", "catalog")])
        await catalog.setDelay(.milliseconds(80))
        let loading = Task { try await client.home() }
        try await wire.waitForRequest()
        let publicStarted = await catalog.homeCalls; XCTAssertEqual(publicStarted, 1)
        let publicFinished = await catalog.homeCompleted; XCTAssertEqual(publicFinished, 0, "Private requests start while public discovery is still waiting")
        let rows = try await loading.value
        XCTAssertEqual(rows.map(\.id), ["public", "subsonic:home:newest", "subsonic:home:frequent", "subsonic:home:random"])
        XCTAssertEqual(rows[1].source, "catalog", "The first source-ranked row owns a duplicate id")
        await catalog.setDelay(.zero)
        await catalog.setFail(true)
        let partial = try await client.home(); XCTAssertEqual(partial.count, 3)
        try service.disconnect()
        let none = try await client.home(); XCTAssertTrue(none.isEmpty)
        await catalog.setFail(false); await catalog.setDelay(.seconds(5))
        let bounded = MusicServerCatalogClient(server: service, catalog: catalog, browseTimeout: .milliseconds(20), currentScope: { owner.scope })
        let start = ContinuousClock.now
        let timed = try await bounded.home(); XCTAssertTrue(timed.isEmpty)
        XCTAssertLessThan(start.duration(to: ContinuousClock.now), .seconds(2), "The slow public request must actually observe cancellation")
    }
    func testPrivateAlbumPlaylistAndArtistRoutesCannotFallBackToAnonymousCatalog() async throws {
        let owner = ServerCatalogOwner(), disk = ServerCatalogDisk(); disk.pairing = pair
        let wire = ServerCatalogWire { request in
            switch request.url?.lastPathComponent {
            case "getAlbum", "getPlaylist": return try Self.response([request.url?.lastPathComponent == "getAlbum" ? "album" : "playlist": .object(["song": .array([]), "entry": .array([])])])
            case "getArtist": return try Self.response(["artist": .object(["album": .array([])])])
            default: return try Self.response(["searchResult3": .object(["song": .array([.object(["id": .string("server-song"), "title": .string("Private song")])])])])
            }
        }
        let service = makeService(owner, disk: disk, wire: wire), publicClient = ServerCatalogPublic()
        let client = MusicServerCatalogClient(server: service, catalog: publicClient, currentScope: { owner.scope })
        let album = MusicCatalogAlbum(id: "subsonic:album", connectorId: "subsonic", title: "Private", artist: "", artwork: "")
        let artist = MusicCatalogArtist(id: "subsonic:artist", connectorId: "subsonic", name: "Private")
        let playlist = MusicCatalogPlaylist(id: "subsonic:playlist", connectorId: "subsonic", name: "Private", artwork: [])
        _ = try await client.albumTracks(album); _ = try await client.playlistTracks(playlist); _ = try await client.artistTop(artist)
        let rows = try await client.artistRows(artist), albums = try await client.artistCatalog(artist, kind: .albums, cursor: nil)
        XCTAssertTrue(rows.isEmpty); XCTAssertTrue(albums.items.isEmpty); XCTAssertEqual(albums.scope, .limited)
        let top = try await client.artistCatalog(artist, kind: .tracks, cursor: nil); XCTAssertTrue(top.items.isEmpty)
        do { _ = try await client.artistCatalog(artist, kind: .tracks, cursor: "again"); XCTFail("Source default cannot invent pagination") } catch { }
        let privateCalls = await publicClient.detailCalls; XCTAssertEqual(privateCalls, 0)
        let combined = try await client.search("song", limit: 2); XCTAssertEqual(combined.tracks.map(\.id), ["public-song", "subsonic:server-song"])
        let requests = await wire.requests; XCTAssertTrue(requests.allSatisfy { URLComponents(url: $0.url!, resolvingAgainstBaseURL: false)?.queryItems?.contains(where: { $0.name == "t" }) == true })
        try service.disconnect()
        let count = await wire.requests.count
        do { _ = try await client.albumTracks(album); XCTFail("Disconnected private items cannot be sent to a public metadata API") } catch { }
        let after = await wire.requests.count, details = await publicClient.detailCalls
        XCTAssertEqual(after, count); XCTAssertEqual(details, 0)
        _ = try await client.search("public", limit: 2)
        let still = await wire.requests.count; XCTAssertEqual(still, count)
    }
    func testProfileAndCredentialDeparturesRejectLatePublicRepliesAndInvalidateCombinedCaches() async throws {
        let owner = ServerCatalogOwner(), disk = ServerCatalogDisk(), gate = ServerCatalogGate()
        let wire = ServerCatalogWire { _ in try Self.response([:]) }
        let service = makeService(owner, disk: disk, wire: wire), publicClient = ServerCatalogPublic(gate: gate)
        let client = MusicServerCatalogClient(server: service, catalog: publicClient, currentScope: { owner.scope })
        let late = Task { try await client.search("held", limit: 2) }
        try await gate.waitForHold(); owner.scope = .init(owner: "other-owner", activation: UUID()); await gate.release()
        do { _ = try await late.value; XCTFail("A late anonymous reply cannot revive a departed private catalog route") } catch is CancellationError { }
        let nextOwner = ServerCatalogOwner(), nextService = makeService(nextOwner, disk: disk, wire: wire)
        let plain = ServerCatalogPublic(); await plain.setHome([row("public", "catalog"), row("private", "subsonic")])
        let model = MusicCatalogModel(client: plain)
        await model.load(query: "", debounce: false); XCTAssertEqual(model.rows.count, 2)
        await model.load(query: "cached", debounce: false); XCTAssertNotNil(model.result)
        model.invalidatePrivateServer(); XCTAssertEqual(model.rows.map(\.id), ["public"]); XCTAssertNil(model.result); XCTAssertFalse(model.hasRequested)
        await model.load(query: "cached", debounce: false)
        let searches = await plain.searchCalls; XCTAssertEqual(searches, 2, "The combined private search cache must be discarded")
        let nextClient = MusicServerCatalogClient(server: nextService, catalog: plain, currentScope: { nextOwner.scope })
        nextService.dispose()
        do { _ = try await nextClient.home(); XCTFail("A disposed service cannot admit a new route") } catch is CancellationError { }
    }
    func testConnectionFormClosesWithoutSavingLateCredentialsAndRetainsFailedDisconnectState() async throws {
        let owner = ServerCatalogOwner(), disk = ServerCatalogDisk(), gate = ServerCatalogGate()
        let wire = ServerCatalogWire { request in
            if request.url?.lastPathComponent == "login" { await gate.hold(); return .init(status: 404, data: Data()) }
            return try Self.response([:])
        }
        let service = makeService(owner, disk: disk, wire: wire), model = MusicServerConnectionModel(service: service)
        XCTAssertTrue(model.incomplete); model.address = "https://owned.example.test"; model.username = "listener"; model.password = "owned-private-password"
        let connecting = Task { await model.connect() }; try await gate.waitForHold(); XCTAssertTrue(model.busy)
        model.close(); await gate.release(); let saved = await connecting.value
        XCTAssertFalse(saved); XCTAssertFalse(model.busy); XCTAssertNil(disk.pairing); XCTAssertNil(model.failure)
        XCTAssertTrue(model.password.isEmpty && model.address.isEmpty && model.username.isEmpty)
        model.address = "https://owned.example.test"; model.username = "listener"; model.password = "new-owned-password"
        let success = await model.connect(); XCTAssertTrue(success); XCTAssertNotNil(disk.pairing); XCTAssertTrue(model.password.isEmpty)
        disk.failWrite = true; XCTAssertFalse(model.disconnect()); XCTAssertNotNil(service.pairing); XCTAssertNotNil(model.failure)
        disk.failWrite = false; XCTAssertTrue(model.disconnect()); XCTAssertNil(service.pairing); XCTAssertNil(model.failure)
    }
    func testAllNewConnectionAndServerRowLabelsResolveInTheSixteenNativeLanguageBundles() throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "music-server-catalog-reference", withExtension: "json", subdirectory: "Fixtures"))
        let fixture = try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: url))
        XCTAssertEqual(fixture["reference"].string, "0834340cec5531650bfe78cd628628702e636987")
        XCTAssertEqual(fixture["languages"].array.count, 16); XCTAssertEqual(fixture["keys"].array.count, 23)
        var comparisons = 0
        for language in fixture["languages"].array {
            let code = try XCTUnwrap(language["code"].string)
            for (key, value) in language["expected"].objectValue {
                let expected = try XCTUnwrap(value.string)
                XCTAssertEqual(DesktopInterfaceText.value(key, language: code), expected, code + ": " + key); comparisons += 1
            }
        }
        XCTAssertEqual(comparisons, 368)
    }
    private var pair: SubsonicPairing { .salted(baseUrl: "https://owned.example.test", username: "listener", password: "owned", salt: "owned-salt") }
    private var empty: MusicCatalogSearch { .init(top: nil, tracks: [], albums: [], artists: [], playlists: []) }
    private func makeService(_ owner: ServerCatalogOwner, disk: ServerCatalogDisk, wire: ServerCatalogWire) -> SubsonicMusicService {
        .init(scope: owner.scope, currentScope: { owner.scope }, transport: wire, persistence: disk)
    }
    private func track(_ id: String, _ title: String) -> MusicTrack { Self.song(id, title) }
    nonisolated static func song(_ id: String, _ title: String) -> MusicTrack {
        .init(id: id, connectorId: "catalog", sourceId: id, playbackUrl: nil, title: title, artist: "Artist", album: nil, artwork: "", durationSeconds: 10, durationLabel: "0:10")
    }
    private func row(_ id: String, _ source: String) -> MusicCatalogRow { .init(id: id, title: id, titleLiteral: true, subtitle: nil, layout: .covers, source: source, items: []) }
    nonisolated static func response(_ supplied: [String: JSONValue]) throws -> MusicServiceHTTPResponse {
        .init(status: 200, data: try JSONEncoder().encode(JSONValue.object(["subsonic-response": .object(["status": .string("ok")].merging(supplied) { _, new in new })])))
    }
}
@MainActor private final class ServerCatalogOwner { var scope = PluginExecutionScope(owner: "server-catalog-" + UUID().uuidString, activation: UUID()) }
@MainActor private final class ServerCatalogDisk: SubsonicPairingPersistence {
    var pairing: SubsonicPairing?, failWrite = false
    func read(owner: String) throws -> SubsonicPairing? { pairing }
    func write(_ pairing: SubsonicPairing, owner: String) throws { if failWrite { throw SubsonicMusicError.storage }; self.pairing = pairing }
    func remove(owner: String) throws { if failWrite { throw SubsonicMusicError.storage }; pairing = nil }
}
private actor ServerCatalogWire: MusicServiceHTTPTransport {
    let reply: @Sendable (URLRequest) async throws -> MusicServiceHTTPResponse
    private(set) var requests: [URLRequest] = []
    init(_ reply: @escaping @Sendable (URLRequest) async throws -> MusicServiceHTTPResponse) { self.reply = reply }
    func perform(_ request: URLRequest) async throws -> MusicServiceHTTPResponse { requests.append(request); return try await reply(request) }
    func waitForRequest() async throws { for _ in 0..<200 { if !requests.isEmpty { return }; try await Task.sleep(for: .milliseconds(10)) }; throw SubsonicMusicError.network }
}
private actor ServerCatalogGate {
    private var pending: CheckedContinuation<Void, Never>?
    private var first = true
    func hold() async { guard first else { return }; first = false; await withCheckedContinuation { pending = $0 } }
    func waitForHold() async throws { for _ in 0..<200 { if pending != nil { return }; try await Task.sleep(for: .milliseconds(10)) }; throw SubsonicMusicError.network }
    func release() { pending?.resume(); pending = nil }
}
private actor ServerCatalogPublic: MusicCatalogCalling {
    private var rows: [MusicCatalogRow] = [], fail = false, delay: Duration = .zero
    private let gate: ServerCatalogGate?
    private(set) var homeCalls = 0, homeCompleted = 0, detailCalls = 0, searchCalls = 0
    init(gate: ServerCatalogGate? = nil) { self.gate = gate }
    func setHome(_ rows: [MusicCatalogRow]) { self.rows = rows }
    func setFail(_ value: Bool) { fail = value }
    func setDelay(_ value: Duration) { delay = value }
    func home() async throws -> [MusicCatalogRow] { homeCalls += 1; if fail { throw SubsonicMusicError.network }; try await Task.sleep(for: delay); homeCompleted += 1; return rows }
    func search(_ query: String, limit: Int) async throws -> MusicCatalogSearch {
        searchCalls += 1; await gate?.hold(); if fail { throw SubsonicMusicError.network }
        return .init(top: nil, tracks: [MusicServerCatalogTests.song("public-song", "Public song")], albums: [], artists: [], playlists: [])
    }
    func albumTracks(_ album: MusicCatalogAlbum) async throws -> [MusicTrack] { detailCalls += 1; return [] }
    func artistTop(_ artist: MusicCatalogArtist) async throws -> [MusicTrack] { detailCalls += 1; return [] }
    func artistRows(_ artist: MusicCatalogArtist) async throws -> [MusicCatalogRow] { detailCalls += 1; return [] }
    func artistCatalog(_ artist: MusicCatalogArtist, kind: MusicCatalogKind, cursor: String?) async throws -> MusicCatalogPage { detailCalls += 1; return .init(items: [], nextCursor: nil, total: nil, scope: .catalog) }
    func playlistTracks(_ playlist: MusicCatalogPlaylist) async throws -> [MusicTrack] { detailCalls += 1; return [] }
}

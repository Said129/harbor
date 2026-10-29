import Foundation
import XCTest
@testable import Harbor

@MainActor final class SubsonicMusicServiceTests: XCTestCase {
    func testPublishedTokenURLFormsSourceIdentifiersAndStrictEnvelopeDefaults() throws {
        XCTAssertEqual(try SubsonicPairing.bases(" music.example.test/ "), ["https://music.example.test","http://music.example.test","http://music.example.test:4533"])
        XCTAssertEqual(try SubsonicPairing.bases("music.example.test:8080"), ["https://music.example.test:8080","http://music.example.test:8080"])
        XCTAssertEqual(try SubsonicPairing.bases("http://192.168.1.4:4533/music/"), ["http://192.168.1.4:4533/music"])
        XCTAssertThrowsError(try SubsonicPairing.bases("ftp://music.example.test")); XCTAssertThrowsError(try SubsonicPairing.bases("   "))
        let pair = SubsonicPairing.salted(baseUrl: "https://music.example.test", username: "a+b space", password: "sesame", salt: "c19b2d")
        XCTAssertEqual(pair.token, "26719a1196d2a940705a59634eb18eab")
        let stream = try pair.endpoint("stream", parameters: [("id","mf-1"),("format","raw")])
        let query = Self.parameters(stream)
        XCTAssertEqual(query["u"], pair.username); XCTAssertEqual(query["t"], pair.token)
        XCTAssertEqual(query["v"], "1.16.1"); XCTAssertEqual(query["c"], "Harbor"); XCTAssertEqual(query["format"], "raw"); XCTAssertNil(query["f"])
        XCTAssertTrue(stream.absoluteString.contains("u=a%2Bb+space"))
        let cover = try XCTUnwrap(URL(string: pair.cover("al-1_9f3c")))
        XCTAssertEqual(Self.parameters(cover)["size"], "512"); XCTAssertNil(Self.parameters(cover)["f"])
        XCTAssertEqual(try SubsonicPairing.safeID(" subsonic:mf-1 "), "mf-1")
        for id in ["", "has space", "á", String(repeating: "a", count: 129)] { XCTAssertThrowsError(try SubsonicPairing.safeID(id)) }
        let empty = try JSONDecoder().decode(SubsonicEnvelope.self, from: Self.response([:]).data).response
        XCTAssertEqual(empty.status, "ok"); XCTAssertNil(empty.album)
        let child = try JSONDecoder().decode(SubsonicSong.self, from: Data(#"{"id":"mf-1"}"#.utf8)).recording(pair)
        XCTAssertEqual(child.id, "subsonic:mf-1"); XCTAssertEqual(child.title, ""); XCTAssertEqual(child.artist, "")
        XCTAssertEqual(child.durationLabel, "0:00"); XCTAssertNil(child.playbackUrl); XCTAssertNil(child.mediaKind)
        XCTAssertThrowsError(try JSONDecoder().decode(SubsonicSong.self, from: Data(#"{"id":"mf-1","title":null}"#.utf8)))
        XCTAssertThrowsError(try JSONDecoder().decode(SubsonicEnvelope.self, from: Data(#"{"subsonic-response":{"status":"ok","album":{"song":null}}}"#.utf8)))
    }
    func testNavidromeTokenExchangePingsBeforeOwnerScopedPersistenceAndDisconnectIsAtomic() async throws {
        let disk = OwnedSubsonicPairings(), state = OwnedSubsonicScope("exchange")
        let transport = OwnedSubsonicTransport { request in
            if request.url?.lastPathComponent == "login" {
                return .init(status: 200, data: try JSONEncoder().encode(["username":"canonical","subsonicSalt":"exchange-salt","subsonicToken":String(repeating: "a", count: 32)]))
            }
            return try Self.response([:])
        }
        let service = client(state, disk: disk, transport: transport)
        try await service.connect(address: "https://music.example.test/", username: "  original  ", password: " owned password ")
        let saved = try XCTUnwrap(disk.values[state.value.owner]); XCTAssertEqual(saved.username, "canonical"); XCTAssertEqual(saved.salt, "exchange-salt")
        XCTAssertFalse(String(decoding: try JSONEncoder().encode(saved), as: UTF8.self).contains("owned password"))
        let requests = await transport.captured()
        XCTAssertEqual(requests.map { $0.url?.lastPathComponent ?? "" }, ["login","ping"])
        XCTAssertEqual(requests[0].httpMethod, "POST"); XCTAssertEqual(requests[1].httpMethod, "GET")
        XCTAssertEqual(requests[0].value(forHTTPHeaderField: "User-Agent"), "Harbor/1.0")
        let login = try JSONDecoder().decode([String:String].self, from: XCTUnwrap(requests[0].httpBody))
        XCTAssertEqual(login["username"], "original"); XCTAssertEqual(login["password"], " owned password ")
        XCTAssertEqual(Self.parameters(try XCTUnwrap(requests[1].url))["f"], "json")
        XCTAssertTrue(client(state, disk: disk, transport: transport).configured)
        XCTAssertFalse(client(OwnedSubsonicScope("other"), disk: disk, transport: transport).configured)
        disk.failWrite = true; XCTAssertThrowsError(try service.disconnect()); XCTAssertEqual(service.pairing, saved); XCTAssertEqual(disk.values[state.value.owner], saved)
        disk.failWrite = false; try service.disconnect(); XCTAssertNil(service.pairing); XCTAssertNil(disk.values[state.value.owner]); XCTAssertEqual(service.connectionStatus, "disconnected")
    }
    func testSaltedFallbackRetainsOldPairingWhenPingOrStorageFails() async throws {
        let disk = OwnedSubsonicPairings(), state = OwnedSubsonicScope("fallback")
        let previous = Self.pairing; disk.values[state.value.owner] = previous
        let transport = OwnedSubsonicTransport { request in
            if request.url?.lastPathComponent == "login" { return .init(status: 404, data: Data()) }
            return try Self.response([:])
        }
        let service = client(state, disk: disk, transport: transport)
        disk.failWrite = true
        do { try await service.connect(address: "https://new.example.test", username: "alice", password: "sesame"); XCTFail("A failed credential write must not publish the pairing") } catch { }
        XCTAssertEqual(service.pairing, previous); XCTAssertEqual(disk.values[state.value.owner], previous)
        disk.failWrite = false
        try await service.connect(address: "https://new.example.test", username: "alice", password: "sesame")
        XCTAssertEqual(service.pairing?.token, "26719a1196d2a940705a59634eb18eab"); XCTAssertEqual(service.pairing?.baseUrl, "https://new.example.test")
        let rejected = OwnedSubsonicTransport { request in
            if request.url?.lastPathComponent == "login" { return .init(status: 404, data: Data()) }
            return try Self.response(["status":.string("failed"),"error":.object(["code":.integer(40),"message":.string("owned rejection")])])
        }
        let failed = client(state, disk: disk, transport: rejected), baseline = failed.pairing
        do { try await failed.connect(address: "https://rejected.example.test", username: "alice", password: "sesame"); XCTFail("Ping must complete before saving credentials") } catch { XCTAssertTrue(error.localizedDescription.contains("Connect it again")) }
        XCTAssertEqual(failed.pairing, baseline); XCTAssertEqual(disk.values[state.value.owner], baseline)
    }
    func testOriginalHomePartialFailureSearchAlbumOrderArtistFanoutAndPlaylistOrder() async throws {
        let disk = OwnedSubsonicPairings(), state = OwnedSubsonicScope("catalog"); disk.values[state.value.owner] = Self.pairing
        let transport = OwnedSubsonicTransport { request in
            try await Task.sleep(for: .milliseconds(30))
            let method = request.url?.lastPathComponent ?? "", query = request.url.map(Self.parameters) ?? [:]
            switch method {
            case "getAlbumList2":
                if query["type"] == "frequent" { return .init(status: 503, data: Data()) }
                return try Self.response(["albumList2":.object(["album":.array([Self.album(query["type"] ?? "")])])])
            case "getStarred2": return try Self.response(["starred2":.object(["song":.array((0..<25).map { Self.song("star-\($0)") })])])
            case "getArtists": return try Self.response(["artists":.object(["index":.array([.object(["artist":.array((0..<26).map { .object(["id":.string("artist-\($0)"),"name":.string("Owned artist")]) })])])])])
            case "getPlaylists": return try Self.response(["playlists":.object(["playlist":.array((0..<25).map { .object(["id":.string("list-\($0)"),"name":.string("Owned list")]) })])])
            case "getArtist": return try Self.response(["artist":.object(["album":.array((1...5).map { Self.album("a\($0)") })])])
            case "getAlbum":
                if query["id"] == "a2" { return .init(status: 500, data: Data()) }
                let songs = query["id"] == "a3" ? (0..<35).map { Self.song("long-\($0)") } : [Self.song("disc-two", disc: 2, track: 1),Self.song("disc-one-last", disc: 1, track: 9),Self.song("disc-one-first", disc: 1, track: 1)]
                return try Self.response(["album":.object(["song":.array(songs)])])
            case "getPlaylist": return try Self.response(["playlist":.object(["entry":.array([Self.song("z", disc: 2, track: 9),Self.song("a", disc: 1, track: 1)])])])
            case "search3": return try Self.response(["searchResult3":.object(["song":.array([Self.song("found")]),"album":.array([Self.album("found-album")]),"artist":.array([.object(["id":.string("found-artist"),"name":.string("Artist")])])])])
            default: return try Self.response([:])
            }
        }
        let service = client(state, disk: disk, transport: transport), rows = try await service.home()
        XCTAssertEqual(rows.map(\.id), ["newest","random","starred","artists","playlists"].map { "subsonic:home:" + $0 })
        XCTAssertEqual(rows.suffix(3).map { $0.items.count }, [24,24,24]); XCTAssertEqual(service.health, .healthy)
        let parallel = await transport.maximum(); XCTAssertGreaterThan(parallel, 1); XCTAssertLessThanOrEqual(parallel, 6)
        let album = MusicCatalogAlbum(id: "subsonic:one", connectorId: "subsonic", title: "", artist: "", artwork: "")
        let songs = try await service.albumTracks(album); XCTAssertEqual(songs.map(\.id), ["subsonic:disc-one-first","subsonic:disc-one-last","subsonic:disc-two"])
        let artist = MusicCatalogArtist(id: "artist", connectorId: "subsonic", name: "Owned")
        let top = try await service.artistTop(artist); XCTAssertEqual(top.count, 30); XCTAssertEqual(top.first?.id, "subsonic:disc-one-first")
        let playlist = MusicCatalogPlaylist(id: "list", connectorId: "subsonic", name: "Owned", artwork: [])
        let entries = try await service.playlistTracks(playlist); XCTAssertEqual(entries.map(\.id), ["subsonic:z","subsonic:a"])
        let search = try await service.search("  Owned  ", limit: 200); XCTAssertEqual(search.tracks.first?.id, "subsonic:found"); XCTAssertEqual(search.albums.count, 1); XCTAssertEqual(search.artists.count, 1)
        let found = try await service.searchTracks("Owned", limit: 7); XCTAssertEqual(found.count, 1)
        let stream = try await service.resolve(found[0]); XCTAssertEqual(Self.parameters(stream.url)["format"], "raw"); XCTAssertNil(Self.parameters(stream.url)["f"])
        let submitted = try await service.submitScrobble(found[0], startedAtSeconds: 2); XCTAssertTrue(submitted)
        let saturated = try await service.submitScrobble(found[0], startedAtSeconds: .max); XCTAssertTrue(saturated)
        let requests = await transport.captured(), albumIDs = requests.filter { $0.url?.lastPathComponent == "getAlbum" }.compactMap { $0.url.map(Self.parameters)?["id"] }
        XCTAssertFalse(albumIDs.contains("a5"))
        let searchQueries = requests.filter { $0.url?.lastPathComponent == "search3" }.compactMap { $0.url.map(Self.parameters) }
        XCTAssertEqual(searchQueries.first?["songCount"], "100"); XCTAssertEqual(searchQueries.last?["artistCount"], "0"); XCTAssertEqual(searchQueries.last?["songCount"], "7")
        XCTAssertTrue(requests.contains { $0.url.map(Self.parameters)?["time"] == "2000" })
        XCTAssertTrue(requests.contains { $0.url.map(Self.parameters)?["time"] == String(UInt64.max) })
    }
    func testLatePairingAndSearchCannotPublishAfterProfileOrCredentialReplacement() async throws {
        let disk = OwnedSubsonicPairings(), state = OwnedSubsonicScope("late-auth"), held = HeldSubsonicTransport()
        let service = client(state, disk: disk, transport: held)
        let login = Task { try await service.connect(address: "https://owned.example.test", username: "alice", password: "owned") }
        try await held.wait(); state.value = .init(owner: "other-profile", activation: UUID())
        await held.release(.init(status: 200, data: try JSONEncoder().encode(["subsonicSalt":"owned-salt","subsonicToken":String(repeating: "a", count: 32)])))
        do { try await login.value; XCTFail("A retired profile must not finish pairing") } catch is CancellationError { }
        XCTAssertTrue(disk.values.isEmpty); XCTAssertNil(service.pairing)
        let next = OwnedSubsonicScope("late-search"), searchHeld = HeldSubsonicTransport(); disk.values[next.value.owner] = Self.pairing
        let searchService = client(next, disk: disk, transport: searchHeld)
        let search = Task { try await searchService.searchTracks("Owned") }; try await searchHeld.wait(); try searchService.disconnect()
        await searchHeld.release(try Self.response(["searchResult3":.object(["song":.array([Self.song("late")])])]))
        do { _ = try await search.value; XCTFail("A disconnected source cannot publish a late search") } catch is CancellationError { }
        XCTAssertNil(searchService.pairing); XCTAssertEqual(searchService.health, .unknown)
    }
    func testRealOwnerKeychainReopensWithoutPasswordAndFailedResponsesKeepPairing() async throws {
        let state = OwnedSubsonicScope("keychain-" + UUID().uuidString), persistence = KeychainSubsonicPairing()
        defer { try? persistence.remove(owner: state.value.owner) }
        try persistence.write(Self.pairing, owner: state.value.owner)
        let transport = OwnedSubsonicTransport { request in
            let query = request.url.map(Self.parameters) ?? [:]
            if query["query"] == "offline" { throw URLError(.notConnectedToInternet) }
            if query["query"] == "rejected" { return try Self.response(["status":.string("failed"),"error":.object(["code":.integer(41),"message":.string("ignored network text")])]) }
            return try Self.response([:])
        }
        let service = SubsonicMusicService(scope: state.value, currentScope: { state.value }, transport: transport, persistence: persistence)
        XCTAssertEqual(service.pairing, Self.pairing)
        do { _ = try await service.searchTracks("offline"); XCTFail("Offline requests must fail") } catch { }
        XCTAssertEqual(service.health, .offline); XCTAssertEqual(service.connectionStatus, "error"); XCTAssertEqual(service.pairing, Self.pairing)
        do { _ = try await service.searchTracks("rejected"); XCTFail("Authentication failures must fail") } catch { XCTAssertTrue(error.localizedDescription.contains("Connect it again")) }
        XCTAssertEqual(service.health, .degraded); XCTAssertEqual(service.connectionStatus, "connected")
        _ = try await service.searchTracks("recovered"); XCTAssertEqual(service.health, .healthy)
        XCTAssertEqual(try persistence.read(owner: state.value.owner), Self.pairing)
    }
    private func client(_ state: OwnedSubsonicScope, disk: OwnedSubsonicPairings, transport: any MusicServiceHTTPTransport) -> SubsonicMusicService {
        .init(scope: state.value, currentScope: { state.value }, transport: transport, persistence: disk, newSalt: { "c19b2d" })
    }
    nonisolated private static var pairing: SubsonicPairing { .salted(baseUrl: "https://music.example.test", username: "alice", password: "sesame", salt: "c19b2d") }
    nonisolated private static func parameters(_ url: URL) -> [String:String] {
        let pairs = (URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedQuery ?? "").split(separator: "&").compactMap { item -> (String,String)? in
            let pair = item.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false); guard pair.count == 2 else { return nil }
            return (String(pair[0]).replacingOccurrences(of: "+", with: " ").removingPercentEncoding ?? "",String(pair[1]).replacingOccurrences(of: "+", with: " ").removingPercentEncoding ?? "")
        }
        return Dictionary(pairs, uniquingKeysWith: { _,last in last })
    }
    nonisolated private static func response(_ supplied: [String:JSONValue]) throws -> MusicServiceHTTPResponse {
        var body = supplied; if body["status"] == nil { body["status"] = .string("ok") }
        return .init(status: 200, data: try JSONEncoder().encode(JSONValue.object(["subsonic-response":.object(body)])))
    }
    nonisolated private static func song(_ id: String, disc: Int = 1, track: Int = 0) -> JSONValue {
        .object(["id":.string(id),"title":.string("Owned song"),"artist":.string("Owned artist"),"duration":.integer(182),"discNumber":.integer(Int64(disc)),"track":.integer(Int64(track))])
    }
    nonisolated private static func album(_ id: String) -> JSONValue { .object(["id":.string(id),"name":.string("Owned album")]) }
}
@MainActor private final class OwnedSubsonicScope {
    var value: PluginExecutionScope
    init(_ owner: String) { value = .init(owner: "owned-subsonic-" + owner, activation: UUID()) }
}
@MainActor private final class OwnedSubsonicPairings: SubsonicPairingPersistence {
    var values: [String:SubsonicPairing] = [:]
    var failWrite = false
    func read(owner: String) throws -> SubsonicPairing? { values[owner] }
    func write(_ pairing: SubsonicPairing, owner: String) throws { if failWrite { throw SubsonicMusicError.storage }; values[owner] = pairing }
    func remove(owner: String) throws { if failWrite { throw SubsonicMusicError.storage }; values[owner] = nil }
}
private actor OwnedSubsonicTransport: MusicServiceHTTPTransport {
    let handler: @Sendable (URLRequest) async throws -> MusicServiceHTTPResponse
    var requests: [URLRequest] = []; var active = 0, maximumActive = 0
    init(_ handler: @escaping @Sendable (URLRequest) async throws -> MusicServiceHTTPResponse) { self.handler = handler }
    func perform(_ request: URLRequest) async throws -> MusicServiceHTTPResponse {
        requests.append(request); active += 1; maximumActive = max(maximumActive,active); defer { active -= 1 }
        return try await handler(request)
    }
    func captured() -> [URLRequest] { requests }
    func maximum() -> Int { maximumActive }
}
private actor HeldSubsonicTransport: MusicServiceHTTPTransport {
    var started = false, pending: CheckedContinuation<MusicServiceHTTPResponse,Never>?
    func perform(_ request: URLRequest) async throws -> MusicServiceHTTPResponse { started = true; return await withCheckedContinuation { pending = $0 } }
    func wait() async throws { for _ in 0..<200 { if started { return }; try await Task.sleep(for: .milliseconds(10)) }; throw SubsonicMusicError.network }
    func release(_ response: MusicServiceHTTPResponse) { pending?.resume(returning: response); pending = nil }
}

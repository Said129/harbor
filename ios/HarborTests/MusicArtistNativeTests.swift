import XCTest
@testable import Harbor

private actor ArtistFixtureNetwork: HarborNativeNetworkCalling {
    struct Observation: Sendable { let host: String; let path: String; let offset: String?; let key: String?; let date: Date; let publicOnly: Bool }
    private(set) var observations: [Observation] = []
    private var holding = false
    private var gates: [CheckedContinuation<Void, Never>] = []
    static let artistID = "11111111-1111-4111-8111-111111111111"
    static let recordingID = "22222222-2222-4222-8222-222222222222"
    static let workID = "33333333-3333-4333-8333-333333333333"
    func hold() { holding = true }
    func release() { holding = false; let values = gates; gates = []; values.forEach { $0.resume() } }
    func perform(_ request: HarborNetworkRequest) async throws -> HarborNetworkResponse {
        let url = try XCTUnwrap(URLComponents(string: request.url)), path = url.path
        let query = Dictionary((url.queryItems ?? []).map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { first, _ in first })
        observations.append(.init(host: url.host ?? "", path: path, offset: query["offset"], key: query["api_key"], date: Date(), publicOnly: request.publicNetworkOnly && !request.allowLocalNetwork))
        if holding { await withCheckedContinuation { gates.append($0) } }
        try Task.checkCancellation()
        let body: String
        if path == "/ws/2/artist" {
            body = query["offset"] == "0"
                ? "{\"count\":4,\"artists\":[{\"id\":\"\(Self.artistID)\",\"name\":\" Owned Artist \"},{\"id\":\"invalid\",\"name\":\"Invalid\"},{\"id\":\"\(Self.workID)\",\"name\":\"Other Artist\"}]}"
                : "{\"count\":4,\"artists\":[{\"id\":\"\(Self.recordingID)\",\"name\":\"Last Artist\"}]}"
        } else if path == "/track/77" || path == "/track/isrc:USOWN2600001" { body = Self.recording }
        else if path.hasPrefix("/track/") { body = Self.recording }
        else if path.hasPrefix("/ws/2/isrc/") {
            body = "{\"isrc\":\"USOWN2600001\",\"recordings\":[{\"id\":\"\(Self.recordingID)\",\"title\":\"Owned Song\",\"length\":180000,\"artist-credit\":[{\"artist\":{\"name\":\"Owned Artist\"}}]}]}"
        } else if path.hasPrefix("/ws/2/recording/") {
            body = "{\"id\":\"\(Self.recordingID)\",\"title\":\"Owned Song\",\"length\":180000,\"isrcs\":[\"USOWN2600001\"],\"artist-credit\":[{\"artist\":{\"name\":\"Owned Artist\"}}],\"relations\":[{\"type\":\"producer\",\"artist\":{\"id\":\"\(Self.artistID)\",\"name\":\"Owned Producer\"},\"attributes\":[\"executive\"]},{\"type\":\"performance\",\"work\":{\"id\":\"\(Self.workID)\",\"title\":\"Owned Composition\",\"relations\":[{\"type\":\"composer\",\"artist\":{\"id\":\"\(Self.workID)\",\"name\":\"Owned Composer\"}}]}}]}"
        } else if url.host == "ws.audioscrobbler.com" { body = "{\"artist\":{\"stats\":{\"listeners\":\"123456\",\"playcount\":\"987654\"}}}" }
        else if path.hasPrefix("/artist/") { body = "{\"id\":8,\"nb_fan\":4512,\"picture_big\":\"https://cdn-images.dzcdn.net/owned.jpg\"}" }
        else { body = "{\"data\":[],\"total\":0}" }
        return .init(status: 200, ok: true, headers: ["content-length": String(body.utf8.count)], bodyBase64: Data(body.utf8).base64EncodedString(), url: request.url)
    }
    static let recording = """
    {"id":77,"type":"track","title":"Owned Song","duration":180,"isrc":"USOWN2600001","artist":{"id":8,"name":"Owned Artist"},"album":{"id":9,"title":"Owned Album","cover_big":"https://cdn-images.dzcdn.net/owned.jpg"},"contributors":[{"id":8,"name":"Owned Artist","role":"Main"},{"id":10,"name":"Owned Guest","role":"Featured"}]}
    """
}
@MainActor private final class ArtistScope { var value = PluginExecutionScope(owner: "owned-artists-" + UUID().uuidString, activation: UUID()) }
@MainActor final class MusicArtistNativeTests: XCTestCase {
    func testActualWorkerRosterUsesOriginalReturnedRowCursorCacheAndMusicBrainzSpacing() async throws {
        let scope = ArtistScope(), network = ArtistFixtureNetwork()
        let client = MusicArtistClient(scope: scope.value, currentScope: { scope.value }, transport: MusicArtistTransport(network: network)); defer { client.dispose() }
        let page = try await client.roster(132); XCTAssertEqual(page.artists.count, 2); XCTAssertEqual(page.next, 3)
        XCTAssertEqual(page.artists.first?.name, "Owned Artist"); XCTAssertEqual(page.artists.first?.musicBrainzId, ArtistFixtureNetwork.artistID)
        _ = try await client.roster(132)
        let last = try await client.roster(132, offset: 3); XCTAssertNil(last.next); XCTAssertEqual(last.artists.count, 1)
        let requests = await network.observations
        XCTAssertEqual(requests.map(\.offset), ["0", "3"]); XCTAssertTrue(requests.allSatisfy(\.publicOnly))
        XCTAssertGreaterThanOrEqual(requests[1].date.timeIntervalSince(requests[0].date), 0.9)
    }
    func testActualRecordingKeepsPlaybackIdentityAndVerifiedDeezerAndMusicBrainzCredits() async throws {
        let scope = ArtistScope(), network = ArtistFixtureNetwork()
        let client = MusicArtistClient(scope: scope.value, currentScope: { scope.value }, transport: MusicArtistTransport(network: network)); defer { client.dispose() }
        let track = Self.track()
        let loaded = try await client.recording(track), profile = try XCTUnwrap(loaded)
        XCTAssertEqual(track.playbackUrl, "https://owned.invalid/private-playback")
        XCTAssertEqual(profile.catalogTrack.id, "deezer:track:77"); XCTAssertNil(profile.catalogTrack.playbackUrl)
        XCTAssertEqual(profile.credits.map(\.role), ["main artist", "featured artist", "producer", "composer"])
        XCTAssertEqual(profile.credits.last?.workTitle, "Owned Composition"); XCTAssertEqual(profile.credits[2].attributes, ["executive"])
        XCTAssertEqual(profile.provenance.map(\.source), ["Deezer", "MusicBrainz"]); XCTAssertEqual(profile.isrc, "USOWN2600001")
        let before = await network.observations.count; _ = try await client.recording(track)
        let after = await network.observations.count; XCTAssertEqual(before, after)
        var external = Self.track(id: "owned:local", connector: "local"); external.isrc = "USOWN2600001"
        let byISRC = try await client.recording(external); XCTAssertEqual(byISRC?.provenance.first?.matchedBy, "isrc")
        let paths = await network.observations.map(\.path); XCTAssertTrue(paths.contains("/track/isrc:USOWN2600001")); XCTAssertFalse(paths.contains("/private-playback"))
    }
    func testWrongProviderIdentityAndAmbiguousSearchNeverBecomeAnUnrelatedRecording() async throws {
        let scope = ArtistScope(), network = ArtistFixtureNetwork()
        let client = MusicArtistClient(scope: scope.value, currentScope: { scope.value }, transport: MusicArtistTransport(network: network)); defer { client.dispose() }
        let wrong = try await client.recording(Self.track(id: "deezer:track:99")); XCTAssertNil(wrong)
        let unknown = try await client.recording(Self.track(id: "owned:unmatched", connector: "local")); XCTAssertNil(unknown)
    }
    func testProfileKeyChangesRetireOldRuntimeAndStatisticsNeverReuseAnotherKeyOrOwner() async throws {
        let scope = ArtistScope(), network = ArtistFixtureNetwork()
        let first = MusicArtistClient(scope: scope.value, currentScope: { scope.value }, transport: MusicArtistTransport(network: network))
        defer { try? first.saveAPIKey(""); first.dispose() }
        XCTAssertFalse(first.hasAPIKey); try first.saveAPIKey("owned-test-key-one")
        let artist = MusicArtistReference(id: "deezer:artist:8", connectorId: "catalog", name: "Owned Artist")
        let initial = try await first.audience([artist]); XCTAssertEqual(initial.first?.listeners, 123456); XCTAssertEqual(initial.first?.fans, 4512)
        let before = await network.observations.count; _ = try await first.audience([artist]); let after = await network.observations.count; XCTAssertEqual(before, after)
        let sameOwner = MusicArtistClient(scope: scope.value, currentScope: { scope.value }); XCTAssertTrue(sameOwner.hasAPIKey); sameOwner.dispose()
        let otherScope = ArtistScope(), other = MusicArtistClient(scope: otherScope.value, currentScope: { otherScope.value }); XCTAssertFalse(other.hasAPIKey); other.dispose()
        try first.saveAPIKey("owned-test-key-two"); _ = try await first.audience([artist])
        let keys = await network.observations.compactMap(\.key); XCTAssertEqual(keys, ["owned-test-key-one", "owned-test-key-two"])
        try first.saveAPIKey(""); let noKey = try await first.audience([artist]); XCTAssertNil(noKey.first?.listeners); XCTAssertFalse(first.hasAPIKey)
    }
    func testCancellationAndRetiredOwnerCannotPublishAnOldRecordingOrDisposeTheNewKeyRuntime() async throws {
        let scope = ArtistScope(), network = ArtistFixtureNetwork()
        let client = MusicArtistClient(scope: scope.value, currentScope: { scope.value }, transport: MusicArtistTransport(network: network)); defer { client.dispose() }
        await network.hold(); let pending = Task { try await client.recording(Self.track()) }
        try await wait { await network.observations.count > 0 }
        try client.saveAPIKey("owned-retiring-key")
        let definitions = try await client.query("definitions", as: [MusicGenre].self); XCTAssertEqual(definitions.count, 159)
        await network.release()
        do { _ = try await pending.value; XCTFail("The old key runtime must retire") } catch is CancellationError { }
        let stillAvailable = try await client.query("definitions", as: [MusicGenre].self); XCTAssertEqual(stillAvailable.count, 159)
        await network.hold(); let count = await network.observations.count
        let cancelled = Task { try await client.recording(Self.track()) }, consumer = Task { try await client.recording(Self.track()) }
        try await wait { await network.observations.count > count }; try await Task.sleep(for: .milliseconds(100))
        cancelled.cancel()
        do { _ = try await cancelled.value; XCTFail("The cancelled reader must retire without cancelling the other consumer") } catch is CancellationError { }
        await network.release(); let shared = try await consumer.value; XCTAssertEqual(shared?.catalogTrack.id, "deezer:track:77")
        let trackRequests = await network.observations.filter { $0.path == "/track/77" }; XCTAssertEqual(trackRequests.count, 2, "One retired key request and one coalesced shared request")
        try client.saveAPIKey("")
        await network.hold(); let before = await network.observations.count
        let retired = Task { try await client.roster(132) }; try await wait { await network.observations.count > before }
        scope.value = .init(owner: "other-owner", activation: UUID()); await network.release()
        do { _ = try await retired.value; XCTFail("A retired profile must not publish artists") } catch is CancellationError { }
    }
    func testArtistTransportRejectsUnrelatedHostsMethodsAndOversizedNativeEnrichmentBatches() async throws {
        let scope = ArtistScope(), network = ArtistFixtureNetwork(), transport = MusicArtistTransport(network: network)
        for (url, method) in [("https://127.0.0.1/private", "GET"), ("https://musicbrainz.org/ws/2/artist", "POST"), ("https://user@api.deezer.com/artist/8", "GET")] {
            do { _ = try await transport.perform(.http, payload: .object(["url": .string(url), "opts": .object(["method": .string(method)])])); XCTFail("Deny before connecting") }
            catch let error as HarborError { XCTAssertEqual(error.code, "music-artist-host") }
        }
        let client = MusicArtistClient(scope: scope.value, currentScope: { scope.value }, transport: transport); defer { client.dispose() }
        let artist = MusicArtistReference(id: "deezer:artist:8", connectorId: "catalog", name: "Owned Artist")
        do { _ = try await client.audience(Array(repeating: artist, count: 4)); XCTFail("Only three simultaneous artist enrichments") } catch let error as HarborError { XCTAssertEqual(error.code, "music-artist-batch") }
        let requests = await network.observations; XCTAssertTrue(requests.isEmpty)
    }
    static func track(id: String = "deezer:track:77", connector: String = "catalog") -> MusicTrack {
        .init(id: id, connectorId: connector, sourceId: "77", playbackUrl: "https://owned.invalid/private-playback", title: "Owned Song", artist: "Owned Artist", album: "Owned Album", artwork: "", durationSeconds: 180, durationLabel: "3:00")
    }
    private func wait(_ condition: @escaping () async -> Bool) async throws {
        for _ in 0..<200 { if await condition() { return }; try await Task.sleep(for: .milliseconds(20)) }
        XCTFail("The owned artist request did not reach its gate"); throw HarborError(code: "owned-artist-gate")
    }
}

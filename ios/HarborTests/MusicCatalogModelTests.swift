import XCTest
@testable import Harbor

private enum OwnedMusicCatalog {
    static let track = MusicTrack(id: "itunes:track:11", connectorId: "catalog", sourceId: "11", playbackUrl: nil, title: "Owned track", artist: "Owned artist", album: "Owned album", artwork: "", durationSeconds: 120, durationLabel: "2:00")
    static let album = MusicCatalogAlbum(id: "deezer:album:7", connectorId: "catalog", title: "Owned album", artist: "Owned artist", artwork: "", year: 2026, trackCount: 2)
    static let artist = MusicCatalogArtist(id: "deezer:artist:17", connectorId: "catalog", name: "Owned artist")
    static let cursor = "owned-provider:artist=17&kind=tracks&offset=not-a-native-number"
    static let row = MusicCatalogRow(id: "owned:row", title: "Owned releases", titleLiteral: true, subtitle: nil, layout: .covers, source: "catalog", items: [.album(album)])
    static let search = MusicCatalogSearch(top: nil, tracks: [track], albums: [album], artists: [artist], playlists: [])
}

private actor ControlledMusicCatalog: MusicCatalogCalling {
    private var searchGate: CheckedContinuation<MusicCatalogSearch, any Error>?
    private var pageGate: CheckedContinuation<MusicCatalogPage, any Error>?
    private var homeCount = 0
    private var searchCount = 0
    private var failHome = false
    private var pages: [MusicCatalogRequest] = []
    func home() async throws -> [MusicCatalogRow] {
        homeCount += 1
        if failHome { throw HarborError(code: "owned-refresh-failure") }
        return [OwnedMusicCatalog.row]
    }
    func search(_ query: String, limit: Int) async throws -> MusicCatalogSearch {
        searchCount += 1
        if query == "slow" { return try await withCheckedThrowingContinuation { searchGate = $0 } }
        return OwnedMusicCatalog.search
    }
    func albumTracks(_ album: MusicCatalogAlbum) async throws -> [MusicTrack] { [OwnedMusicCatalog.track] }
    func artistTop(_ artist: MusicCatalogArtist) async throws -> [MusicTrack] { [OwnedMusicCatalog.track] }
    func artistRows(_ artist: MusicCatalogArtist) async throws -> [MusicCatalogRow] { [OwnedMusicCatalog.row] }
    func playlistTracks(_ playlist: MusicCatalogPlaylist) async throws -> [MusicTrack] { [OwnedMusicCatalog.track] }
    func artistCatalog(_ artist: MusicCatalogArtist, kind: MusicCatalogKind, cursor: String?) async throws -> MusicCatalogPage {
        pages.append(.init(operation: "artistCatalog", artist: artist, kind: kind, cursor: cursor))
        if kind == .albums { return .init(items: [.album(OwnedMusicCatalog.album)], nextCursor: nil, total: 1, scope: .catalog) }
        if cursor == nil { return .init(items: [.track(OwnedMusicCatalog.track)], nextCursor: OwnedMusicCatalog.cursor, total: 2, scope: .catalog) }
        return try await withCheckedThrowingContinuation { pageGate = $0 }
    }
    func searchWaiting() -> Bool { searchGate != nil }
    func pageWaiting() -> Bool { pageGate != nil }
    func homeCalls() -> Int { homeCount }
    func searchCalls() -> Int { searchCount }
    func failRefresh() { failHome = true }
    func capturedPages() -> [MusicCatalogRequest] { pages }
    func finishSearch() { searchGate?.resume(returning: OwnedMusicCatalog.search); searchGate = nil }
    func finishPage() {
        let other = MusicTrack(id: "itunes:track:12", connectorId: "catalog", sourceId: "12", playbackUrl: nil, title: "Owned second", artist: "Owned artist", album: nil, artwork: "", durationSeconds: 180, durationLabel: "3:00")
        pageGate?.resume(returning: .init(items: [.track(other), .track(OwnedMusicCatalog.track)], nextCursor: OwnedMusicCatalog.cursor, total: 2, scope: .catalog)); pageGate = nil
    }
}

@MainActor final class MusicCatalogModelTests: XCTestCase {
    func testPinnedTaggedCatalogObjectsKeepTheirKindsAndOriginalProviderIDs() throws {
        let fixtures = [
            #"{"kind":"album","id":"deezer:album:7","connectorId":"catalog","title":"Owned album","artist":"Owned artist","artwork":"","year":2026,"trackCount":2}"#,
            #"{"kind":"artist","id":"deezer:artist:17","connectorId":"catalog","name":"Owned artist"}"#,
            #"{"kind":"playlist","id":"deezer:playlist:7","connectorId":"catalog","name":"Owned list","artwork":[],"trackCount":2}"#,
            #"{"kind":"station","id":"owned:station","connectorId":"owned","name":"Owned station","artwork":""}"#]
        let values = try fixtures.map { try JSONDecoder().decode(MusicCatalogItem.self, from: Data($0.utf8)) }
        XCTAssertEqual(Set(values.map(\.id)).count, 4)
        XCTAssertEqual(values[0], .album(OwnedMusicCatalog.album)); XCTAssertEqual(values[1], .artist(OwnedMusicCatalog.artist))
        XCTAssertThrowsError(try JSONDecoder().decode(MusicCatalogItem.self, from: Data(#"{"kind":"unknown","id":"7"}"#.utf8)))
        let data = try JSONEncoder().encode(MusicCatalogRequest(operation: "artistCatalog", artist: OwnedMusicCatalog.artist, kind: .albums, cursor: OwnedMusicCatalog.cursor))
        let request = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(request["cursor"] as? String, OwnedMusicCatalog.cursor)
        XCTAssertEqual((request["artist"] as? [String: Any])?["id"] as? String, "deezer:artist:17")
    }
    func testLateSearchCannotReplaceTheHomeAndReturningHomeReusesItsLoadedRows() async throws {
        let client = ControlledMusicCatalog()
        let actual = MusicCatalogModel(client: client)
        await actual.load(query: "", debounce: false)
        let slow = Task { await actual.load(query: "slow", debounce: false) }
        try await wait { await client.searchWaiting() }
        await actual.load(query: "", debounce: false); await client.finishSearch(); await slow.value
        XCTAssertEqual(actual.activeQuery, ""); XCTAssertNil(actual.result); XCTAssertEqual(actual.rows.first?.id, OwnedMusicCatalog.row.id)
        let calls = await client.homeCalls(); XCTAssertEqual(calls, 1)
        await actual.load(query: "owned", debounce: false); await actual.load(query: "owned", debounce: false)
        let searches = await client.searchCalls(); XCTAssertEqual(searches, 2, "The last successful query survives returning from a detail screen")
        await client.failRefresh(); await actual.load(query: "", refresh: true, debounce: false)
        XCTAssertEqual(actual.rows.first?.id, OwnedMusicCatalog.row.id, "A failed refresh keeps available content without a partial-catalog warning")
        XCTAssertFalse(actual.loading); XCTAssertNil(actual.failure)
    }
    func testArtistPagesKeepOpaqueCursorsDeduplicateAndRejectLatePreviousKindResults() async throws {
        let client = ControlledMusicCatalog(), model = MusicCatalogDetailModel()
        await model.load(.artist(OwnedMusicCatalog.artist), kind: .tracks, client: client)
        let firstNext = Task { await model.loadNext(client: client) }; try await wait { await client.pageWaiting() }
        await client.finishPage(); await firstNext.value
        XCTAssertEqual(model.items.count, 2); XCTAssertNil(model.nextCursor, "A provider repeating its cursor cannot loop forever")
        await model.load(.artist(OwnedMusicCatalog.artist), kind: .tracks, client: client)
        let lateNext = Task { await model.loadNext(client: client) }; try await wait { await client.pageWaiting() }
        await model.load(.artist(OwnedMusicCatalog.artist), kind: .albums, client: client)
        await client.finishPage(); await lateNext.value
        XCTAssertEqual(model.items, [.album(OwnedMusicCatalog.album)]); XCTAssertEqual(model.total, 1); XCTAssertFalse(model.loading)
        let pages = await client.capturedPages().filter { $0.cursor != nil }
        XCTAssertEqual(pages.count, 2); XCTAssertTrue(pages.allSatisfy { $0.cursor == OwnedMusicCatalog.cursor && $0.artist?.id == OwnedMusicCatalog.artist.id && $0.kind == .tracks })
    }
    private func wait(_ condition: @Sendable () async -> Bool) async throws {
        for _ in 0..<150 { if await condition() { return }; try await Task.sleep(for: .milliseconds(20)) }
        XCTFail("The owned catalog request did not reach its gate"); throw HarborError(code: "owned-catalog-timeout")
    }
}

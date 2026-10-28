import XCTest
@testable import Harbor

@MainActor final class ManualWatchedSelectionTests: XCTestCase {
    private func fixture() throws -> JSONValue {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "manual-mark-reference", withExtension: "json", subdirectory: "Fixtures"))
        let value = try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: url))
        XCTAssertEqual(value["reference"].string, "0834340cec5531650bfe78cd628628702e636987")
        XCTAssertEqual(value["actual_original_typescript_executed"], .bool(true)); XCTAssertEqual(value["provider_network_requests"].integer, 0)
        XCTAssertEqual(value["executed_module_hashes"].objectValue.count, 3); return value
    }
    private func account() throws -> TraktAccountStore {
        let account = TraktAccountStore(owner: "owned-manual-" + UUID().uuidString, persistence: OwnedTraktPersistence())
        try account.load(); try account.set(.init(accessToken: "owned-access", refreshToken: "owned-refresh", createdAt: 1_700_000_000, expiresIn: 7_776_000))
        return account
    }
    private func client(_ transport: OwnedTraktTransport) -> TraktClient {
        let clock = OwnedTraktClock(); return .init(transport: { try await transport.send($0) }, sleep: { clock.advance($0) }, now: { clock.now() })
    }
    private func receipt(_ count: Int = 1) throws -> TraktReply {
        .init(status: 200, data: try JSONEncoder().encode(JSONValue.object(["added": .object(["movies": .integer(Int64(count)), "episodes": .integer(Int64(count))])])))
    }
    private func makeLibrary(_ account: TraktAccountStore, feed: TraktWatchedFeed, root: URL) async -> LibraryModel {
        let service = OwnedRetirementOfflineService()
        let library = LibraryModel(service: service, writeQueue: .init(service: service, directory: root), cache: .init(directory: root), traktWatched: feed)
        await library.setSession(nil, personalOwner: account.owner, guestOwner: account.owner, synchronize: false)
        feed.bind(account: account, scope: "owned", active: { true }); return library
    }
    func testExecutedDesktopManualMarkTargetsAndAiringBoundariesMatchAllNineScenarios() throws {
        let value = try fixture(), now = Date(timeIntervalSince1970: try XCTUnwrap(value["at"].numericValue) / 1_000)
        XCTAssertEqual(value["cases"].array.count, 9)
        for row in value["cases"].array {
            let media = try XCTUnwrap(Media.parse(row["media"], kind: "movie")), episodes = ManualWatchedSelection.releasedEpisodes(media, now: now)
            let coordinates = episodes.map { JSONValue.object(["season": .integer(Int64($0.season ?? -1)), "episode": .integer(Int64($0.episode ?? -1))]) }
            XCTAssertEqual(JSONValue.array(coordinates), row["episodes"], row["name"].string ?? "")
            let requests = ManualWatchedSelection.requests(media, episodes: episodes, wholeSeries: true)
            XCTAssertEqual(JSONValue.array(requests.map { $0.target.json }), row["targets"], row["name"].string ?? "")
        }
    }
    func testActualCustomMovieMarkSendsExplicitIMDbAndPersistsWithoutStremioSession() async throws {
        let account = try account(), root = FileManager.default.temporaryDirectory.appendingPathComponent(account.owner)
        defer { try? FileManager.default.removeItem(at: root) }
        let transport = OwnedTraktTransport(try [receipt()]), feed = TraktWatchedFeed(client: client(transport), disk: OwnedTraktWatchedDisk())
        let library = await makeLibrary(account, feed: feed, root: root)
        var media = Media(id: "owned:film", type: "movie", name: "Owned Film"); media.imdbID = "tt1234567"
        await library.toggleWatched(media); await feed.settled()
        XCTAssertFalse(library.hasCloudSession); XCTAssertTrue(library.watched(media))
        let requests = await transport.requests; XCTAssertEqual(requests.count, 1)
        let request = try XCTUnwrap(requests.first); XCTAssertEqual(request.httpMethod, "POST"); XCTAssertEqual(request.url?.path, "/sync/history")
        let body = try JSONDecoder().decode(JSONValue.self, from: XCTUnwrap(request.httpBody))
        XCTAssertEqual(body["movies"].array.first?["ids"]["imdb"].string, "tt1234567")
        XCTAssertTrue(try XCTUnwrap(feed.state(for: account.owner)).movie(media))
        let snapshot = try await LibraryCache(directory: root).readSnapshot(owner: account.owner)
        XCTAssertEqual(snapshot.items.first?.id, media.id); XCTAssertEqual(snapshot.items.first?.raw["state"]["nativeManualMovie"], .bool(true))
        let restored = await makeLibrary(account, feed: feed, root: root); XCTAssertTrue(restored.watched(media))
    }
    func testActualBulkMarkExcludesSpecialFutureAndUndatedTailAndUnmarkPreservesIndividualSpecial() async throws {
        let account = try account(), root = FileManager.default.temporaryDirectory.appendingPathComponent(account.owner)
        defer { try? FileManager.default.removeItem(at: root) }
        let transport = OwnedTraktTransport(try [receipt(), receipt(), receipt()]), feed = TraktWatchedFeed(client: client(transport), disk: OwnedTraktWatchedDisk())
        let library = await makeLibrary(account, feed: feed, root: root)
        let row = try XCTUnwrap(fixture()["cases"].array.first { $0["name"].string == "custom-show-explicit-imdb-and-aired-boundary" })
        let media = try XCTUnwrap(Media.parse(row["media"], kind: "series")), special = try XCTUnwrap(media.videos?.first { $0.season == 0 })
        await library.toggleWatched(media); await feed.settled()
        XCTAssertEqual(library.watchedEpisodes(media), ["1:1", "1:2"]); XCTAssertTrue(library.watched(media))
        await library.toggleEpisode(media, episode: special); await feed.settled()
        XCTAssertTrue(library.watchedEpisodes(media).contains("0:1"))
        await library.toggleWatched(media); await feed.settled()
        XCTAssertFalse(library.watched(media)); XCTAssertEqual(library.watchedEpisodes(media), ["0:1"])
        let requests = await transport.requests; XCTAssertEqual(requests.count, 3); XCTAssertTrue(requests.allSatisfy { $0.httpMethod == "POST" })
        let snapshot = try await LibraryCache(directory: root).readSnapshot(owner: account.owner)
        let manual = try XCTUnwrap(snapshot.items.first).raw["state"]["nativeManualEpisodes"]
        XCTAssertEqual(manual["1:1"], .bool(false)); XCTAssertEqual(manual["0:1"], .bool(true)); XCTAssertEqual(manual["1:3"], .null)
    }
    func testAnimeRequiresVerifiedEpisodeMappingAndRejectsMetadataOnlyAndWholeSeriesRequests() {
        var media = Media(id: "kitsu:1", type: "series", name: "Owned Anime"); media.imdbID = "tt7654321"
        let raw = Episode(id: "kitsu:1:99", season: 1, episode: 99)
        XCTAssertTrue(ManualWatchedSelection.requests(media, episodes: [raw], wholeSeries: false).isEmpty)
        let mapped = Episode(id: raw.id, season: 1, episode: 99, imdbID: "tt7654321", imdbSeason: 5, imdbEpisode: 23)
        let request = ManualWatchedSelection.requests(media, episodes: [mapped], wholeSeries: false).first
        XCTAssertEqual(request?.identity.mediaID, "kitsu:1"); XCTAssertEqual(request?.target.season, 5); XCTAssertEqual(request?.target.number, 23)
        XCTAssertTrue(ManualWatchedSelection.requests(media, episodes: [mapped], wholeSeries: true).isEmpty)
        media.id = "owned:unknown"; media.imdbID = "not-an-imdb-id"
        XCTAssertTrue(ManualWatchedSelection.requests(media, episodes: [raw], wholeSeries: false).isEmpty)
    }
    func testHeldCustomShowMarkCannotPublishOrSendNextEpisodeAfterOwnerChanges() async throws {
        let account = try account(), scope = OwnedTraktScope(), transport = OwnedTraktTransport(try [receipt(), receipt()])
        let feed = TraktWatchedFeed(client: client(transport), disk: OwnedTraktWatchedDisk())
        feed.bind(account: account, scope: "owned", active: { scope.active })
        var media = Media(id: "owned:show", type: "series", name: "Owned Show"); media.imdbID = "tt7654321"
        await transport.hold("/sync/history")
        feed.enqueueMark(media, episodes: [.init(id: "ep:1", season: 1, episode: 1), .init(id: "ep:2", season: 1, episode: 2)], owner: account.owner, wholeSeries: true)
        for _ in 0..<100 { if await transport.isHolding { break }; try await Task.sleep(for: .milliseconds(20)) }
        let held = await transport.isHolding; XCTAssertTrue(held)
        scope.active = false; await transport.release(); await feed.settled()
        XCTAssertNil(feed.state(for: account.owner)); let requests = await transport.requests; XCTAssertEqual(requests.count, 1)
    }
}

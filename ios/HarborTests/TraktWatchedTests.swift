import XCTest
@testable import Harbor

actor OwnedTraktWatchedDisk: TraktWatchedPersistence {
    private var values: [String: (String, TraktWatchedState)] = [:]
    func read(owner: String, fingerprint: String) -> TraktWatchedState? { values[owner].flatMap { $0.0 == fingerprint ? $0.1 : nil } }
    func write(_ value: TraktWatchedState, owner: String, fingerprint: String) { values[owner] = (fingerprint, value) }
}
@MainActor final class TraktWatchedTests: XCTestCase {
    private func fixture() throws -> JSONValue {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "trakt-watched-reference", withExtension: "json", subdirectory: "Fixtures"))
        let value = try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: url))
        XCTAssertEqual(value["reference"].string, "0834340cec5531650bfe78cd628628702e636987")
        XCTAssertEqual(value["actual_original_typescript_executed"], .bool(true)); XCTAssertEqual(value["provider_network_requests"].integer, 0)
        XCTAssertEqual(value["executed_module_hashes"].objectValue.count, 4); return value
    }
    private func account() throws -> TraktAccountStore {
        let value = TraktAccountStore(owner: "owned-watched-" + UUID().uuidString, persistence: OwnedTraktPersistence())
        try value.load(); try value.set(.init(accessToken: "owned-access", refreshToken: "owned-refresh", createdAt: 1_700_000_000, expiresIn: 7_776_000, username: "Owned")); return value
    }
    private func client(_ transport: OwnedTraktTransport) -> TraktClient {
        let clock = OwnedTraktClock(); return .init(transport: { try await transport.send($0) }, sleep: { clock.advance($0) }, now: { clock.now() })
    }
    private func reply(_ value: JSONValue, status: Int = 200) throws -> TraktReply { .init(status: status, data: try JSONEncoder().encode(value)) }
    private func waitForHold(_ transport: OwnedTraktTransport) async throws {
        for _ in 0..<100 { if await transport.isHolding { return }; try await Task.sleep(for: .milliseconds(20)) }
        XCTFail("Owned request did not reach its barrier"); throw HarborError(code: "owned-barrier")
    }
    func testExecutedDesktopHistoryKeepsBothIDsCanonicalCoordinatesAndTheActualThousandItemRequest() async throws {
        let value = try fixture(), date = Date(timeIntervalSince1970: try XCTUnwrap(value["at"].numericValue) / 1_000)
        XCTAssertEqual(value["cases"].array.count, 6)
        for row in value["cases"].array {
            let state = try TraktWatchedState(at: date, history: row["raw"])
            XCTAssertEqual(state.keys, Set(row["keys"].array.compactMap(\.string)), row["name"].string ?? "")
            let account = try account(), transport = OwnedTraktTransport(try [reply(row["raw"])])
            let feed = TraktWatchedFeed(client: client(transport), disk: OwnedTraktWatchedDisk(), now: { date })
            feed.bind(account: account, scope: "owned", active: { true }); await feed.refresh()
            XCTAssertEqual(feed.state(for: account.owner), state)
            let requests = await transport.requests; XCTAssertEqual(requests.count, 1)
            XCTAssertEqual(requests.first?.url?.absoluteString, "https://api.trakt.tv/sync/history?limit=1000")
            XCTAssertEqual(requests.first?.value(forHTTPHeaderField: "Authorization"), "Bearer owned-access"); XCTAssertNil(requests.first?.value(forHTTPHeaderField: "Cookie"))
        }
        XCTAssertThrowsError(try TraktWatchedState(at: date, history: .object([:])))
    }
    func testExecutedDesktopCacheExpiresAfterExactlyOneDayAndProtectedDiskSeparatesConnectionAndOwner() async throws {
        let value = try fixture(), date = Date(timeIntervalSince1970: try XCTUnwrap(value["at"].numericValue) / 1_000)
        XCTAssertEqual(value["cacheCases"].array.count, 6)
        for row in value["cacheCases"].array where row["username"].string == "Owned" && row["connected"] == .bool(true) {
            let state = TraktWatchedState(at: date.addingTimeInterval(-(row["age"].numericValue ?? 0) / 1_000), keys: ["imdb:tt1234567", "imdb:tt7654321:5:23"])
            XCTAssertEqual(state.fresh(date), !row["expected"].array.isEmpty)
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("owned-watched-disk-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let disk = TraktWatchedDisk(root: root), account = try account(), fingerprint = EBookShelf.hash(try XCTUnwrap(account.session?.trackingID).uuidString)
        let state = try TraktWatchedState(at: date, history: value["cases"].array[0]["raw"])
        try await disk.write(state, owner: account.owner, fingerprint: fingerprint)
        let reopened = try await TraktWatchedDisk(root: root).read(owner: account.owner, fingerprint: fingerprint)
        XCTAssertEqual(reopened, state)
        let other = try await disk.read(owner: account.owner, fingerprint: "other"), foreign = try await disk.read(owner: "other", fingerprint: fingerprint)
        XCTAssertNil(other); XCTAssertNil(foreign)
        let file = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil).first)
        let text = try String(contentsOf: file, encoding: .utf8); XCTAssertFalse(text.contains("owned-access")); XCTAssertFalse(text.contains("owned-refresh"))
        let transport = OwnedTraktTransport(), feed = TraktWatchedFeed(client: client(transport), disk: disk, now: { date })
        feed.bind(account: account, scope: "owned", active: { true }); await feed.refresh(); XCTAssertEqual(feed.state(for: account.owner), state)
        try account.set(nil); XCTAssertNil(feed.state(for: account.owner))
        try account.set(.init(accessToken: "owned-next", refreshToken: "owned-next-refresh", createdAt: 1_700_000_000, expiresIn: 7_776_000))
        feed.bind(account: account, scope: "owned", active: { true }); await feed.refresh(); XCTAssertNil(feed.state(for: account.owner))
    }
    func testExecutedDesktopCanonicalAnimeAndManualNegativePrioritySurviveActualLibraryRestart() async throws {
        let value = try fixture(); XCTAssertEqual(value["progressCases"].array.count, 5)
        for row in value["progressCases"].array {
            let account = try account(), root = FileManager.default.temporaryDirectory.appendingPathComponent("owned-watched-manual-" + UUID().uuidString)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true); defer { try? FileManager.default.removeItem(at: root) }
            let disk = OwnedTraktWatchedDisk(), fingerprint = EBookShelf.hash(try XCTUnwrap(account.session?.trackingID).uuidString)
            await disk.write(.init(at: Date(), keys: Set(row["keys"].array.compactMap(\.string))), owner: account.owner, fingerprint: fingerprint)
            let transport = OwnedTraktTransport(fallback: { request in
                let value: JSONValue = .object(["added": .object(["episodes": .integer(1)])])
                return .init(status: request.httpMethod == "GET" ? 503 : 200, data: try JSONEncoder().encode(value))
            })
            let feed = TraktWatchedFeed(client: client(transport), disk: disk); feed.bind(account: account, scope: "owned", active: { true }); await feed.refresh()
            let cache = LibraryCache(directory: root), service = OwnedRetirementOfflineService()
            let library = LibraryModel(service: service, writeQueue: .init(service: service, directory: root), cache: cache, traktWatched: feed)
            await library.setSession(nil, personalOwner: account.owner, guestOwner: account.owner, synchronize: false)
            // setSession invalidates old operations; rebind as the real root does.
            feed.bind(account: account, scope: "owned", active: { true }); await feed.refresh()
            let episode = Episode(id: "kitsu:1:99", season: 1, episode: 99, imdbID: "tt7654321", imdbSeason: row["canonS"].integer, imdbEpisode: row["canonE"].integer)
            var media = Media(id: "kitsu:1", type: "series", name: "Owned Anime"); media.videos = [episode]
            if row["manual"] != .null { await library.toggleEpisode(media, episode: episode); await feed.settled() }
            XCTAssertEqual(library.watchedEpisodes(media).contains("1:99"), row["expected"]["watched"] == .bool(true), row["name"].string ?? "")
            let restart = LibraryModel(service: service, writeQueue: .init(service: service, directory: root), cache: LibraryCache(directory: root), traktWatched: feed)
            await restart.setSession(nil, personalOwner: account.owner, guestOwner: account.owner, synchronize: false)
            feed.bind(account: account, scope: "owned", active: { true }); await feed.refresh()
            XCTAssertEqual(restart.watchedEpisodes(media).contains("1:99"), row["expected"]["watched"] == .bool(true))
            let requests = await service.requests; XCTAssertEqual(requests, 0)
        }
    }
    func testLateDifferentProfileAndConnectionCannotPublishWatchedKeysOrCacheThem() async throws {
        let value = try fixture(), account = try account(), scope = OwnedTraktScope()
        let transport = OwnedTraktTransport(try [reply(value["cases"].array[0]["raw"])]), disk = OwnedTraktWatchedDisk()
        let feed = TraktWatchedFeed(client: client(transport), disk: disk); feed.bind(account: account, scope: "owned", active: { scope.active })
        await transport.hold("/sync/history"); let operation = Task { await feed.refresh() }; try await waitForHold(transport)
        scope.active = false; await transport.release(); await operation.value; XCTAssertNil(feed.state(for: account.owner))
        let fingerprint = EBookShelf.hash(try XCTUnwrap(account.session?.trackingID).uuidString)
        let saved = await disk.read(owner: account.owner, fingerprint: fingerprint); XCTAssertNil(saved)
        scope.active = true; feed.bind(account: account, scope: "owned", active: { scope.active })
        await transport.hold("/sync/history"); let changed = Task { await feed.refresh(force: true) }; try await waitForHold(transport)
        try account.set(nil); await transport.release(); await changed.value; XCTAssertNil(feed.state(for: account.owner))
        for row in value["staleCases"].array { XCTAssertEqual(row["rejected"], .bool(true)); XCTAssertEqual(row["cacheWrites"].integer, 0) }
    }
    func testExecutedDesktopManualHistoryWritesKeepDirectResolvedSpecialAndUnconfirmedOutcomes() async throws {
        let rows = try fixture()["markCases"].array; XCTAssertEqual(rows.count, 4)
        for row in rows {
            let account = try account(), name = row["name"].string
            let receipt: JSONValue = .object(["added": .object(["episodes": .integer(1)])]), miss: JSONValue = .object(["not_found": .object([:])])
            let transport = OwnedTraktTransport(try [reply(name == "direct" ? receipt : miss), reply(receipt)])
            let reporter = TraktWatchReporter(account: account, queue: .init(owner: account.owner, persistence: OwnedTraktPendingPersistence()), client: client(transport), active: { true },
                resolve: { _, _, _ in name == "resolved" ? .found(.init(showIds: .init(.object(["trakt": .integer(99)])), season: 1, number: 99)) : .notFound },
                specialMovie: { _, _, _ in name == "special-movie" ? .init(.object(["tmdb": .integer(88)])) : nil })
            let identity = TraktWatchIdentity(mediaID: "tt7654321", episode: Episode(id: "owned", season: row["target"]["season"].integer, episode: row["target"]["number"].integer))
            let result = await reporter.mark(identity); XCTAssertEqual(result != nil, row["expected"] == .bool(true), name ?? "")
            let requests = await transport.requests; XCTAssertEqual(requests.count, row["requests"].array.count)
            for (index, expected) in row["requests"].array.enumerated() {
                let target: TraktWatchTarget
                if expected["kind"].string == "movie" { target = .init(kind: .movie, ids: .init(expected["ids"])) }
                else { target = .init(kind: .episode, ids: .init(expected["show"]["ids"]), season: expected["season"].integer, number: expected["number"].integer) }
                let actual = try JSONDecoder().decode(JSONValue.self, from: XCTUnwrap(requests[index].httpBody))
                XCTAssertEqual(actual, target.historyBody); XCTAssertEqual(requests[index].url?.path, "/sync/history")
            }
        }
    }
    func testActualUnmarkOfRemoteMoviePersistsLocallyWithoutDeletingProviderHistory() async throws {
        let account = try account(), root = FileManager.default.temporaryDirectory.appendingPathComponent("owned-watched-movie-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true); defer { try? FileManager.default.removeItem(at: root) }
        let transport = OwnedTraktTransport(try [reply(fixture()["cases"].array[0]["raw"])]), feed = TraktWatchedFeed(client: client(transport), disk: OwnedTraktWatchedDisk())
        let library = LibraryModel(cache: LibraryCache(directory: root), traktWatched: feed)
        await library.setSession(nil, personalOwner: account.owner, guestOwner: account.owner, synchronize: false)
        feed.bind(account: account, scope: "owned", active: { true }); await feed.refresh()
        let movie = Media(id: "tt1234567", type: "movie", name: "Owned Film"); XCTAssertTrue(library.watched(movie))
        await library.toggleWatched(movie); await feed.settled(); XCTAssertFalse(library.watched(movie))
        let requests = await transport.requests; XCTAssertEqual(requests.count, 1); XCTAssertTrue(requests.allSatisfy { $0.httpMethod == "GET" })
        let saved = try await LibraryCache(directory: root).readSnapshot(owner: account.owner)
        XCTAssertEqual(saved.items.first?.raw["state"]["nativeManualMovie"], .bool(false))
    }
}

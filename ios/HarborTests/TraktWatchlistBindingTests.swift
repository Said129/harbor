import XCTest
@testable import Harbor

@MainActor final class TraktWatchlistBindingTests: XCTestCase {
    private func fixture() throws -> JSONValue {
        let file = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "trakt-watchlist-binding-reference", withExtension: "json", subdirectory: "Fixtures"))
        let value = try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: file))
        XCTAssertEqual(value["reference"].string, "0834340cec5531650bfe78cd628628702e636987")
        XCTAssertEqual(value["actual_original_typescript_executed"], .bool(true)); XCTAssertEqual(value["provider_network_requests"].integer, 0)
        XCTAssertEqual(value["executed_module_hashes"].objectValue.count, 4); XCTAssertEqual(value["stale_scope_publications"].integer, 0)
        return value
    }
    private func account() throws -> TraktAccountStore {
        let account = TraktAccountStore(owner: "owned-binding-" + UUID().uuidString, persistence: OwnedTraktPersistence())
        try account.load(); try account.set(.init(accessToken: "owned-access", refreshToken: "owned-refresh", createdAt: 1_700_000_000, expiresIn: 7_776_000)); return account
    }
    private func client(_ transport: OwnedTraktTransport) -> TraktClient {
        let clock = OwnedTraktClock(); return .init(transport: { try await transport.send($0) }, sleep: { clock.advance($0) }, now: { clock.now() })
    }
    private func item(_ value: JSONValue) throws -> TraktLibraryItem {
        .init(type: try XCTUnwrap(.init(rawValue: value["type"].string ?? "")), title: value["title"].string ?? "", year: value["year"].integer,
            ids: .init(value["ids"]), contextDate: value["contextDate"].string)
    }
    private func media(_ value: JSONValue) -> Media {
        var media = Media(id: value["id"].string ?? "", type: value["type"].string ?? "movie", name: value["name"].string ?? "Owned")
        media.imdbID = value["imdbId"].string; return media
    }
    private func record(_ value: JSONValue) -> JSONValue {
        var fields = LibraryRecord.new(media(value)); fields["imdb_id"] = value["imdbId"]
        fields["unknown"] = .string("keep"); return .object(fields)
    }
    private func library(_ account: TraktAccountStore, root: URL, records: [JSONValue] = []) async throws -> (LibraryModel, OwnedRetirementOfflineService) {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let cache = LibraryCache(directory: root), service = OwnedRetirementOfflineService()
        try await cache.save(records, owner: account.owner)
        let library = LibraryModel(service: service, writeQueue: .init(service: service, directory: root), cache: cache)
        await library.setSession(nil, personalOwner: account.owner, guestOwner: account.owner, synchronize: false); return (library, service)
    }
    private func directory() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("owned-watchlist-" + UUID().uuidString, isDirectory: true) }
    private func waitForHold(_ transport: OwnedTraktTransport) async throws {
        for _ in 0..<1_000 { if await transport.isHolding { return }; await Task.yield() }
        XCTFail("Owned request did not reach its barrier"); throw HarborError(code: "owned-barrier")
    }
    func testExecutedDesktopAutomaticActionsKeepLocalStateAliasEvictionAndExactProviderRequestsWithoutStremio() async throws {
        let rows = try fixture()["cases"].array; XCTAssertEqual(rows.count, 6); XCTAssertEqual(rows.reduce(0) { $0 + $1["steps"].array.count }, 11)
        for row in rows {
            let account = try account(), root = directory(); defer { try? FileManager.default.removeItem(at: root) }
            let (library, service) = try await library(account, root: root, records: row["initial"].array.map(record))
            let store = TraktLibraryStore(owner: account.owner, disk: OwnedTraktLibraryDisk()); store.bind(account.session?.trackingID)
            try await store.commit(.init(watchlist: row["remote"].array.map(item)), fingerprint: XCTUnwrap(store.fingerprint), revision: store.revision)
            let transport = OwnedTraktTransport(fallback: { _ in .init(status: row["fail"] == .bool(true) ? 503 : 204, data: Data()) })
            let binding = try XCTUnwrap(TraktWatchlistSync(account: account, store: store, client: client(transport), active: { true }))
            library.bindTraktWatchlist(binding)
            var expected: [JSONValue] = []
            for (index, input) in row["actions"].array.enumerated() {
                let media = media(input), step = row["steps"].array[index]
                await library.toggleBookmark(media); await binding.settled()
                XCTAssertEqual(library.bookmarked(media), step["saved"] == .bool(true), row["name"].string ?? "")
                let candidates = Set(row["before"].array.compactMap(\.string) + row["initial"].array.compactMap { $0["id"].string } + row["actions"].array.compactMap { $0["id"].string })
                for id in candidates {
                    let kind = id.contains(":tv:") || id == "tt1234568" || id.hasPrefix("kitsu:") ? "series" : "movie"
                    XCTAssertEqual(library.bookmarked(Media(id: id, type: kind, name: "Probe")), step["ids"].array.contains(.string(id)), "\(row["name"].string ?? "") / \(id)")
                }
                expected += step["requests"].array
            }
            let requests = await transport.requests
            let actual = try requests.map { request -> JSONValue in
                .object(["route": .string(try XCTUnwrap(request.url?.path)), "method": .string(request.httpMethod ?? ""),
                    "body": try JSONDecoder().decode(JSONValue.self, from: XCTUnwrap(request.httpBody))])
            }
            XCTAssertEqual(JSONValue.array(actual), JSONValue.array(expected)); XCTAssertTrue(requests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == "Bearer owned-access" && $0.value(forHTTPHeaderField: "Cookie") == nil })
            let accountRequests = await service.requests; XCTAssertEqual(accountRequests, 0); XCTAssertFalse(library.hasCloudSession)
            library.bindTraktWatchlist(nil)
        }
    }
    func testRootAggregationKeepsTypedAliasesProgressAndImportDistinctFromTransientProviderCards() async throws {
        let account = try account(), root = directory(); defer { try? FileManager.default.removeItem(at: root) }
        var original = record(.object(["id": .string("tt1234567"), "type": .string("movie"), "name": .string("Local metadata")])).objectValue
        original["removed"] = .bool(true); original["temp"] = .bool(true)
        original["state"] = .object(["timeOffset": .integer(40_000), "duration": .integer(100_000), "custom": .string("keep")])
        let (library, service) = try await library(account, root: root, records: [.object(original)])
        let film = try item(fixture()["cases"].array[2]["remote"].array[0])
        let show = TraktLibraryItem(type: .show, title: "Same TMDB number, different show", year: 2020, ids: .init(.object(["tmdb": .integer(8), "imdb": .string("tt7654321")])))
        let store = TraktLibraryStore(owner: account.owner, disk: OwnedTraktLibraryDisk()); store.bind(account.session?.trackingID)
        try await store.commit(.init(watchlist: [film, show]), fingerprint: XCTUnwrap(store.fingerprint), revision: store.revision)
        let transport = OwnedTraktTransport(), binding = try XCTUnwrap(TraktWatchlistSync(account: account, store: store, client: client(transport), active: { true }))
        library.bindTraktWatchlist(binding)
        XCTAssertEqual(library.filteredItems(for: .saved).count, 2); XCTAssertEqual(library.filteredItems(for: .all).count, 2)
        XCTAssertTrue(library.bookmarked(Media(id: "tmdb:movie:8", type: "movie", name: "Film")))
        XCTAssertTrue(library.bookmarked(Media(id: "tmdb:tv:8", type: "series", name: "Show")))
        let displayed = try XCTUnwrap(library.filteredItems(for: .saved).first { $0.id == "tt1234567" })
        XCTAssertEqual(displayed.raw["state"], original["state"]); XCTAssertEqual(displayed.media?.name, "Local metadata")
        XCTAssertEqual(library.items.count, 1); XCTAssertEqual(library.items[0].raw, .object(original)); XCTAssertEqual(library.continuing.count, 1)
        let imported = await library.saveBookmark(try XCTUnwrap(show.importMedia), owner: account.owner, personalOwner: account.owner)
        XCTAssertTrue(imported); XCTAssertEqual(library.items.count, 2)
        library.bindTraktWatchlist(nil); XCTAssertFalse(library.bookmarked(try XCTUnwrap(film.media))); XCTAssertTrue(library.bookmarked(try XCTUnwrap(show.importMedia)))
        let requests = await transport.requests; XCTAssertTrue(requests.isEmpty); let accountRequests = await service.requests; XCTAssertEqual(accountRequests, 0)
    }
    func testFailedRemoteRemovalSurvivesRestartWithoutLosingProgressAndNewRemoteAddOrNewConnectionCanWin() async throws {
        let account = try account(), root = directory(); defer { try? FileManager.default.removeItem(at: root) }
        let row = try fixture()["cases"].array[3], film = try item(row["remote"].array[0])
        let records = row["initial"].array.map { input -> JSONValue in
            var fields = record(input).objectValue; fields["state"] = .object(["timeOffset": .integer(40_000), "duration": .integer(100_000)]); return .object(fields)
        }
        let (library, _) = try await library(account, root: root, records: records)
        let disk = OwnedTraktLibraryDisk(), store = TraktLibraryStore(owner: account.owner, disk: disk); store.bind(account.session?.trackingID)
        try await store.commit(.init(watchlist: [film]), fingerprint: XCTUnwrap(store.fingerprint), revision: store.revision)
        let transport = OwnedTraktTransport(), binding = try XCTUnwrap(TraktWatchlistSync(account: account, store: store, client: client(transport), active: { true }))
        library.bindTraktWatchlist(binding); await library.toggleBookmark(media(row["actions"].array[0])); await binding.settled()
        XCTAssertTrue(library.filteredItems(for: .saved).isEmpty); XCTAssertEqual(library.continuing.count, 2)
        for record in library.items { XCTAssertEqual(record.raw["state"], records[0]["state"]); XCTAssertEqual(record.raw["unknown"].string, "keep") }
        library.bindTraktWatchlist(nil)
        let restart = LibraryModel(cache: LibraryCache(directory: root)); await restart.setSession(nil, personalOwner: account.owner, guestOwner: account.owner, synchronize: false)
        let reopened = TraktLibraryStore(owner: account.owner, disk: disk); reopened.bind(account.session?.trackingID); try await reopened.restore()
        let restartedBinding = try XCTUnwrap(TraktWatchlistSync(account: account, store: reopened, client: client(transport), active: { true }))
        restart.bindTraktWatchlist(restartedBinding); XCTAssertTrue(restart.filteredItems(for: .saved).isEmpty)
        var newer = film; newer.contextDate = Date().addingTimeInterval(60).ISO8601Format()
        try await reopened.commit(.init(watchlist: [newer]), fingerprint: XCTUnwrap(reopened.fingerprint), revision: reopened.revision)
        XCTAssertTrue(restart.bookmarked(try XCTUnwrap(film.media)))
        try account.set(.init(accessToken: "owned-new", refreshToken: "owned-new-refresh", createdAt: 1_700_000_100, expiresIn: 7_776_000))
        XCTAssertFalse(restart.bookmarked(try XCTUnwrap(film.media)))
        let replacement = try XCTUnwrap(TraktWatchlistSync(account: account, store: reopened, client: client(transport), active: { true })); restart.bindTraktWatchlist(replacement)
        try await reopened.commit(.init(watchlist: [film]), fingerprint: XCTUnwrap(reopened.fingerprint), revision: reopened.revision)
        XCTAssertTrue(restart.bookmarked(try XCTUnwrap(film.media))); restart.bindTraktWatchlist(nil)
    }
    func testQueuedActionsRemainOrderedAndLateOldConnectionCannotPublishOrSendTheNextAction() async throws {
        let account = try account(), transport = OwnedTraktTransport([.init(status: 204, data: Data()), .init(status: 204, data: Data()), .init(status: 204, data: Data())])
        let store = TraktLibraryStore(owner: account.owner, disk: OwnedTraktLibraryDisk())
        let binding = try XCTUnwrap(TraktWatchlistSync(account: account, store: store, client: client(transport), active: { true }))
        let media = Media(id: "tt1234567", type: "movie", name: "Owned Film")
        await transport.hold("/sync/watchlist"); binding.enqueue(media, saved: true); try await waitForHold(transport)
        binding.enqueue(media, saved: false)
        try account.set(nil); await transport.release(); await binding.settled()
        let oldRequests = await transport.requests; XCTAssertEqual(oldRequests.count, 1); XCTAssertTrue(store.snapshot.watchlist.isEmpty)
        XCTAssertFalse(store.updating); XCTAssertFalse(binding.isActive)
        try account.set(.init(accessToken: "owned-next", refreshToken: "owned-next-refresh", createdAt: 1_700_000_000, expiresIn: 7_776_000))
        let next = try XCTUnwrap(TraktWatchlistSync(account: account, store: store, client: client(transport), active: { true }))
        next.enqueue(media, saved: true); next.enqueue(media, saved: false); await next.settled()
        let requests = await transport.requests
        XCTAssertEqual(requests.map { $0.url?.path }, ["/sync/watchlist", "/sync/watchlist", "/sync/watchlist/remove"])
        XCTAssertEqual(requests.dropFirst().map { $0.value(forHTTPHeaderField: "Authorization") }, ["Bearer owned-next", "Bearer owned-next"])
        XCTAssertTrue(store.snapshot.watchlist.isEmpty); XCTAssertFalse(store.updating)
    }
    func testActiveRefreshCannotRestoreRemovedTitleAndToggleDoesNotWaitForNetwork() async throws {
        let account = try account(), root = directory(); defer { try? FileManager.default.removeItem(at: root) }
        let (library, _) = try await library(account, root: root)
        let film = try item(fixture()["cases"].array[2]["remote"].array[0])
        let raw: JSONValue = .array([.object(["type": .string("movie"), "listed_at": .string(try XCTUnwrap(film.contextDate)), "movie": .object(["title": .string(film.title), "ids": film.ids.json])])])
        let transport = OwnedTraktTransport(try [TraktReply(status: 200, data: JSONEncoder().encode(raw)), TraktReply(status: 200, data: JSONEncoder().encode(JSONValue.array([]))), TraktReply(status: 204, data: Data())])
        let store = TraktLibraryStore(owner: account.owner, disk: OwnedTraktLibraryDisk()); store.bind(account.session?.trackingID)
        try await store.commit(.init(watchlist: [film]), fingerprint: XCTUnwrap(store.fingerprint), revision: store.revision); store.invalidate()
        let binding = try XCTUnwrap(TraktWatchlistSync(account: account, store: store, client: client(transport), active: { true })); library.bindTraktWatchlist(binding)
        await transport.hold("/sync/history"); let refresh = Task { await binding.refresh() }; try await waitForHold(transport)
        await library.toggleBookmark(try XCTUnwrap(film.media)); XCTAssertFalse(library.bookmarked(try XCTUnwrap(film.media)))
        let before = await transport.requests, held = await transport.isHolding; XCTAssertEqual(before.count, 2); XCTAssertTrue(held)
        await transport.release(); await refresh.value; await binding.settled()
        XCTAssertFalse(library.bookmarked(try XCTUnwrap(film.media))); XCTAssertTrue(store.snapshot.watchlist.isEmpty)
        let requests = await transport.requests; XCTAssertEqual(requests.map { $0.url?.path }, ["/sync/watchlist", "/sync/history", "/sync/watchlist/remove"])
        library.bindTraktWatchlist(nil)
    }
    func testManualTransferLeaseDoesNotDropQueuedTapAndForeignProfileBindingCannotSend() async throws {
        let account = try account(), root = directory(); defer { try? FileManager.default.removeItem(at: root) }
        let (library, _) = try await library(account, root: root), transport = OwnedTraktTransport([.init(status: 204, data: Data())])
        let store = TraktLibraryStore(owner: account.owner, disk: OwnedTraktLibraryDisk())
        let binding = try XCTUnwrap(TraktWatchlistSync(account: account, store: store, client: client(transport), active: { true })); library.bindTraktWatchlist(binding)
        let transfer = try XCTUnwrap(store.beginUpdate()), movie = Media(id: "tt1234567", type: "movie", name: "Owned")
        await library.toggleBookmark(movie); XCTAssertTrue(library.bookmarked(movie))
        for _ in 0..<20 { await Task.yield() }; let before = await transport.requests; XCTAssertTrue(before.isEmpty)
        store.endUpdate(transfer); await binding.settled(); let sent = await transport.requests; XCTAssertEqual(sent.count, 1)
        let foreign = try self.account(), foreignStore = TraktLibraryStore(owner: foreign.owner, disk: OwnedTraktLibraryDisk())
        let foreignBinding = try XCTUnwrap(TraktWatchlistSync(account: foreign, store: foreignStore, client: client(transport), active: { true }))
        library.bindTraktWatchlist(foreignBinding); XCTAssertFalse(foreignBinding.isActive)
        library.bindTraktWatchlist(nil); await library.toggleBookmark(movie); await binding.settled()
        let after = await transport.requests; XCTAssertEqual(after.count, 1); XCTAssertFalse(library.bookmarked(movie))
    }
}

import XCTest
@testable import Harbor

@MainActor final class LibraryHistoryTests: XCTestCase {
    private func fixture() throws -> JSONValue {
        let file = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "library-history-reference", withExtension: "json", subdirectory: "Fixtures"))
        let value = try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: file))
        XCTAssertEqual(value["reference"].string, "0834340cec5531650bfe78cd628628702e636987")
        XCTAssertEqual(value["actual_original_typescript_executed"], .bool(true)); XCTAssertEqual(value["provider_network_requests"].integer, 0)
        XCTAssertEqual(value["executed_module_hashes"].objectValue.count, 3); return value
    }
    private func remote(_ value: JSONValue) -> TraktLibraryItem {
        let movie = value["type"].string == "movie"
        var ids: [String: JSONValue] = [:]
        ids["imdb"] = movie ? value["imdb"] : value["showImdb"]; ids["tmdb"] = movie ? value["tmdb"] : value["showTmdb"]
        return .init(type: movie ? .movie : .show, title: value["title"].string ?? "Owned", year: value["year"].integer, ids: .init(.object(ids)), contextDate: value["watchedAt"].string)
    }
    private func json(_ entries: [LibraryHistoryEntry]) throws -> JSONValue {
        let rows = entries.map { entry -> JSONValue in
            .object(["id": .string(entry.id), "type": entry.media.map { .string($0.type) } ?? .null, "name": entry.media.map { .string($0.name) } ?? .null,
                "localID": entry.localID.map(JSONValue.string) ?? .null, "date": entry.date.map(JSONValue.number) ?? .null, "watchedAt": entry.watchedAt.map(JSONValue.number) ?? .null,
                "season": entry.season.map { .integer(Int64($0)) } ?? .null, "episode": entry.episode.map { .integer(Int64($0)) } ?? .null,
                "progress": .number(entry.progress), "watched": .bool(entry.watched), "durationMs": .number(entry.durationMs), "timeOffsetMs": .number(entry.timeOffsetMs)])
        }
        return try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(JSONValue.array(rows)))
    }
    private func account() throws -> TraktAccountStore {
        let account = TraktAccountStore(owner: "owned-history-" + UUID().uuidString, persistence: OwnedTraktPersistence())
        try account.load(); try account.set(.init(accessToken: "owned-access", refreshToken: "owned-refresh", createdAt: 1_700_000_000, expiresIn: 7_776_000)); return account
    }
    private func client(_ transport: OwnedTraktTransport) -> TraktClient {
        let clock = OwnedTraktClock(); return .init(transport: { try await transport.send($0) }, sleep: { clock.advance($0) }, now: { clock.now() })
    }
    private func reply(_ value: JSONValue, status: Int = 200) throws -> TraktReply { .init(status: status, data: try JSONEncoder().encode(value)) }
    private func library(_ account: TraktAccountStore, root: URL, records: [JSONValue]) async throws -> (LibraryModel, OwnedRetirementOfflineService) {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let cache = LibraryCache(directory: root), service = OwnedRetirementOfflineService(); try await cache.save(records, owner: account.owner)
        let library = LibraryModel(service: service, writeQueue: .init(service: service, directory: root), cache: cache)
        await library.setSession(nil, personalOwner: account.owner, guestOwner: account.owner, synchronize: false); return (library, service)
    }
    func testExecutedDesktopHistoryPreservesFilteringPriorityDatesProgressAndBothSourceCoordinateSchemes() throws {
        let value = try fixture(); XCTAssertEqual(value["cases"].array.count, 8)
        for row in value["cases"].array {
            let records = row["local"].array.map { LibraryRecord(raw: $0) }
            let entries = LibraryHistoryEntry.merge(local: records, remote: row["remote"].array.map(remote))
            XCTAssertEqual(try json(entries), row["expected"], row["name"].string ?? "")
            XCTAssertEqual(Set(records.filter(LibraryHistoryEntry.eligible).map(\.id)), Set(row["filteredIDs"].array.compactMap(\.string)))
        }
        XCTAssertEqual(value["css"]["entranceMilliseconds"].integer, 440); XCTAssertEqual(value["css"]["entranceOffset"].integer, 10)
        XCTAssertEqual(value["css"]["reducedMotionDisables"], .bool(true))
    }
    func testHistoryRefreshUsesOnlyTwoHundredHistoryItemsAndPreservesTheIndependentlyChangedWatchlist() async throws {
        let account = try account(), root = FileManager.default.temporaryDirectory.appendingPathComponent("owned-history-read-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let (library, service) = try await library(account, root: root, records: fixture()["cases"].array[0]["local"].array)
        let store = TraktLibraryStore(owner: account.owner, disk: OwnedTraktLibraryDisk()), scope = OwnedTraktScope()
        let payload: JSONValue = .array([.object(["type": .string("movie"), "movie": .object(["title": .string("Remote"), "ids": .object(["imdb": .string("tt9999999")])]), "watched_at": .string("2026-10-27T00:00:00Z")])])
        let transport = OwnedTraktTransport(try [reply(payload), reply(.null, status: 503)])
        let model = LibraryHistoryModel(library: library, account: account, store: store, client: client(transport), active: { scope.active })
        model.loadAccount(); await transport.hold("/sync/history"); let refresh = Task { await model.refresh() }
        for _ in 0..<100 { if await transport.isHolding { break }; try await Task.sleep(for: .milliseconds(20)) }
        let held = await transport.isHolding; XCTAssertTrue(held)
        let item = TraktLibraryItem(type: .movie, title: "Keep watchlist", year: nil, ids: .init(.object(["imdb": .string("tt1111111")])))
        try await store.commit(.init(watchlist: [item]), fingerprint: XCTUnwrap(store.fingerprint), revision: store.revision)
        await transport.release(); await refresh.value
        XCTAssertEqual(store.snapshot.watchlist, [item]); XCTAssertEqual(model.entries.count, 3); XCTAssertNil(model.error)
        await model.refresh(force: true); XCTAssertNotNil(model.error); XCTAssertEqual(model.entries.count, 3)
        let requests = await transport.requests; XCTAssertEqual(requests.count, 2)
        XCTAssertTrue(requests.allSatisfy { $0.url?.absoluteString == "https://api.trakt.tv/sync/history?limit=200" && $0.value(forHTTPHeaderField: "Authorization") == "Bearer owned-access" })
        let old = model.entries; scope.active = false; XCTAssertTrue(model.entries.isEmpty); XCTAssertEqual(old.count, 3)
        let accountRequests = await service.requests; XCTAssertEqual(accountRequests, 0)
    }
    func testRemoveFromActualIndependentHistoryPreservesRawProgressAndUnknownFieldsAcrossRestart() async throws {
        let account = try account(), root = FileManager.default.temporaryDirectory.appendingPathComponent("owned-history-remove-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        var raw = try fixture()["cases"].array[0]["local"].array[0].objectValue; raw["unknown"] = .string("keep")
        let (library, service) = try await library(account, root: root, records: [.object(raw)])
        let entry = try XCTUnwrap(LibraryHistoryEntry.merge(local: library.items, remote: []).first)
        let wrong = await library.removeHistory(entry.record, owner: "wrong", personalOwner: account.owner); XCTAssertFalse(wrong)
        let removed = await library.removeHistory(entry.record, owner: account.owner, personalOwner: account.owner); XCTAssertTrue(removed)
        XCTAssertTrue(LibraryHistoryEntry.merge(local: library.items, remote: []).isEmpty)
        let reopened = try await LibraryCache(directory: root).readSnapshot(owner: account.owner), saved = try XCTUnwrap(reopened.items.first)
        XCTAssertEqual(saved.raw["removed"], .bool(true)); XCTAssertEqual(saved.raw["temp"], .bool(false))
        XCTAssertEqual(saved.raw["state"], raw["state"]); XCTAssertEqual(saved.raw["unknown"].string, "keep")
        let requests = await service.requests; XCTAssertEqual(requests, 0)
    }
    func testLegacyPresentationKeepsPosterDefaultAndModePersistsWithinItsActualLibraryOwner() async throws {
        let legacy = try JSONDecoder().decode(LibraryDisplay.self, from: Data(#"{"filter":"watched","kind":"series","sort":"title","grouped":false}"#.utf8))
        XCTAssertEqual(legacy.historyView, .posters); XCTAssertEqual(legacy.sort, .title); XCTAssertFalse(legacy.grouped)
        let account = try account(), root = FileManager.default.temporaryDirectory.appendingPathComponent("owned-history-mode-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root); try? KeychainStore().remove(LibraryPresentation.key(owner: account.owner)) }
        let (library, _) = try await library(account, root: root, records: [])
        XCTAssertTrue(library.canChangePresentation)
        library.changeDisplay { $0.historyView = .episodes; $0.filter = .watched; $0.grouped = false }
        let restarted = LibraryModel(cache: LibraryCache(directory: root)); await restarted.setSession(nil, personalOwner: account.owner, guestOwner: account.owner, synchronize: false)
        XCTAssertEqual(restarted.presentation.display.historyView, .episodes); XCTAssertFalse(restarted.presentation.display.grouped)
        await restarted.setSession(nil, personalOwner: "foreign-" + account.owner, guestOwner: "foreign-" + account.owner, synchronize: false)
        XCTAssertEqual(restarted.presentation.display.historyView, .posters)
    }
    func testHistoryGroupingUsesModifiedDateWhileEpisodeCardRetainsLastWatchedAndHint() throws {
        let value = try fixture(), row = try XCTUnwrap(value["cases"].array.first { $0["name"].string == "group-date-separate-from-last-watched" })
        let entries = LibraryHistoryEntry.merge(local: row["local"].array.map { .init(raw: $0) }, remote: [])
        var display = LibraryDisplay(); display.filter = .watched; display.grouped = false
        XCTAssertEqual(LibraryListing.select(entries.map(\.listingRecord), display: display, query: "").map(\.id), ["recent", "older"])
        let older = try XCTUnwrap(entries.first { $0.id == "older" }); XCTAssertGreaterThan(try XCTUnwrap(older.watchedAt), try XCTUnwrap(older.date))
        let anime = try XCTUnwrap(LibraryHistoryEntry.merge(local: value["cases"].array[2]["local"].array.map { .init(raw: $0) }, remote: []).first { $0.id == "kitsu:1" })
        XCTAssertEqual(anime.episodeHint?.season, 1); XCTAssertEqual(anime.episodeHint?.episode, 99)
        let special = try XCTUnwrap(LibraryHistoryEntry.merge(local: value["cases"].array[2]["local"].array.map { .init(raw: $0) }, remote: []).first { $0.id == "special" })
        XCTAssertEqual(special.episodeHint?.season, 0)
    }
    func testHeldReplyAfterProfileChangeCannotPublishAndDisconnectedLocalHistoryDoesNotNeedStremio() async throws {
        let account = try account(), root = FileManager.default.temporaryDirectory.appendingPathComponent("owned-history-stale-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let (library, _) = try await library(account, root: root, records: fixture()["cases"].array[0]["local"].array)
        let transport = OwnedTraktTransport(try [reply(.array([]))]), store = TraktLibraryStore(owner: account.owner, disk: OwnedTraktLibraryDisk())
        let model = LibraryHistoryModel(library: library, account: account, store: store, client: client(transport), active: { true })
        await transport.hold("/sync/history"); let refresh = Task { await model.refresh() }
        for _ in 0..<100 { if await transport.isHolding { break }; try await Task.sleep(for: .milliseconds(20)) }
        let held = await transport.isHolding; XCTAssertTrue(held)
        await library.setSession(nil, personalOwner: "other", guestOwner: "other", synchronize: false)
        await transport.release(); await refresh.value; XCTAssertTrue(model.entries.isEmpty); XCTAssertNil(model.error)
        await library.setSession(nil, personalOwner: account.owner, guestOwner: account.owner, synchronize: false); try account.set(nil)
        let local = LibraryHistoryModel(library: library, account: account, store: store, client: client(transport), active: { true })
        await local.refresh(); XCTAssertEqual(local.entries.count, 2); XCTAssertFalse(library.hasCloudSession)
        let requests = await transport.requests; XCTAssertEqual(requests.count, 1)
    }
}

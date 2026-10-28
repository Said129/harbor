import XCTest
@testable import Harbor

actor OwnedTraktLibraryDisk: TraktLibraryPersistence {
    private var values: [String: (String, TraktLibrarySnapshot)] = [:]
    func read(owner: String, fingerprint: String) -> TraktLibrarySnapshot? { values[owner].flatMap { $0.0 == fingerprint ? $0.1 : nil } }
    func write(_ value: TraktLibrarySnapshot, owner: String, fingerprint: String) { values[owner] = (fingerprint, value) }
}

@MainActor final class TraktLibraryTests: XCTestCase {
    private func fixture() throws -> JSONValue {
        let file = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "trakt-library-reference", withExtension: "json", subdirectory: "Fixtures"))
        let value = try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: file))
        XCTAssertEqual(value["reference"].string, "0834340cec5531650bfe78cd628628702e636987")
        XCTAssertEqual(value["actual_original_typescript_executed"], .bool(true)); XCTAssertEqual(value["provider_network_requests"].integer, 0)
        XCTAssertEqual(value["executed_module_hashes"].objectValue.count, 6); return value
    }
    private func account(owner: String = "owned-trakt-library", persistence: OwnedTraktPersistence? = nil) throws -> TraktAccountStore {
        let account = TraktAccountStore(owner: owner, persistence: persistence ?? OwnedTraktPersistence()); try account.load()
        try account.set(.init(accessToken: "owned-access", refreshToken: "owned-refresh", createdAt: 1_700_000_000, expiresIn: 7_776_000)); return account
    }
    private func reply(_ value: JSONValue, status: Int = 200) throws -> TraktReply { .init(status: status, data: try JSONEncoder().encode(value)) }
    private func client(_ transport: OwnedTraktTransport) -> TraktClient {
        let clock = OwnedTraktClock(); return .init(transport: { try await transport.send($0) }, sleep: { clock.advance($0) }, now: { clock.now() })
    }
    private func item(_ value: JSONValue) throws -> TraktLibraryItem {
        .init(type: try XCTUnwrap(.init(rawValue: value["type"].string ?? "")), title: value["title"].string ?? "", year: value["year"].integer, ids: .init(value["ids"]), contextDate: value["contextDate"].string)
    }
    private func itemsJSON(_ items: [TraktLibraryItem]) -> JSONValue {
        .array(items.map { item in
            var fields: [String: JSONValue] = ["type": .string(item.type.rawValue), "title": .string(item.title), "year": item.year.map { .integer(Int64($0)) } ?? .null, "ids": item.ids.json]
            if let date = item.contextDate { fields["contextDate"] = .string(date) }; return .object(fields)
        })
    }
    private func metaJSON(_ records: [LibraryRecord], includeYear: Bool) -> JSONValue {
        .array(records.compactMap { record in
            guard let media = record.media else { return nil }
            var fields: [String: JSONValue] = ["id": .string(media.id), "type": .string(media.type), "name": .string(media.name)]
            if includeYear, let year = media.releaseInfo { fields["releaseInfo"] = .string(year) }; return .object(fields)
        })
    }
    func testExecutedDesktopWatchlistAndHistoryPreserveBothIdentifierRoutesDateFieldsAndShowDeduplication() throws {
        let value = try fixture(); XCTAssertEqual(value["listCases"].array.count, 7); XCTAssertEqual(value["historyCases"].array.count, 4)
        for row in value["listCases"].array where row["status"].integer == nil {
            let items = try TraktLibraryItem.watchlist(row["raw"])
            XCTAssertEqual(itemsJSON(items), row["expected"], row["name"].string ?? "")
            XCTAssertEqual(metaJSON(items.compactMap { $0.record() }, includeYear: true), row["expectedMetas"], row["name"].string ?? "")
        }
        for row in value["historyCases"].array {
            let snapshot = TraktLibrarySnapshot(history: try TraktLibraryItem.history(row["raw"]))
            XCTAssertEqual(metaJSON(snapshot.historyRecords, includeYear: false), .array(row["expectedDated"].array.map { $0["meta"] }), row["name"].string ?? "")
            XCTAssertEqual(snapshot.history.map(\.historyID), row["expected"].array.map { $0["id"].integer })
            XCTAssertEqual(snapshot.history.map(\.season), row["expected"].array.map { $0["season"].integer })
            XCTAssertEqual(snapshot.history.map(\.contextDate), row["expected"].array.map { $0["watchedAt"].string })
        }
        XCTAssertThrowsError(try TraktLibraryItem.watchlist(.object([:])))
        XCTAssertThrowsError(try TraktLibraryItem.history(.null))
    }
    func testExecutedDesktopExportPlansKeepTypedDeduplicationAnimeSkipsAndHundredItemBoundaries() throws {
        let rows = try fixture()["plans"].array; XCTAssertEqual(rows.count, 5)
        for row in rows {
            let plan = TraktWatchlistExportPlan(row["sources"].array), expected = row["expected"]
            XCTAssertEqual(.array(plan.movies), expected["movies"], row["name"].string ?? "")
            XCTAssertEqual(.array(plan.shows), expected["shows"]); XCTAssertEqual(plan.total, expected["total"].integer)
            XCTAssertEqual(plan.skippedAnime, expected["skippedAnime"].integer)
            XCTAssertTrue(plan.chunks.allSatisfy { $0["movies"].array.count + $0["shows"].array.count <= 100 })
        }
        XCTAssertNil(TraktLibraryTarget(Media(id: "kitsu:1", type: "series", name: "Owned")))
        let show = try XCTUnwrap(TraktLibraryTarget(Media(id: "tt1234567", type: "series", name: "Owned")))
        XCTAssertEqual(show.kind, .show); XCTAssertEqual(show.body["shows"].array.first?["ids"]["imdb"].string, "tt1234567")
    }
    func testExecutedDesktopPartialExportsReportConfirmedCountsAndKeepSendingAfterOneFailedChunk() async throws {
        let reference = try fixture(), rows = reference["exportCases"].array, source = try XCTUnwrap(reference["plans"].array.first { $0["name"].string == "batch-boundaries" })
        XCTAssertEqual(rows.count, 4)
        for row in rows {
            let account = try account(), store = TraktLibraryStore(owner: account.owner, disk: OwnedTraktLibraryDisk())
            let pattern = row["pattern"].string
            let replies = try row["requests"].array.enumerated().map { index, request -> TraktReply in
                if pattern == "error" || (pattern == "partial" && index == 0) { return try reply(.null, status: 503) }
                let body = request["body"]
                let value: JSONValue = pattern == "none" ? .object(["not_found": body]) : .object(["added": .object(["movies": .integer(Int64(body["movies"].array.count))]), "existing": .object(["shows": .integer(Int64(body["shows"].array.count))])])
                return try reply(value)
            }
            let transport = OwnedTraktTransport(replies), model = TraktLibraryModel(account: account, store: store, client: client(transport), active: { true })
            let result = await model.export(.init(source["sources"].array))
            if row["expectedError"] == .bool(true) { XCTAssertNil(result); XCTAssertNotNil(model.error) }
            else { XCTAssertEqual(result?.synced, row["expected"]["synced"].integer); XCTAssertEqual(result?.unmatched, row["expected"]["unmatched"].integer) }
            let requests = await transport.requests
            XCTAssertEqual(try requests.map { try JSONDecoder().decode(JSONValue.self, from: XCTUnwrap($0.httpBody)) }, row["requests"].array.map { $0["body"] })
            XCTAssertTrue(requests.allSatisfy { $0.url?.path == "/sync/watchlist" && $0.value(forHTTPHeaderField: "Authorization") == "Bearer owned-access" })
            XCTAssertFalse(model.transferring); XCTAssertFalse(store.updating)
        }
    }
    func testExecutedDesktopImportsPreferIMDbContinueAfterFailedWritesAndReportEveryProcessedItem() async throws {
        let rows = try fixture()["importCases"].array; XCTAssertEqual(rows.count, 2)
        for row in rows {
            let account = try account(), model = TraktLibraryModel(account: account, store: .init(owner: account.owner, disk: OwnedTraktLibraryDisk()), active: { true })
            let items = try row["items"].array.map(item), failedID = row["failedID"].string
            var requests: [JSONValue] = []
            let count = await model.importItems(items) { media in
                requests.append(.object(["id": .string(media.id), "type": .string(media.type), "name": .string(media.name)])); return media.id != failedID
            }
            XCTAssertEqual(.array(requests), row["requests"]); XCTAssertEqual(count, row["expected"]["added"].integer)
            XCTAssertEqual(model.completed, items.count); XCTAssertEqual(model.total, items.count)
        }
    }
    func testRefreshCachesCompleteListsPreservesOfflineDataAcrossRestartAndSeparatesAccountLineage() async throws {
        let reference = try fixture(), account = try account(), disk = OwnedTraktLibraryDisk(), store = TraktLibraryStore(owner: account.owner, disk: disk)
        let list = try XCTUnwrap(reference["listCases"].array.first)["raw"], history = try XCTUnwrap(reference["historyCases"].array.first)["raw"]
        let transport = OwnedTraktTransport(try [reply(list), reply(history), reply(.null, status: 503)])
        let model = TraktLibraryModel(account: account, store: store, client: client(transport), active: { true })
        await model.refresh(); XCTAssertNil(model.error); XCTAssertEqual(model.watchlist.count, 2); XCTAssertEqual(model.history.count, 2)
        await model.refresh(); let afterTTL = await transport.requests.count; XCTAssertEqual(afterTTL, 2)
        let reopened = TraktLibraryStore(owner: account.owner, disk: disk); reopened.bind(account.session?.trackingID); try await reopened.restore()
        XCTAssertEqual(reopened.snapshot, store.snapshot)
        await model.refresh(force: true); XCTAssertNotNil(model.error); XCTAssertEqual(model.watchlist.count, 2)
        let requests = await transport.requests; XCTAssertEqual(requests[0].url?.absoluteString, "https://api.trakt.tv/sync/watchlist?sort_by=added&sort_how=desc")
        XCTAssertEqual(requests[1].url?.absoluteString, "https://api.trakt.tv/sync/history?limit=200")
        XCTAssertTrue(requests.allSatisfy { $0.value(forHTTPHeaderField: "Cookie") == nil })
        store.bind(UUID()); XCTAssertTrue(store.snapshot.watchlist.isEmpty); try await store.restore(); XCTAssertTrue(store.snapshot.watchlist.isEmpty)
        let other = TraktLibraryStore(owner: "owned-other-profile", disk: disk); other.bind(account.session?.trackingID); try await other.restore(); XCTAssertTrue(other.snapshot.watchlist.isEmpty)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("owned-trakt-cache-" + UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let actual = TraktLibraryDisk(root: root), fingerprint = try XCTUnwrap(reopened.fingerprint)
        try await actual.write(reopened.snapshot, owner: account.owner, fingerprint: fingerprint)
        let saved = try await actual.read(owner: account.owner, fingerprint: fingerprint)
        XCTAssertEqual(saved, reopened.snapshot)
        let foreign = try await actual.read(owner: account.owner, fingerprint: "different"), absent = try await actual.read(owner: "different", fingerprint: fingerprint)
        XCTAssertNil(foreign); XCTAssertNil(absent)
        let encoded = try Data(contentsOf: root.appendingPathComponent(EBookShelf.hash(account.owner) + ".json"))
        XCTAssertFalse(String(decoding: encoded, as: UTF8.self).contains("owned-access"))
    }
    func testHeldHistoryAndChangedProfileCannotPublishAPartialListOrContinueAnExport() async throws {
        let reference = try fixture(), account = try account(), store = TraktLibraryStore(owner: account.owner, disk: OwnedTraktLibraryDisk()), scope = OwnedTraktScope()
        let list = try XCTUnwrap(reference["listCases"].array.first)["raw"], transport = OwnedTraktTransport(try [reply(list), reply(.array([]))])
        await transport.hold("/sync/history")
        let model = TraktLibraryModel(account: account, store: store, client: client(transport), active: { scope.active })
        let operation = Task { await model.refresh() }
        for _ in 0..<100 { if await transport.isHolding { break }; try await Task.sleep(for: .milliseconds(20)) }
        let held = await transport.isHolding; XCTAssertTrue(held); XCTAssertTrue(store.snapshot.watchlist.isEmpty)
        scope.active = false; await transport.release(); await operation.value
        XCTAssertTrue(store.snapshot.watchlist.isEmpty); XCTAssertNil(model.error)
        let result = await model.export(.init([.object(["id": .string("tt1234567")])]))
        XCTAssertNil(result); let requests = await transport.requests; XCTAssertEqual(requests.count, 2)
    }
    func testActualIndependentLibraryImportIsIdempotentPreservesProgressAndSurvivesRestartWithoutAccountRequests() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("owned-trakt-import-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true); defer { try? FileManager.default.removeItem(at: root) }
        let account = try account(owner: "owned-person"), service = OwnedRetirementOfflineService(), cache = LibraryCache(directory: root)
        let queue = LibraryWriteQueue(service: service, directory: root), library = LibraryModel(service: service, writeQueue: queue, cache: cache)
        let original: JSONValue = .object(["_id": .string("tt1234567"), "name": .string("Owned Film"), "type": .string("movie"), "removed": .bool(false), "temp": .bool(false), "unknown": .string("keep"), "state": .object(["timeOffset": .integer(40_000), "duration": .integer(100_000)])])
        try await cache.save([original], owner: "owned-import"); await library.setSession(nil, personalOwner: "owned-person", guestOwner: "owned-import", synchronize: false)
        let model = TraktLibraryModel(account: account, store: .init(owner: account.owner, disk: OwnedTraktLibraryDisk()), active: { true })
        let values = try fixture()["listCases"].array[0]["expected"].array.map(item)
        let save: @MainActor (Media) async -> Bool = { await library.saveBookmark($0, owner: "owned-import", personalOwner: "owned-person") }
        let first = await model.importItems(values, save: save), second = await model.importItems(values, save: save)
        XCTAssertEqual(first, 2); XCTAssertEqual(second, 2); XCTAssertEqual(library.items.count, 2)
        let restart = LibraryModel(service: service, writeQueue: queue, cache: LibraryCache(directory: root))
        await restart.setSession(nil, personalOwner: "owned-person", guestOwner: "owned-import", synchronize: false)
        XCTAssertFalse(restart.hasCloudSession); XCTAssertEqual(restart.items.count, 2)
        let saved = try XCTUnwrap(restart.items.first { $0.id == "tt1234567" }); XCTAssertEqual(saved.raw, original)
        let wrongOwner = await restart.saveBookmark(Media(id: "tt99999", type: "movie", name: "Wrong"), owner: "different", personalOwner: "owned-person")
        XCTAssertFalse(wrongOwner); let requests = await service.requests; XCTAssertEqual(requests, 0)
    }
    func testExecutedDesktopFilteringKeepsCountsAndSearchIndependentOfSourceAndWatchHistory() throws {
        let value = try fixture(), records = try TraktLibraryItem.watchlist(value["listCases"].array[0]["raw"]).compactMap { $0.record() }
        let rows = value["filterCases"].array; XCTAssertEqual(rows.count, 12)
        for row in rows {
            var display = LibraryDisplay(); display.kind = try XCTUnwrap(.init(rawValue: row["kind"].string ?? ""))
            let selected = LibraryListing.select(records, display: display, query: row["query"].string ?? "")
            XCTAssertEqual(Set(selected.map(\.id)), Set(row["expectedIDs"].array.compactMap(\.string)))
            XCTAssertEqual(records.count, row["counts"]["all"].integer)
            XCTAssertEqual(records.filter { $0.media?.type == "movie" }.count, row["counts"]["movie"].integer)
        }
    }
    func testWatchlistActionsUseTheirTypedBucketsMatchAliasesAndPreserveHistoryWithoutDuplicateCards() async throws {
        let reference = try fixture(), account = try account(), store = TraktLibraryStore(owner: account.owner, disk: OwnedTraktLibraryDisk())
        store.bind(account.session?.trackingID)
        let initial = TraktLibrarySnapshot(watchlist: try TraktLibraryItem.watchlist(reference["listCases"].array[0]["raw"]), history: try TraktLibraryItem.history(reference["historyCases"].array[0]["raw"]))
        try await store.commit(initial, fingerprint: XCTUnwrap(store.fingerprint), revision: store.revision)
        let transport = OwnedTraktTransport([.init(status: 204, data: Data()), .init(status: 204, data: Data())])
        let model = TraktLibraryModel(account: account, store: store, client: client(transport), active: { true })
        await model.setWatchlisted(false, target: .init(kind: .movie, ids: .init(.object(["tmdb": .integer(8)]))), title: "Owned Film", year: 2024)
        XCTAssertEqual(model.watchlist.count, 1); XCTAssertEqual(store.snapshot.history, initial.history)
        await model.setWatchlisted(true, target: initial.watchlist[1].target, title: "Owned Show", year: 2022)
        XCTAssertEqual(model.watchlist.count, 1); XCTAssertFalse(store.updating); XCTAssertNil(model.error)
        await model.setWatchlisted(true, target: .init(kind: .show, ids: .init(.null)), title: "Unmapped", year: nil)
        let requests = await transport.requests
        XCTAssertEqual(requests.map { $0.url!.path }, ["/sync/watchlist/remove", "/sync/watchlist"])
        let bodies = try requests.map { try JSONDecoder().decode(JSONValue.self, from: XCTUnwrap($0.httpBody)) }
        XCTAssertEqual(bodies[0]["movies"].array.first?["ids"]["tmdb"].integer, 8)
        XCTAssertEqual(bodies[1]["shows"].array.first?["ids"]["imdb"].string, "tt1234568")
    }
}

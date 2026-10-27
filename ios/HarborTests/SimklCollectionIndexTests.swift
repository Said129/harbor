import XCTest
@testable import Harbor

private actor OwnedIndexRelations {
    private(set) var requests: [URLRequest] = []
    private var continuation: CheckedContinuation<SimklReply, Never>?
    func send(_ request: URLRequest) async -> SimklReply {
        requests.append(request)
        if requests.count == 2 { return await withCheckedContinuation { continuation = $0 } }
        return reply(request)
    }
    private func reply(_ request: URLRequest) -> SimklReply {
        .init(status: 200, data: Data((request.url?.path.hasSuffix("/1") == true
            ? "{\"relations\":[{\"is_direct\":true,\"ids\":{\"simkl_id\":2}}]}" : "{\"relations\":[]}").utf8))
    }
    func release() { continuation?.resume(returning: .init(status: 200, data: Data("{}".utf8))); continuation = nil }
}
@MainActor final class SimklCollectionIndexTests: XCTestCase {
    private func item(_ id: Int, kind: SimklMediaKind, title: String, status: SimklListStatus) -> SimklListItem {
        .init(kind: kind, ids: .init(.object(["simkl": .integer(Int64(id))])), title: title, year: 2024,
            status: status, addedAt: "2024-01-01T00:00:00Z", watchedEpisodes: [])
    }
    private func snapshot() -> SimklLibrarySnapshot {
        var result = SimklLibrarySnapshot()
        for index in 1...200 {
            for value in [item(index, kind: .anime, title: "Owned Saga \(index)", status: .completed),
                          item(1_000 + index, kind: .anime, title: "Owned Saga \(index) Season 2", status: .watching),
                          item(index, kind: .show, title: "Owned Show \(index)", status: .watching)] { result.items[value.id] = value }
        }
        for index in 1...300 { let value = item(index, kind: .movie, title: "Owned Film \(index)", status: .plantowatch); result.items[value.id] = value }
        return result
    }
    func testPreparedRowsKeepCountsRepresentativeTitlesSearchAndDirectRelationMergesAcrossNineHundredItems() {
        let snapshot = snapshot(), index = SimklCollectionIndex(snapshot)
        XCTAssertEqual(snapshot.items.count, 900)
        XCTAssertEqual(index.counts(kind: .anime)[.watching], 200); XCTAssertEqual(index.counts(kind: .anime)[.completed], 200)
        XCTAssertEqual(index.counts(kind: .show)[.watching], 200); XCTAssertEqual(index.counts(kind: .movie)[.plantowatch], 300)
        let matches = index.rows(kind: .anime, status: .watching, query: "  ÓWNED SAGA 12  ")
        XCTAssertEqual(matches.count, 11); XCTAssertTrue(matches.allSatisfy { $0.items.count == 2 })
        XCTAssertTrue(matches.allSatisfy { !$0.media.name.contains("Season 2") && $0.media.id.hasPrefix("simkl:") })
        let merged = SimklCollectionIndex(snapshot, relations: ["anime:1": ["anime:2"]])
        XCTAssertEqual(merged.counts(kind: .anime)[.watching], 199)
        let linked = merged.rows(kind: .anime, status: .completed, query: "Owned Saga 1").first { $0.items.count == 4 }
        XCTAssertNotNil(linked); XCTAssertEqual(linked?.items.filter { $0.status == .watching }.count, 2)
    }
    func testTypingAndStatusChangesReuseThePreparedCollectionUntilTheSnapshotOrAccountActuallyChanges() async throws {
        let account = SimklAccountStore(owner: "owned-prepared-index", persistence: OwnedSimklLibraryAccount()); try account.load()
        let disk = OwnedSimklLibraryDisk(), store = SimklLibraryStore(owner: account.owner, disk: disk); store.bind(account.session?.accessToken)
        var snapshot = snapshot()
        try await store.commit(snapshot, fingerprint: XCTUnwrap(store.fingerprint), expectedRevision: store.revision)
        let model = SimklLibraryModel(account: account, store: store, active: { true }), first = model.collection
        let reopenedStore = SimklLibraryStore(owner: account.owner, disk: disk); reopenedStore.bind(account.session?.accessToken)
        let reopenedModel = SimklLibraryModel(account: account, store: reopenedStore, active: { true }), emptyBeforeRestore = reopenedModel.collection
        try await reopenedStore.restore()
        XCTAssertFalse(reopenedModel.collection === emptyBeforeRestore)
        XCTAssertEqual(reopenedModel.collection.counts(kind: .movie)[.plantowatch], 300, "An offline cache restore must invalidate the previously empty projection")
        for query in ["O", "Ow", "Own", "Owne", "Owned", "Owned Saga", "Owned Saga 12", ""] {
            for status in SimklListStatus.allCases { _ = model.collection.rows(kind: .anime, status: status, query: query) }
            XCTAssertTrue(model.collection === first, "Search and status selection must not rebuild normalized franchises")
        }
        let extra = item(999, kind: .movie, title: "A newly synced film", status: .plantowatch)
        snapshot.items[extra.id] = extra
        try await store.commit(snapshot, fingerprint: XCTUnwrap(store.fingerprint), expectedRevision: store.revision)
        let updated = model.collection
        XCTAssertFalse(updated === first); XCTAssertEqual(updated.rows(kind: .movie, status: .plantowatch, query: "newly").map(\.media.name), ["A newly synced film"])
        XCTAssertTrue(model.collection === updated)
        store.bind("owned-other-account")
        let empty = model.collection
        XCTAssertFalse(empty === updated); XCTAssertTrue(empty.rows(kind: .anime, status: .watching).isEmpty)
    }
    func testCancelledRelationBatchPublishesNothingAndTheNextAppearanceCanRetryEveryUncommittedGroup() async throws {
        let account = SimklAccountStore(owner: "owned-index-relations", persistence: OwnedSimklLibraryAccount()); try account.load()
        let store = SimklLibraryStore(owner: account.owner, disk: OwnedSimklLibraryDisk()); store.bind(account.session?.accessToken)
        let first = item(1, kind: .anime, title: "Owned Alpha", status: .watching), second = item(2, kind: .anime, title: "Owned Beta", status: .watching)
        try await store.commit(.init(items: [first.id: first, second.id: second]), fingerprint: XCTUnwrap(store.fingerprint), expectedRevision: store.revision)
        let transport = OwnedIndexRelations(), clock = OwnedSimklClock()
        let client = SimklClient(transport: { await transport.send($0) }, sleep: { clock.advance($0) }, now: { clock.now() })
        let model = SimklLibraryModel(account: account, store: store, client: client, active: { true }), original = model.collection
        let loading = Task { await model.loadRelations() }
        for _ in 0..<100 { if await transport.requests.count == 2 { break }; try await Task.sleep(for: .milliseconds(10)) }
        let waiting = await transport.requests; XCTAssertEqual(waiting.count, 2)
        model.cancel(); await transport.release(); await loading.value
        XCTAssertTrue(model.relations.isEmpty); XCTAssertTrue(model.collection === original)
        await model.loadRelations()
        let requests = await transport.requests; XCTAssertEqual(requests.count, 4)
        XCTAssertEqual(requests.map { $0.url!.path }, ["/anime/1", "/anime/2", "/anime/1", "/anime/2"])
        XCTAssertTrue(requests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == nil })
        XCTAssertFalse(model.collection === original); XCTAssertEqual(model.collection.counts(kind: .anime)[.watching], 1)
    }
}

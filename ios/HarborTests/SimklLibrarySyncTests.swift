import XCTest
@testable import Harbor

@MainActor final class OwnedSimklLibraryAccount: SimklAccountPersistence {
    var session: SimklSession? = .init(accessToken: "owned-library-token", username: "Owned")
    func readSimklSession(owner: String) throws -> SimklSession? { session }
    func writeSimklSession(_ session: SimklSession?, owner: String) throws { self.session = session }
}
actor OwnedSimklLibraryDisk: SimklLibraryPersistence {
    private(set) var values: [String: (String, SimklLibrarySnapshot)] = [:]
    func read(owner: String, fingerprint: String) -> SimklLibrarySnapshot? { values[owner]?.0 == fingerprint ? values[owner]?.1 : nil }
    func write(_ value: SimklLibrarySnapshot, owner: String, fingerprint: String) { values[owner] = (fingerprint, value) }
    func remove(owner: String) { values[owner] = nil }
}
@MainActor private final class OwnedSimklLibraryActive { var active = true }
private actor OwnedSimklLibraryHeldReply {
    private(set) var started = false
    private var continuation: CheckedContinuation<SimklReply, Never>?
    func hold(_ request: URLRequest) async -> SimklReply { started = true; return await withCheckedContinuation { continuation = $0 } }
    func release() { continuation?.resume(returning: .init(status: 200, data: Data(#"{"all":"2023-01-02T00:00:00Z"}"#.utf8))); continuation = nil }
}

@MainActor final class SimklLibrarySyncTests: XCTestCase {
    private func reply(_ value: String, status: Int = 200) -> SimklReply { .init(status: status, data: Data(value.utf8)) }
    private func make(_ responses: [SimklReply], disk: OwnedSimklLibraryDisk = .init()) throws -> (SimklLibraryModel, OwnedSimklReplies) {
        let clock = OwnedSimklClock(), replies = OwnedSimklReplies(responses, clock: clock)
        let client = SimklClient(transport: { try await replies.send($0) }, sleep: { clock.advance($0) }, now: { clock.now() })
        let account = SimklAccountStore(owner: "owned-library-profile", persistence: OwnedSimklLibraryAccount()); try account.load()
        let model = SimklLibraryModel(account: account, store: SimklLibraryStore(owner: account.owner, disk: disk), client: client, active: { true })
        model.loadAccount(); return (model, replies)
    }
    private func seed(_ store: SimklLibraryStore) async throws -> SimklTarget {
        let ids = SimklIdentifiers(.object(["simkl": .integer(7), "imdb": .string("tt0123456")]))
        let item = SimklListItem(kind: .movie, ids: ids, title: "Owned Movie", status: .plantowatch, watchedEpisodes: [])
        var snapshot = SimklLibrarySnapshot(items: [item.id: item]); snapshot.lastSync = "2023-01-01T00:00:00Z"
        try await store.commit(snapshot, fingerprint: XCTUnwrap(store.fingerprint), expectedRevision: store.revision); return item.target
    }
    func testBootstrapChecksActivitiesFirstAndUnchangedWatermarkSkipsEveryListEndpoint() async throws {
        let movie = #"{"movies":[{"status":"plantowatch","movie":{"title":"Owned Movie","year":2023,"poster":"owned","ids":{"simkl":7,"imdb":"tt0123456"}}}]}"#
        let activities = #"{"all":"2023-01-01T00:00:00Z"}"#
        let (model, replies) = try make([reply(activities), reply(movie), reply("{}"), reply("{}"), reply(#"{"movies":[{"rating":7,"movie":{"ids":{"simkl":7,"imdb":"tt0123456"}}}]}"#), reply(activities)])
        await model.refresh(); XCTAssertNil(model.error); XCTAssertEqual(model.store.snapshot.items.count, 1)
        XCTAssertEqual(model.store.snapshot.items.values.first?.userRating, 7)
        let before = await replies.requests; XCTAssertEqual(before.map { $0.0.url!.path }, ["/sync/activities", "/sync/all-items/movies/all", "/sync/all-items/shows/all", "/sync/all-items/anime/all", "/sync/ratings"])
        await model.refresh(maximumAge: 0)
        let after = await replies.requests; XCTAssertEqual(after.count, 6); XCTAssertEqual(after.last?.0.url?.path, "/sync/activities")
        XCTAssertEqual(model.store.snapshot.items.count, 1); XCTAssertNil(model.error)
    }
    func testDeltaUsesFullEpisodeDataAndRemovesOnlyAfterSuccessfulIdentityReply() async throws {
        let (model, replies) = try make([
            reply(#"{"all":"2023-01-02T00:00:00Z","movies":{"removed_from_list":"2023-01-02T00:00:00Z"}}"#),
            reply(#"{"anime":[{"status":"watching","show":{"title":"Owned Anime","ids":{"simkl":8,"mal":9}},"seasons":[{"number":1,"episodes":[{"number":3,"watched_at":"2023-01-01T12:00:00Z"}]}]}]}"#),
            reply(#"{"movies":[],"anime":[{"show":{"ids":{"simkl":8}}}]}"#), reply("{}")])
        _ = try await seed(model.store); await model.refresh(maximumAge: 0)
        XCTAssertNil(model.error); XCTAssertEqual(Set(model.store.snapshot.items.keys), ["anime:8"])
        XCTAssertEqual(model.store.snapshot.items["anime:8"]?.watchedEpisodes, ["1:3"])
        let sent = await replies.requests, delta = try XCTUnwrap(sent.first { $0.0.url?.path == "/sync/all-items" }?.0.url)
        let query = try XCTUnwrap(URLComponents(url: delta, resolvingAgainstBaseURL: false)?.queryItems)
        XCTAssertEqual(query.first { $0.name == "date_from" }?.value, "2023-01-01T00:00:00Z")
        XCTAssertEqual(query.first { $0.name == "extended" }?.value, "full"); XCTAssertEqual(query.first { $0.name == "episode_watched_at" }?.value, "yes")
        XCTAssertEqual(sent.count, 4)
    }
    func testMutationPublishesOnlyAcceptedRepliesAndUpdatesAllRatingAliases() async throws {
        let (model, replies) = try make([reply(#"{"added":{"movies":[{"to":"completed"}]}}"#), reply("{}"), reply("{}"), reply("{}"), reply("{}", status: 401)])
        let target = try await seed(model.store), media = Media(id: "tt0123456", type: "movie", name: "Owned Movie")
        await model.setStatus(.plantowatch, target: target, media: media); XCTAssertEqual(model.store.snapshot.item(for: target)?.status, .completed)
        await model.setRating(5, target: target)
        let alias = try XCTUnwrap(SimklTarget.direct(media)); XCTAssertEqual(model.store.snapshot.rating(for: alias), 5)
        await model.setRating(nil, target: alias); XCTAssertNil(model.store.snapshot.rating(for: target))
        await model.setStatus(nil, target: target, media: media); XCTAssertNil(model.store.snapshot.item(for: target))
        await model.setStatus(.dropped, target: target, media: media); XCTAssertNil(model.store.snapshot.item(for: target))
        XCTAssertEqual(model.error, "Simkl sign-in expired, reconnect it"); XCTAssertFalse(model.store.updating)
        let sent = await replies.requests; XCTAssertEqual(sent.count, 5)
    }
    func testRetiredProfileCannotPublishHeldListOrMutationRepliesAndFailuresKeepCachedItems() async throws {
        for mutation in [false, true] {
            let active = OwnedSimklLibraryActive(), held = OwnedSimklLibraryHeldReply(), clock = OwnedSimklClock()
            let account = SimklAccountStore(owner: "owned-retired-library", persistence: OwnedSimklLibraryAccount()); try account.load()
            let client = SimklClient(transport: { await held.hold($0) }, sleep: { clock.advance($0) }, now: { clock.now() })
            let model = SimklLibraryModel(account: account, store: .init(owner: account.owner, disk: OwnedSimklLibraryDisk()), client: client, active: { active.active })
            model.loadAccount(); let target = try await seed(model.store), before = model.store.snapshot
            let task = Task { if mutation { await model.setStatus(.dropped, target: target, media: .init(id: "tt0123456", type: "movie", name: "Owned")) } else { await model.refresh(maximumAge: 0) } }
            for _ in 0..<100 { if await held.started { break }; try await Task.sleep(for: .milliseconds(10)) }
            let started = await held.started; XCTAssertTrue(started); active.active = false; await held.release(); await task.value
            XCTAssertEqual(model.store.snapshot, before); XCTAssertNil(model.error)
        }
        let (failed, _) = try make([reply("{}", status: 403)]); _ = try await seed(failed.store); let before = failed.store.snapshot
        await failed.refresh(maximumAge: 0); XCTAssertEqual(failed.store.snapshot, before); XCTAssertEqual(failed.error, "Couldn't reach Simkl")
    }
}

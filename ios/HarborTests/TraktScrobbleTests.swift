import XCTest
@testable import Harbor

@MainActor final class OwnedTraktPendingPersistence: TraktPendingPersistence {
    var values: [String: TraktPendingDocument] = [:]
    var failRead = false, failWrite = false
    func read(owner: String) throws -> TraktPendingDocument? { if failRead { throw HarborError(code: "owned-read") }; return values[owner] }
    func write(_ value: TraktPendingDocument?, owner: String) throws { if failWrite { throw HarborError(code: "owned-write") }; values[owner] = value }
}

@MainActor final class TraktScrobbleTests: XCTestCase {
    private func fixture() throws -> JSONValue {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "trakt-scrobble-reference", withExtension: "json", subdirectory: "Fixtures"))
        let value = try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: url))
        XCTAssertEqual(value["reference"].string, "0834340cec5531650bfe78cd628628702e636987")
        XCTAssertEqual(value["actual_original_typescript_executed"], .bool(true)); XCTAssertEqual(value["provider_network_requests"].integer, 0)
        XCTAssertEqual(value["executed_module_hashes"].objectValue.count, 7); return value
    }
    private func canonical(_ value: JSONValue) throws -> JSONValue { try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(value)) }
    private func identity(_ value: JSONValue) -> TraktWatchIdentity {
        let ref = value["episode"]
        let episode: Episode? = ref == .null ? nil : .init(id: "owned-episode", season: ref["season"].integer, episode: ref["episode"].integer,
            imdbID: ref["imdbId"].string, imdbSeason: ref["imdbSeason"].integer, imdbEpisode: ref["imdbEpisode"].integer, tvdbEpisodeID: ref["tvdbEpisodeId"].integer)
        return .init(mediaID: value["mediaID"].string ?? "", episode: episode)
    }
    private func deliveries(_ values: [TraktPlaybackPolicy.Delivery]) -> JSONValue {
        .array(values.map { value in
            var ref: [String: JSONValue] = ["mediaID": .string(value.identity.mediaID)]
            if let episode = value.identity.episode {
                var fields: [String: JSONValue] = [:]
                if let season = episode.season { fields["season"] = .integer(Int64(season)) }
                if let number = episode.episode { fields["episode"] = .integer(Int64(number)) }
                if let imdb = episode.imdbID { fields["imdbId"] = .string(imdb) }
                if let season = episode.imdbSeason { fields["imdbSeason"] = .integer(Int64(season)) }
                if let number = episode.imdbEpisode { fields["imdbEpisode"] = .integer(Int64(number)) }
                if let tvdb = episode.tvdbEpisodeID { fields["tvdbEpisodeId"] = .integer(Int64(tvdb)) }
                ref["episode"] = .object(fields)
            }
            return .object(["identity": .object(ref), "event": .object(["action": .string(value.event.action.rawValue), "progress": .number(value.event.progress)])])
        })
    }
    private func account(_ memory: OwnedTraktPersistence? = nil, owner: String = "owned-scrobble") throws -> TraktAccountStore {
        let store = TraktAccountStore(owner: owner, persistence: memory ?? OwnedTraktPersistence()); try store.load()
        try store.set(.init(accessToken: "owned-access", refreshToken: "owned-refresh", createdAt: 1_700_000_000, expiresIn: 7_776_000)); return store
    }
    private func reply(_ status: Int, _ value: JSONValue = .null) throws -> TraktReply { .init(status: status, data: try JSONEncoder().encode(value)) }
    private func client(_ transport: OwnedTraktTransport, clock: OwnedTraktClock = .init()) -> TraktClient {
        .init(transport: { try await transport.send($0) }, sleep: { clock.poll($0) }, now: { clock.now() })
    }
    func testExecutedDesktopTargetsScrobbleBodiesAndHistoryReceiptsPreserveIDsAndExactDecimalRounding() throws {
        let reference = try fixture(); XCTAssertEqual(reference["targets"].array.count, 17)
        for row in reference["targets"].array {
            let target = TraktWatchTarget.resolve(identity(row))
            XCTAssertEqual(target?.json ?? .null, row["expected"]["target"], row["name"].string ?? "")
        }
        XCTAssertEqual(reference["bodyCases"].array.count, 77)
        for row in reference["bodyCases"].array {
            let target = try XCTUnwrap(TraktWatchTarget.resolve(identity(row))), progress = try XCTUnwrap(row["progress"].numericValue)
            XCTAssertEqual(try canonical(target.kind == .show ? .null : target.scrobbleBody(progress) ?? .null), row["expected"], row["name"].string ?? "")
        }
        XCTAssertEqual(reference["historyCases"].array.count, 55)
        for row in reference["historyCases"].array {
            let target = try XCTUnwrap(TraktWatchTarget.resolve(identity(row)))
            XCTAssertEqual(target.historyBody ?? .null, row["expected"]["body"], row["name"].string ?? "")
            if target.kind != .show { XCTAssertEqual(.bool(TraktHistoryReceipt.confirms(row["receipt"])), row["expected"]["confirmed"]) }
        }
        XCTAssertNil(TraktWatchTarget.resolve(.init(mediaID: "tt1234567:-1:0")))
        XCTAssertNil(TraktWatchTarget.resolve(.init(mediaID: "tmdb:movie:0")))
        XCTAssertNil(TraktWatchTarget(kind: .movie, ids: .init(.object(["imdb": .string("tt1234567")]))).scrobbleBody(.nan))
    }
    func testExecutedDesktopHookPreservesPauseResumeSeekThrottleFurthestProgressAndFreshEpisodeReset() throws {
        let rows = try fixture()["lifecycleCases"].array; XCTAssertEqual(rows.count, 14)
        for row in rows {
            var policy = TraktPlaybackPolicy()
            for step in row["steps"].array {
                let result = policy.update(identity: identity(step["identity"]), status: try XCTUnwrap(.init(rawValue: step["status"].string ?? "")),
                    position: try XCTUnwrap(step["position"].numericValue), duration: try XCTUnwrap(step["duration"].numericValue),
                    now: try XCTUnwrap(step["now"].numericValue), isClockTick: step["tick"] == .bool(true))
                XCTAssertEqual(try canonical(deliveries(result)), step["expected"], row["name"].string ?? "")
            }
            XCTAssertEqual(try canonical(deliveries(policy.finish().map { [$0] } ?? [])), row["finish"], row["name"].string ?? "")
        }
    }
    func testExecutedDesktopScrobbleFailuresRetryOnlyTerminalStopsAndAcceptDuplicateReceipts() async throws {
        let rows = try fixture()["sendCases"].array; XCTAssertEqual(rows.count, 8)
        for row in rows {
            let account = try account(), memory = OwnedTraktPendingPersistence(), queue = TraktPendingStops(owner: account.owner, persistence: memory)
            let transport = OwnedTraktTransport(try row["statuses"].array.map { try reply(try XCTUnwrap($0.integer)) }), clock = OwnedTraktClock()
            let reporter = TraktWatchReporter(account: account, queue: queue, client: client(transport, clock: clock), active: { true }, resolve: { _, _, _ in .error })
            await reporter.send(.init(action: try XCTUnwrap(.init(rawValue: row["action"].string ?? "")), progress: 50), identity: .init(mediaID: "tt1234567"))
            let requests = await transport.requests
            for request in requests {
                XCTAssertEqual(request.url?.host, "api.trakt.tv"); XCTAssertEqual(request.httpMethod, "POST")
                XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer owned-access")
                XCTAssertNil(request.value(forHTTPHeaderField: "Cookie"))
            }
            let observed: JSONValue = .array(try requests.map { request in .object(["path": .string(request.url!.path), "method": .string(request.httpMethod!), "body": try JSONDecoder().decode(JSONValue.self, from: XCTUnwrap(request.httpBody))]) })
            XCTAssertEqual(try canonical(observed), row["expected"]["requests"], row["name"].string ?? "")
            XCTAssertEqual(clock.pollDelays.filter { $0 == 0.8 }.map { $0 * 1000 }, row["expected"]["delays"].array.compactMap(\.numericValue))
            XCTAssertNil(queue.document)
        }
    }
    func testDurableAccountLineageMigratesBeforePublicationSurvivesRefreshAndSeparatesReconnects() async throws {
        let memory = OwnedTraktPersistence(), owner = "owned-legacy-lineage"
        let old = TraktSession(accessToken: "owned-access", refreshToken: "owned-refresh", createdAt: 1_700_000_000, expiresIn: 7_776_000)
        memory.values[owner] = old; memory.failWrite = true
        let account = TraktAccountStore(owner: owner, persistence: memory)
        XCTAssertThrowsError(try account.load()); XCTAssertFalse(account.ready); XCTAssertNil(account.session); XCTAssertNil(memory.values[owner]?.trackingID)
        memory.failWrite = false; try account.load(); let lineage = try XCTUnwrap(account.session?.trackingID)
        let reopened = TraktAccountStore(owner: owner, persistence: memory); try reopened.load(); XCTAssertEqual(reopened.session?.trackingID, lineage)
        let grant: JSONValue = .object(["access_token": .string("owned-rotated"), "refresh_token": .string("owned-rotated-refresh"), "created_at": .integer(1_700_000_100), "expires_in": .integer(7_776_000)])
        let transport = OwnedTraktTransport(try [reply(401), reply(200, grant), reply(200, .array([]))])
        _ = try await account.response(.playback, client: client(transport), active: { true })
        XCTAssertEqual(account.session?.trackingID, lineage); XCTAssertEqual(memory.values[owner]?.trackingID, lineage)
        try account.set(nil); try account.set(old); XCTAssertNotEqual(account.session?.trackingID, lineage)
    }
    func testPendingStopsPreserveDiskOnFailureDeduplicateBoundToTheAccountAndKeepNewerAcknowledgements() throws {
        let memory = OwnedTraktPendingPersistence(), queue = TraktPendingStops(owner: "owned-queue", persistence: memory), lineage = UUID()
        try queue.bind(lineage)
        for index in 0..<55 { _ = try queue.record(.init(mediaID: "tt\(index + 100)"), progress: 75) }
        XCTAssertEqual(queue.document?.entries.count, 50); XCTAssertEqual(queue.document?.entries.first?.identity.mediaID, "tt154")
        let identity = TraktWatchIdentity(mediaID: "tt154"), previous = try XCTUnwrap(queue.document?.entries.first), fingerprint = try XCTUnwrap(queue.document?.fingerprint)
        memory.failWrite = true; XCTAssertThrowsError(try queue.record(identity, progress: 99)); XCTAssertEqual(queue.document?.entries.first?.id, previous.id)
        memory.failWrite = false; let current = try XCTUnwrap(queue.record(identity, progress: 99)); try queue.remove(previous, fingerprint: fingerprint)
        XCTAssertEqual(queue.document?.entries.first?.id, current.id)
        let reopened = TraktPendingStops(owner: queue.owner, persistence: memory); try reopened.bind(lineage); XCTAssertEqual(reopened.document?.entries.first?.id, current.id)
        XCTAssertNil(try queue.record(identity, progress: 69.999)); try queue.bind(UUID()); XCTAssertTrue(queue.document?.entries.isEmpty == true)
        let anotherProfile = TraktPendingStops(owner: "different", persistence: memory); try anotherProfile.bind(lineage); XCTAssertTrue(anotherProfile.document?.entries.isEmpty == true)
    }
    func testUnconfirmedHeuristicMissStaysDurableUntilConfirmedRecoveryAndDoesNotReplayIntoAnotherAccount() async throws {
        let account = try account(), memory = OwnedTraktPendingPersistence(), queue = TraktPendingStops(owner: account.owner, persistence: memory)
        let transport = OwnedTraktTransport(try [reply(503), reply(503), reply(200, .object(["not_found": .object(["episodes": .array([])])]))])
        let reporter = TraktWatchReporter(account: account, queue: queue, client: client(transport), active: { true }, resolve: { _, _, _ in .notFound })
        let identity = TraktWatchIdentity(mediaID: "tt1234567", episode: .init(id: "owned", season: 1, episode: 7))
        await reporter.send(.init(action: .stop, progress: 91), identity: identity); XCTAssertEqual(queue.document?.entries.count, 1)
        let reopened = TraktPendingStops(owner: account.owner, persistence: memory), recovered = OwnedTraktTransport(try [reply(409)])
        let next = TraktWatchReporter(account: account, queue: reopened, client: client(recovered), active: { true })
        await next.recover(); XCTAssertTrue(reopened.document?.entries.isEmpty == true)
        let recoveredRequests = await recovered.requests, request = try XCTUnwrap(recoveredRequests.first)
        XCTAssertEqual(try JSONDecoder().decode(JSONValue.self, from: XCTUnwrap(request.httpBody))["progress"].integer, 100)
        let oldCount = await transport.requests.count
        try account.set(nil); try account.set(.init(accessToken: "owned-other", refreshToken: "owned-other-refresh", createdAt: 1_700_000_000, expiresIn: 7_776_000))
        await reporter.send(.init(action: .start, progress: 1), identity: identity)
        let after = await transport.requests.count; XCTAssertEqual(after, oldCount)
    }
    func testSerialPlaybackCompositionKeepsPreviousEpisodeTerminalBeforeNewStartAndClosesOnlyOnce() async throws {
        let account = try account(), transport = OwnedTraktTransport(fallback: { _ in .init(status: 200, data: Data("null".utf8)) })
        let queue = TraktPendingStops(owner: account.owner, persistence: OwnedTraktPendingPersistence())
        let reporter = TraktWatchReporter(account: account, queue: queue, client: client(transport), active: { true })
        let tracker = TraktPlaybackTracker(reporter: reporter, delivery: .init()), a = TraktWatchIdentity(mediaID: "tt1234567"), b = TraktWatchIdentity(mediaID: "tt1234568")
        tracker.sample(identity: a, status: .playing, position: 950, duration: 1000)
        tracker.sample(identity: b, status: .loading, position: 0, duration: 0)
        tracker.sample(identity: b, status: .playing, position: 20, duration: 1000)
        tracker.finish(identity: b, position: 30, duration: 1000); tracker.finish(); await tracker.settled()
        let requests = await transport.requests
        XCTAssertEqual(requests.map { $0.url!.path }, ["/scrobble/start", "/scrobble/stop", "/scrobble/start", "/scrobble/pause"])
        let bodies = try requests.map { try JSONDecoder().decode(JSONValue.self, from: XCTUnwrap($0.httpBody)) }
        XCTAssertEqual(bodies.map { $0["movie"]["ids"]["imdb"].string }, [a.mediaID, a.mediaID, b.mediaID, b.mediaID])
        XCTAssertEqual(bodies.last?["progress"].integer, 3); XCTAssertTrue(queue.document?.entries.isEmpty == true)
    }
    func testExecutedDesktopResolutionsPreserveDirectHistoryFallbackMappedEpisodesAndSpecialMovies() async throws {
        let rows = try fixture()["resolutionCases"].array; XCTAssertEqual(rows.count, 7)
        for row in rows {
            let account = try account(), queue = TraktPendingStops(owner: account.owner, persistence: OwnedTraktPendingPersistence())
            let responses = try row["statuses"].array.map { status -> TraktReply in
                let receipt: JSONValue = row["name"].string == "direct-history" ? .object(["existing": .object(["episodes": .integer(1)])]) : .object([:])
                return try reply(try XCTUnwrap(status.integer), receipt)
            }
            let transport = OwnedTraktTransport(responses)
            let resolved = TrackerResolvedEpisode(showIds: .init(row["resolved"]["showIds"]), season: try XCTUnwrap(row["resolved"]["season"].integer), number: try XCTUnwrap(row["resolved"]["number"].integer))
            let found = row["found"] == .bool(true), special = row["special"] == .bool(true)
            let reporter = TraktWatchReporter(account: account, queue: queue, client: client(transport), active: { true },
                resolve: { _, _, _ in found ? .found(resolved) : .notFound },
                specialMovie: { _, _, _ in special ? TrackerShowIDs(.object(["trakt": .integer(92)])) : nil })
            let action = try XCTUnwrap(TraktScrobbleAction(rawValue: row["action"].string ?? "")), progress = try XCTUnwrap(row["progress"].numericValue)
            await reporter.send(.init(action: action, progress: progress), identity: identity(row["identity"]))
            let requests = await transport.requests
            let actual: JSONValue = .array(try requests.map { .object(["path": .string($0.url!.path), "method": .string($0.httpMethod!), "body": try JSONDecoder().decode(JSONValue.self, from: XCTUnwrap($0.httpBody))]) })
            XCTAssertEqual(try canonical(actual), row["expected"]["requests"], row["name"].string ?? "")
            if action == .stop && progress >= 70 { XCTAssertEqual(queue.document?.entries.count, row["expected"]["outcome"].string == "failed" ? 1 : 0) }
        }
    }
    func testExecutedDesktopSpecialMovieMatchingAndProductionResolverUseAnonymousBoundedSearchAndCache() async throws {
        let rows = try fixture()["movieCases"].array; XCTAssertEqual(rows.count, 10)
        for row in rows {
            let identity = try row["identity"].decoded(TrackerEpisodeIdentity.self)
            XCTAssertEqual(.bool(TrackerEpisodeMatch.movieMatches(identity, title: row["candidate"]["title"].string, year: row["candidate"]["year"].integer)), row["expected"], row["name"].string ?? "")
        }
        let data = Data(#"{"metadata":{"name":"Owned Show","releaseInfo":"2020","videos":[{"season":0,"episode":1,"name":"The Lost Island","released":"2020-01-01"}]},"movies":[{"movie":{"title":"The Lost Island","year":2000,"ids":{"trakt":90}}},{"movie":{"title":"Owned Show: The Lost Island","year":2021,"ids":{"trakt":91}}}]}"#.utf8)
        let catalog = OwnedTrackerCatalog(try JSONDecoder().decode(JSONValue.self, from: data)), resolver = TrackerEpisodeResolver(response: { try await catalog.send($0) }, cacheURL: nil)
        async let first = resolver.specialMovie(metaID: "tt1234567", season: 0, number: 1)
        async let second = resolver.specialMovie(metaID: "tt1234567", season: 0, number: 1)
        let result = await (first, second); XCTAssertEqual(result.0?.json["trakt"].integer, 91); XCTAssertEqual(result.1, result.0)
        let cached = await resolver.specialMovie(metaID: "tt1234567", season: 0, number: 1); XCTAssertEqual(cached, result.0)
        let requests = await catalog.requests; XCTAssertEqual(requests.filter { if case .searchMovies = $0 { return true }; return false }, [.searchMovies("The Lost Island")])
        let request = try HTTPClient.trackerCatalogRequest(.searchMovies("The Lost Island")), components = try XCTUnwrap(URLComponents(url: XCTUnwrap(request.url), resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.path, "/search/movie"); XCTAssertEqual(components.queryItems?.first { $0.name == "limit" }?.value, "10")
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization")); XCTAssertNil(request.value(forHTTPHeaderField: "Cookie"))
    }
    func testHeldAcknowledgementCannotDeleteANewerStopAndChangedProfileCannotContinueTheOldDelivery() async throws {
        let account = try account(), queue = TraktPendingStops(owner: account.owner, persistence: OwnedTraktPendingPersistence()), scope = OwnedTraktScope()
        try queue.bind(account.session?.trackingID)
        let identity = TraktWatchIdentity(mediaID: "tt1234567"), transport = OwnedTraktTransport(try [reply(409)])
        await transport.hold("/scrobble/stop")
        let reporter = TraktWatchReporter(account: account, queue: queue, client: client(transport), active: { scope.active })
        let operation = Task { await reporter.send(.init(action: .stop, progress: 95), identity: identity) }
        for _ in 0..<100 { if await transport.isHolding { break }; try await Task.sleep(for: .milliseconds(20)) }
        let held = await transport.isHolding; XCTAssertTrue(held)
        let replacement = try XCTUnwrap(queue.record(identity, progress: 100))
        scope.active = false; await transport.release(); await operation.value
        XCTAssertEqual(queue.document?.entries.first?.id, replacement.id)
        await reporter.recover(); let requests = await transport.requests; XCTAssertEqual(requests.count, 1)
    }
}

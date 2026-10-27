import XCTest
@testable import Harbor

actor OwnedTrackerCatalog {
    let scenario: JSONValue
    private(set) var requests: [TrackerCatalogRequest] = []
    init(_ scenario: JSONValue) { self.scenario = scenario }
    func send(_ endpoint: TrackerCatalogRequest) async throws -> JSONValue {
        requests.append(endpoint)
        switch endpoint {
        case .searchShows:
            if scenario["searchError"] == .bool(true) { throw HarborError(code: "owned-tracker-search") }
            try await Task.sleep(for: .milliseconds(20)); return scenario["search"]
        case .searchMovies: return scenario["movies"]
        case .seasons(let ids):
            guard let id = ids.parameter else { throw HarborError(code: "owned-tracker-foreign-id") }
            if scenario["seasonError"].string == id { throw HarborError(code: "owned-tracker-seasons") }
            return scenario["seasons"][id] == .null ? .array([]) : scenario["seasons"][id]
        case .tmdbShow: return scenario["tmdbLookup"]
        case .cinemetaSeries: return .object(["meta": scenario["metadata"]])
        }
    }
}
@MainActor final class TrackerEpisodeResolverTests: XCTestCase {
    private func fixture() throws -> JSONValue {
        let file = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "tracker-episode-reference", withExtension: "json", subdirectory: "Fixtures"))
        let result = try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: file))
        XCTAssertEqual(result["actual_original_typescript_executed"], .bool(true)); XCTAssertEqual(result["provider_network_requests"].integer, 0)
        return result
    }
    private func canonical(_ endpoint: TrackerCatalogRequest) throws -> String {
        if case .cinemetaSeries(let imdb) = endpoint { return "CINEMETA:" + imdb + ":forced" }
        return try canonical(XCTUnwrap(HTTPClient.trackerCatalogRequest(endpoint).url).absoluteString)
    }
    private func canonical(_ raw: String) throws -> String {
        if raw.hasPrefix("CINEMETA:") { return raw }
        let url = raw.hasPrefix("http") ? raw : "https://api.trakt.tv" + raw
        let components = try XCTUnwrap(URLComponents(string: url.replacingOccurrences(of: "+", with: "%20")))
        return components.path + "?" + (components.queryItems ?? []).map { $0.name + "=" + ($0.value ?? "") }.sorted().joined(separator: "&")
    }
    func testEightEpisodeMatchesPreserveTheExecutedDesktopIdentifierPrecedenceAndDateWindow() throws {
        let cases = try fixture()["matchCases"].array; XCTAssertEqual(cases.count, 8)
        for row in cases {
            let identity = try row["identity"].decoded(TrackerEpisodeIdentity.self), candidate = try row["candidate"].decoded(TrackerEpisodeCandidate.self)
            XCTAssertEqual(.bool(TrackerEpisodeMatch.matches(identity, candidate)), row["expected"], row["name"].string ?? "")
        }
    }
    func testSixteenCatalogResolutionsMatchTheExecutedDesktopResultsAndAnonymousRequestBudget() async throws {
        let cases = try fixture()["scenarios"].array; XCTAssertEqual(cases.count, 16)
        for row in cases {
            let transport = OwnedTrackerCatalog(row), resolver = TrackerEpisodeResolver(response: { try await transport.send($0) }, cacheURL: nil)
            let result = await resolver.resolve(try row["identity"].decoded(TrackerEpisodeIdentity.self))
            XCTAssertEqual(result.json, row["expected"], row["name"].string ?? "")
            let requests = await transport.requests
            XCTAssertEqual(try requests.map(canonical), try row["requests"].array.compactMap(\.string).map(canonical), row["name"].string ?? "")
            XCTAssertLessThanOrEqual(requests.count, 6)
        }
    }
    func testSixHydrationPathsForceCinemetaAndBridgeForeignShowIdsLikeTheExecutedDesktop() async throws {
        let cases = try fixture()["hydrationCases"].array; XCTAssertEqual(cases.count, 6)
        for row in cases {
            let transport = OwnedTrackerCatalog(row), resolver = TrackerEpisodeResolver(response: { try await transport.send($0) }, cacheURL: nil)
            let result = await resolver.resolve(metaID: try XCTUnwrap(row["metaId"].string), season: 1, number: 7)
            XCTAssertEqual(result.json, row["expected"], row["name"].string ?? "")
            let requests = await transport.requests
            XCTAssertEqual(try requests.map(canonical), try row["requests"].array.compactMap(\.string).map(canonical), row["name"].string ?? "")
        }
    }
    func testResolutionCoalescesAndReopensPositiveCacheWhileNegativeAndTransientResultsHaveDifferentLifetimes() async throws {
        let all = try fixture()["scenarios"].array, positive = all[0], clock = OwnedSimklClock()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("owned-tracker-" + UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("episodes.json"), transport = OwnedTrackerCatalog(positive)
        let identity = try positive["identity"].decoded(TrackerEpisodeIdentity.self)
        let resolver = TrackerEpisodeResolver(response: { try await transport.send($0) }, now: { clock.now() }, cacheURL: file)
        async let first = resolver.resolve(identity)
        async let second = resolver.resolve(identity)
        let pair = await (first, second); XCTAssertEqual(pair.0.json, positive["expected"]); XCTAssertEqual(pair.0, pair.1)
        let coalesced = await transport.requests; XCTAssertEqual(coalesced.count, 2)
        let reopenedTransport = OwnedTrackerCatalog(positive)
        let reopened = TrackerEpisodeResolver(response: { try await reopenedTransport.send($0) }, now: { clock.now() }, cacheURL: file)
        let restored = await reopened.resolve(identity); XCTAssertEqual(restored, pair.0)
        let noRequests = await reopenedTransport.requests; XCTAssertTrue(noRequests.isEmpty)
        XCTAssertFalse(try String(contentsOf: file, encoding: .utf8).contains(identity.showTitle), "Persistent resolution keys are hashed metadata identities")
        clock.advance(7 * 24 * 60 * 60)
        _ = await reopened.resolve(identity); let expired = await reopenedTransport.requests; XCTAssertEqual(expired.count, 2)
        let negative = all[8], missingTransport = OwnedTrackerCatalog(negative)
        let missing = TrackerEpisodeResolver(response: { try await missingTransport.send($0) }, now: { clock.now() }, cacheURL: nil)
        _ = await missing.resolve(identity); _ = await missing.resolve(identity)
        let retainedMiss = await missingTransport.requests; XCTAssertEqual(retainedMiss.count, 1)
        clock.advance(600); _ = await missing.resolve(identity)
        let expiredMiss = await missingTransport.requests; XCTAssertEqual(expiredMiss.count, 2)
        let transient = all[7], transientTransport = OwnedTrackerCatalog(transient)
        let retryable = TrackerEpisodeResolver(response: { try await transientTransport.send($0) }, cacheURL: nil)
        let uncomparable = try transient["identity"].decoded(TrackerEpisodeIdentity.self)
        _ = await retryable.resolve(uncomparable); _ = await retryable.resolve(uncomparable)
        let retried = await transientTransport.requests; XCTAssertEqual(retried.count, 4)
    }
    func testTypedCatalogRequestsKeepOAuthOffBothOriginsAndRejectForeignNumericShowIdentifiers() throws {
        let reference = try fixture(), ids = TrackerShowIDs(.object(["trakt": .integer(42), "imdb": .string("tt0123456"), "tmdb": .integer(50)]))
        for endpoint in [TrackerCatalogRequest.searchShows("An owned title & sequel"), .seasons(ids), .tmdbShow(50), .cinemetaSeries("tt0123456")] {
            let request = try HTTPClient.trackerCatalogRequest(endpoint)
            XCTAssertEqual(request.httpMethod, "GET"); XCTAssertNil(request.value(forHTTPHeaderField: "Authorization")); XCTAssertNil(request.httpBody)
            XCTAssertEqual(request.url?.scheme, "https"); XCTAssertNil(request.url?.user); XCTAssertNil(request.url?.password)
            if request.url?.host == "api.trakt.tv" { XCTAssertEqual(request.value(forHTTPHeaderField: "trakt-api-key"), reference["public_trakt_client_id"].string) }
            else { XCTAssertEqual(request.url?.host, "v3-cinemeta.strem.io"); XCTAssertNil(request.value(forHTTPHeaderField: "trakt-api-key")) }
        }
        XCTAssertEqual(ids.parameter, "42")
        XCTAssertThrowsError(try HTTPClient.trackerCatalogRequest(.seasons(.init(.object(["tmdb": .integer(50), "tvdb": .integer(60)])))))
        XCTAssertThrowsError(try HTTPClient.trackerCatalogRequest(.seasons(.init(.object(["slug": .string("../owned")])))))
        XCTAssertThrowsError(try HTTPClient.trackerCatalogRequest(.cinemetaSeries("tt0123456/private")))
    }
}

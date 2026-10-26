import XCTest
@testable import Harbor

final class SimklPlaybackContractTests: XCTestCase {
    private func reference() throws -> JSONValue {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "simkl-playback-reference", withExtension: "json", subdirectory: "Fixtures"))
        return try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: url))
    }
    func test42ScrobblePayloadsMatchTheActuallyExecutedDesktopBuilderWithoutTokenURLs() throws {
        let reference = try reference(); XCTAssertEqual(reference["actual_original_typescript_executed"], .bool(true)); XCTAssertEqual(reference["provider_network_requests"].integer, 0)
        XCTAssertEqual(reference["bodies"].array.count, 42)
        for value in reference["bodies"].array {
            let episode = value["episode"] == .null ? nil : Episode(id: "owned", season: value["episode"]["season"].integer, episode: value["episode"]["episode"].integer, imdbID: value["episode"]["imdbId"].string)
            let identity = SimklWatchIdentity(mediaID: try XCTUnwrap(value["id"].string), episode: episode,
                title: value["info"]["title"].string, year: value["info"]["year"].integer, imdb: value["info"]["imdb"].string)
            let candidate = identity.scrobbleBody(progress: Double(try XCTUnwrap(value["progress"].integer)))
            if value["expected"] == .null { XCTAssertNil(candidate); continue }
            let body = try XCTUnwrap(candidate)
            XCTAssertEqual(try JSONValue.encoded(body), value["expected"])
            let request = try SimklEndpoint.watch(.scrobble(.start, body)).request(token: "owned-tracker-token")
            XCTAssertEqual(request.url?.path, "/scrobble/start"); XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer owned-tracker-token")
            XCTAssertFalse(request.url!.absoluteString.contains("owned-tracker-token"))
        }
        XCTAssertNil(SimklWatchIdentity(mediaID: "tt0123456").scrobbleBody(progress: .nan))
        XCTAssertThrowsError(try SimklEndpoint.watch(.history(.object([:]))).request())
    }
    func testSevenPlaybackTracesMatchTheExecutedDesktopHookIncludingStubsFurthestSeekAndTheWatchedThreshold() throws {
        let reference = try reference(); XCTAssertEqual(reference["scenarios"].array.count, 7)
        for scenario in reference["scenarios"].array {
            var policy = SimklPlaybackPolicy(), events: [SimklPlaybackPolicy.Event] = []
            for raw in scenario["steps"].array {
                let step = raw.array, status: SimklPlaybackPolicy.Status
                switch step[0].string { case "playing": status = .playing; case "paused": status = .paused; case "ended": status = .ended; default: status = .loading }
                if let event = policy.update(status: status, position: Double(try XCTUnwrap(step[1].integer)), duration: Double(try XCTUnwrap(step[2].integer))) { events.append(event) }
            }
            let exit = scenario["exit"].array
            if let event = policy.finish(position: Double(try XCTUnwrap(exit[0].integer)), duration: Double(try XCTUnwrap(exit[1].integer))) { events.append(event) }
            let expected = scenario["expected"].array
            XCTAssertEqual(events.count, expected.count, scenario["name"].string ?? "")
            for (event, actual) in zip(events, expected) {
                XCTAssertEqual(event.action.rawValue, actual["action"].string)
                XCTAssertEqual(event.progress, Double(try XCTUnwrap(actual["progress"].integer)), accuracy: 0.000001)
            }
            XCTAssertEqual(events.contains(where: \.recordWatched), scenario["expectedWatched"] == .bool(true))
        }
    }
    func testHistoryUsesVerifiedAnimeAliasesAndDoesNotSubstituteTheirCoordinatesForDirectTVEntries() async throws {
        let ep = Episode(id: "owned-episode", season: 1, episode: 99, imdbSeason: 5, imdbEpisode: 23)
        let anime = SimklWatchIdentity(mediaID: "kitsu:123", episode: ep, imdb: "tt0123456")
        let animeValue = try await anime.historyBody(now: Date(timeIntervalSince1970: 0), mapping: { _ in XCTFail("Verified IMDb fallback should not require a mapping request"); return .null })
        let animeBody = try XCTUnwrap(animeValue)
        let show = try XCTUnwrap(animeBody["shows"].array.first), season = try XCTUnwrap(show["seasons"].array.first)
        XCTAssertEqual(show["ids"]["imdb"].string, "tt0123456"); XCTAssertEqual(season["number"].integer, 5); XCTAssertEqual(season["episodes"].array.first?["number"].integer, 23)
        let direct = SimklWatchIdentity(mediaID: "tt0123456", episode: ep)
        let directValue = try await direct.historyBody(now: Date(timeIntervalSince1970: 0)), directBody = try XCTUnwrap(directValue)
        XCTAssertEqual(directBody["shows"].array.first?["seasons"].array.first?["number"].integer, 1)
        XCTAssertEqual(directBody["shows"].array.first?["seasons"].array.first?["episodes"].array.first?["number"].integer, 99)
        let mapped = SimklWatchIdentity(mediaID: "kitsu:123", episode: .init(id: "owned", season: 1, episode: 7))
        let result = try await mapped.historyBody(mapping: { _ in .object(["mappings": .object(["kitsu_id": .integer(123), "mal_id": .integer(456)])]) })
        XCTAssertEqual(result?["shows"].array.first?["ids"]["mal"].integer, 456)
    }
}

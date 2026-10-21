import XCTest
@testable import Harbor

private actor PluginRequestFetch {
    var metaCalls = 0
    var tmdbCalls = 0
    private var continuation: CheckedContinuation<Void, Never>?
    private var released = false
    func find() async -> HarborPluginTMDBReference {
        tmdbCalls += 1
        if !released { await withCheckedContinuation { continuation = $0 } }
        return .init(id: 603, kind: "movie")
    }
    func meta() async -> JSONValue {
        metaCalls += 1
        if !released { await withCheckedContinuation { continuation = $0 } }
        return .object(["moviedb_id": .integer(603), "name": .string("The Matrix"), "releaseInfo": .string("1999")])
    }
    func waitUntilStarted() async throws {
        for _ in 0..<150 { if continuation != nil { return }; try await Task.sleep(for: .milliseconds(20)) }
        throw HarborError(code: "owned-timeout")
    }
    func release() { released = true; continuation?.resume(); continuation = nil }
}

@MainActor final class HarborPluginStreamRequestTests: XCTestCase {
    private func suite() -> String {
        let name = "owned-plugin-request-" + UUID().uuidString
        addTeardownBlock { UserDefaults(suiteName: name)?.removePersistentDomain(forName: name) }
        return name
    }
    func testNativeRequestBuilderMatchesTwelveOriginalDesktopCasesIncludingRawAndAbsoluteEpisodes() async throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "plugin-stream-requests-reference", withExtension: "json", subdirectory: "Fixtures"))
        let fixture = try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: url))
        XCTAssertEqual(fixture["reference"].string, "0834340cec5531650bfe78cd628628702e636987")
        XCTAssertEqual(fixture["sourceHash"].string, "cdfe17a2ba63ccd0e44f774cd498fb538d66823360c8928844798d6131af49b0")
        XCTAssertEqual(fixture["cases"].array.count, 12)
        let both = JSONValue.object(["movie_results": .array([.object(["id": .integer(603)])]), "tv_results": .array([.object(["id": .integer(62715)])])])
        XCTAssertEqual(TMDBService.pluginReference(both, type: "series"), .init(id: 62715, kind: "tv"))
        XCTAssertEqual(TMDBService.pluginReference(both, type: "movie"), .init(id: 603, kind: "movie"))
        XCTAssertEqual(TMDBService.pluginReference(.object(["movie_results": both["movie_results"]]), type: "series"), .init(id: 603, kind: "movie"))
        for row in fixture["cases"].array {
            let input = row["input"], meta = input["meta"], tmdb = input["tmdb"]
            let resolver = HarborPluginMetadataResolver(defaultsName: suite(), fetchTMDB: { _, _, _ in
                guard let id = tmdb["id"].integer, let kind = tmdb["kind"].string else { return nil }
                return .init(id: id, kind: kind)
            }, fetchCinemeta: { _, _ in meta })
            let media = try input["media"].decoded(Media.self)
            let episode: Episode? = input["episode"] == .null ? nil : try input["episode"].decoded(Episode.self)
            let actual = try await HarborPluginStreamRequest.build(media: media, ids: input["ids"].array.compactMap(\.string),
                pickedID: XCTUnwrap(input["pickedID"].string), episode: episode, tmdbKey: input["key"].string ?? "", resolver: resolver)
            XCTAssertEqual(actual, row["expected"], row["name"].string ?? "Owned request")
        }
    }
    func testConcurrentMetadataLookupSurvivesOneCancelledCallerAndPersistsOnlyPublicMapping() async throws {
        let name = suite(), network = PluginRequestFetch()
        let resolver = HarborPluginMetadataResolver(defaultsName: name, fetchTMDB: { _, _, _ in await network.find() }, fetchCinemeta: { _, _ in await network.meta() })
        let cancelled = Task { try await resolver.resolve(imdb: "tt0133093", type: "movie", tmdbKey: "owned-secret-never-persist", needsName: false) }
        try await network.waitUntilStarted()
        let normal = Task { try await resolver.resolve(imdb: "tt0133093", type: "movie", tmdbKey: "owned-secret-never-persist", needsName: true) }
        await Task.yield(); cancelled.cancel(); await network.release()
        do { _ = try await cancelled.value; XCTFail("Cancelled caller published public lookup") } catch { XCTAssertTrue(error is CancellationError) }
        let value = try await normal.value
        XCTAssertEqual(value.tmdb, .init(id: 603, kind: "movie")); XCTAssertEqual(value.title, "The Matrix")
        let calls = await network.metaCalls; XCTAssertEqual(calls, 1)
        let finds = await network.tmdbCalls; XCTAssertEqual(finds, 1)
        let persisted = try XCTUnwrap(UserDefaults(suiteName: name)?.data(forKey: "ios.plugins.public-tmdb.v1"))
        XCTAssertFalse(String(decoding: persisted, as: UTF8.self).contains("owned-secret"))
        let restored = HarborPluginMetadataResolver(defaultsName: name, fetchTMDB: { _, _, _ in throw HarborError(code: "must-not-fetch") },
            fetchCinemeta: { _, _ in throw HarborError(code: "must-not-fetch") })
        let hit = try await restored.resolve(imdb: "tt0133093", type: "movie", tmdbKey: "", needsName: false)
        XCTAssertEqual(hit.tmdb, value.tmdb)
    }
    func testMissingPublicMappingIsNotRepeatedForEveryPluginOrPersistedAsPermanentFailure() async throws {
        actor Misses {
            var count = 0
            func fetch() -> JSONValue { count += 1; return .object([:]) }
        }
        let misses = Misses(), name = suite()
        let resolver = HarborPluginMetadataResolver(defaultsName: name, now: { 100 }, fetchTMDB: { _, _, _ in nil }, fetchCinemeta: { _, _ in await misses.fetch() })
        for _ in 0..<10 {
            let value = try await resolver.resolve(imdb: "tt0133093", type: "movie", tmdbKey: "", needsName: false)
            XCTAssertNil(value.tmdb)
        }
        let count = await misses.count; XCTAssertEqual(count, 1)
        XCTAssertNil(UserDefaults(suiteName: name)?.data(forKey: "ios.plugins.public-tmdb.v1"))
        let restarted = HarborPluginMetadataResolver(defaultsName: name, now: { 101 }, fetchTMDB: { _, _, _ in nil },
            fetchCinemeta: { _, _ in .object(["moviedb_id": .integer(603)]) })
        let recovered = try await restarted.resolve(imdb: "tt0133093", type: "movie", tmdbKey: "", needsName: false)
        XCTAssertEqual(recovered.tmdb?.id, 603)
    }
}

import XCTest
@testable import Harbor

private actor FranchiseFixtureTransport: AnimeFranchiseTransport {
    private var replies: [AnimeFranchiseRequest: JSONValue]
    private var calls: [AnimeFranchiseRequest] = []
    private var active = 0
    private var maximum = 0
    init(_ replies: [AnimeFranchiseRequest: JSONValue]) { self.replies = replies }
    func replace(_ request: AnimeFranchiseRequest, with value: JSONValue) { replies[request] = value }
    func requests() -> [AnimeFranchiseRequest] { calls }
    func maximumActive() -> Int { maximum }
    func get(_ request: AnimeFranchiseRequest) async throws -> JSONValue {
        calls.append(request); active += 1; maximum = max(maximum, active)
        defer { active -= 1 }
        try await Task.sleep(for: .milliseconds(8))
        guard let value = replies[request] else { throw HarborError(code: "http-404") }
        return value
    }
}

private actor FranchiseTVDBTransport: TVDBTransport {
    func get(_ request: TVDBRequest) async throws -> JSONValue { .object(["data": .object(["episodes": .array([])])]) }
}

final class AnimeFranchiseTests: XCTestCase {
    private func json(_ text: String) throws -> JSONValue { try JSONDecoder().decode(JSONValue.self, from: Data(text.utf8)) }
    private func resource(_ id: Int, name: String? = nil, subtype: String = "TV", episodes: Int = 12, date: String = "2020-01-01", status: String = "finished") -> JSONValue {
        .object(["id": .string(String(id)), "type": .string("anime"), "attributes": .object([
            "canonicalTitle": .string(name ?? "Synthetic Season \(id)"), "subtype": .string(subtype), "episodeCount": .integer(Int64(episodes)),
            "startDate": .string(date), "status": .string(status), "averageRating": .string("85"),
            "posterImage": .object(["large": .string("https://example.invalid/poster.jpg")])])])
    }
    private func related(_ values: [(String, JSONValue)]) -> JSONValue {
        .object(["data": .array(values.map { role, resource in .object(["attributes": .object(["role": .string(role)]),
            "relationships": .object(["destination": .object(["data": .object(["id": resource["id"], "type": .string("anime")])])])]) }),
            "included": .array(values.map { $0.1 })])
    }
    private func fixture(_ id: Int = 1) -> FranchiseFixtureTransport {
        let root = resource(id)
        return FranchiseFixtureTransport([.kitsu(id): .object(["data": root]), .related(id): related([])])
    }
    private func loadedGraph(_ service: AnimeFranchiseService, id: String) async throws -> AnimeFranchise {
        let value = try await service.franchise(for: id)
        return try XCTUnwrap(value)
    }

    func testValidatedPublicRoutesCoalesceRequestsAndNeverExceedFourMetadataCalls() async throws {
        for invalid in [AnimeFranchiseRequest.kitsu(0), .related(-1), .mapping("kitsu:1/../login"), .mapping("tt1?token=x"), .relations(source: "../account", id: 1)] {
            XCTAssertThrowsError(try invalid.url)
        }
        XCTAssertEqual(try AnimeFranchiseRequest.mapping("mal:123").url, "https://api.ani.zip/mappings?mal_id=123")
        var replies: [AnimeFranchiseRequest: JSONValue] = [:]
        for id in 1...12 { replies[.kitsu(id)] = .object(["data": resource(id)]) }
        let transport = FranchiseFixtureTransport(replies), service = AnimeFranchiseService(transport: transport, anilistSpacing: 0)
        async let first = service.response(.kitsu(1))
        async let second = service.response(.kitsu(1))
        let pair = try await [first, second]; XCTAssertEqual(pair[0], pair[1])
        try await withThrowingTaskGroup(of: Void.self) { group in
            for id in 2...12 { group.addTask { _ = try await service.response(.kitsu(id)) } }
            try await group.waitForAll()
        }
        let calls = await transport.requests(), maximum = await transport.maximumActive()
        XCTAssertEqual(calls.filter { $0 == .kitsu(1) }.count, 1); XCTAssertGreaterThan(maximum, 1); XCTAssertLessThanOrEqual(maximum, 4)
        await transport.replace(.mapping("kitsu:1"), with: try json(#"{"mappings":{"kitsu_id":99}}"#))
        do { _ = try await service.response(.mapping("kitsu:1")); XCTFail("A different title's mapping must fail") } catch {}
        await transport.replace(.mapping("kitsu:1"), with: try json(#"{"mappings":{"kitsu_id":1,"anilist_id":10}}"#))
        let recovered = try await service.response(.mapping("kitsu:1"))
        XCTAssertEqual(recovered["mappings"]["anilist_id"].integer, 10)
        let final = await transport.requests(); XCTAssertEqual(final.filter { $0 == .mapping("kitsu:1") }.count, 2)
    }

    func testKitsuTraversalUsesThreeWavesSkipsUnrelatedEntriesAndWarmsIncludedMetadata() async throws {
        let transport = fixture()
        await transport.replace(.related(1), with: related([("sequel", resource(2)), ("side_story", resource(99))]))
        await transport.replace(.related(2), with: related([("prequel", resource(1)), ("sequel", resource(3))]))
        await transport.replace(.related(3), with: related([("sequel", resource(4))]))
        await transport.replace(.related(4), with: related([("sequel", resource(5))]))
        let service = AnimeFranchiseService(transport: transport, anilistSpacing: 0)
        let graph = try await loadedGraph(service, id: "kitsu:1")
        XCTAssertEqual(Set(graph.entries.map(\.id)), ["kitsu:1", "kitsu:2", "kitsu:3", "kitsu:4"])
        XCTAssertEqual(graph.rootID, "kitsu:1"); XCTAssertTrue(graph.complete)
        _ = try await service.response(.kitsu(2))
        let calls = await transport.requests()
        XCTAssertEqual(calls.filter { $0 == .related(1) }.count, 1)
        XCTAssertFalse(calls.contains(.kitsu(2)), "The complete included resource is reused")
        XCTAssertFalse(calls.contains(.related(4))); XCTAssertFalse(calls.contains(.related(99)))
    }

    func testRootPrefersSeriesOverEarlierMoviesAndStopsCycles() async throws {
        let transport = fixture(3)
        await transport.replace(.related(3), with: related([("prequel", resource(90, subtype: "movie", date: "1990-01-01")), ("prequel", resource(2, date: "2010-01-01"))]))
        await transport.replace(.related(2), with: related([("prequel", resource(1, date: "2000-01-01"))]))
        await transport.replace(.related(1), with: related([("prequel", resource(3))]))
        await transport.replace(.related(90), with: related([]))
        let graph = try await loadedGraph(AnimeFranchiseService(transport: transport, anilistSpacing: 0), id: "kitsu:3")
        XCTAssertEqual(graph.rootID, "kitsu:1")
        XCTAssertTrue(graph.entries.first(where: { $0.id == "kitsu:90" })?.extra == true)
        XCTAssertEqual(graph.entries.filter(\.current).map(\.id), ["kitsu:3"])
        let calls = await transport.requests(); XCTAssertEqual(calls.filter { $0 == .related(3) }.count, 1)
    }

    func testAniListComplementWalksSixLevelsAndResolvesRealKitsuAliases() async throws {
        let transport = fixture()
        await transport.replace(.relations(source: "kitsu", id: 1), with: try json(#"{"kitsu":1,"anilist":100}"#))
        for id in 100...107 {
            let next = id + 1
            let node = try json("""
            {"id":\(next),"format":"TV","episodes":12,"title":{"english":"Synthetic Part \(next)"},"startDate":{"year":\(2000 + next),"month":1,"day":1}}
            """)
            await transport.replace(.anilist(id), with: .object(["Media": .object(["id": .integer(Int64(id)), "relations": .object(["edges": .array([
                .object(["relationType": .string("SEQUEL"), "node": node])])])])]))
        }
        await transport.replace(.relations(source: "anilist", id: 101), with: try json(#"{"anilist":101,"kitsu":88}"#))
        let graph = try await loadedGraph(AnimeFranchiseService(transport: transport, anilistSpacing: 0), id: "kitsu:1")
        XCTAssertEqual(graph.entries.count, 7)
        XCTAssertTrue(graph.entries.contains(where: { $0.id == "kitsu:88" }))
        XCTAssertFalse(graph.entries.contains(where: { $0.id == "anilist:101" || $0.id == "anilist:107" }))
        let calls = await transport.requests(); XCTAssertFalse(calls.contains(.anilist(106)))
    }

    func testPartialGraphIsNotCachedAndRecoversWithoutRepeatingSuccessfulRequests() async throws {
        let transport = FranchiseFixtureTransport([.kitsu(1): .object(["data": resource(1)])])
        let service = AnimeFranchiseService(transport: transport, anilistSpacing: 0)
        async let first = service.franchise(for: "kitsu:1")
        async let second = service.franchise(for: "kitsu:1")
        let values = try await [first, second]
        XCTAssertEqual(values.compactMap { $0?.complete }, [false, false])
        await transport.replace(.related(1), with: related([("sequel", resource(2))]))
        let missingChild = try await loadedGraph(service, id: "kitsu:1")
        XCTAssertFalse(missingChild.complete, "A failed descendant request must not disappear from the bounded collection")
        await transport.replace(.related(2), with: related([]))
        let recovered = try await loadedGraph(service, id: "kitsu:1")
        XCTAssertTrue(recovered.complete); XCTAssertEqual(recovered.entries.count, 2)
        let before = await transport.requests()
        _ = try await service.franchise(for: "kitsu:1")
        let after = await transport.requests(); XCTAssertEqual(before, after)
        XCTAssertEqual(after.filter { $0 == .kitsu(1) }.count, 1)
    }

    func testDesktopExtrasUpcomingAndDuplicateTitlePriorityRemainDistinct() throws {
        let now = try XCTUnwrap(ISO8601DateParser.shared.date("2026-10-19T00:00:00Z"))
        let current = try XCTUnwrap(AnimeFranchiseEntry.kitsu(resource(1, name: "AC: Synthetic Second Season"), currentID: 1, now: now))
        let alias = try XCTUnwrap(AnimeFranchiseEntry.anilist(json(#"{"id":10,"format":"TV","episodes":12,"title":{"english":"Synthetic Season 2"},"startDate":{"year":2020}}"#)))
        XCTAssertEqual(AnimeFranchise.normalizedName(current.media.name), AnimeFranchise.normalizedName(alias.media.name))
        XCTAssertEqual(AnimeFranchise.merged([alias, current]).map(\.id), ["kitsu:1"])
        XCTAssertEqual(current.media.ratingSource, "Kitsu"); XCTAssertEqual(current.media.imdbRating, "8.5")
        XCTAssertTrue(try XCTUnwrap(AnimeFranchiseEntry.kitsu(resource(2, subtype: "ONA", episodes: 12), currentID: 1, now: now)).extra)
        XCTAssertTrue(try XCTUnwrap(AnimeFranchiseEntry.kitsu(resource(3, episodes: 1), currentID: 1, now: now)).extra)
        let future = try XCTUnwrap(AnimeFranchiseEntry.kitsu(resource(4, episodes: 1, date: "2027-01-01", status: "unreleased"), currentID: 1, now: now))
        XCTAssertTrue(future.upcoming); XCTAssertFalse(future.extra)
        XCTAssertFalse(current.extra)
    }

    @MainActor func testFranchiseSelectionKeepsTheActualProviderAndRejectsUnknownOwnerOrWrongMetadata() async throws {
        let transport = fixture()
        await transport.replace(.related(1), with: related([("sequel", resource(2))]))
        await transport.replace(.related(2), with: related([]))
        let library = LibraryModel(), root = Media(id: "kitsu:1", type: "series", name: "Root", videos: [Episode(id: "kitsu:1:1", season: 1, episode: 1)])
        var context = UUID()
        let model = DetailModel(root, service: HarborService(), metadataLoaded: true, contextRevision: { context })
        await model.loadFranchise(owner: "guest", library: library, provider: AnimeFranchiseService(transport: transport, anilistSpacing: 0))
        XCTAssertEqual(model.activeFranchiseEntryID, "kitsu:1")
        model.selectedEpisode = root.videos?.first
        model.offers = [StreamOffer(id: 1, raw: .object(["url": .string("https://example.invalid/previous.mp4")]))]
        let wrongOwner = await model.selectFranchiseEntry("kitsu:2", owner: "other", library: library, fetch: { _ in XCTFail("Owner mismatch must not load another entry"); return root })
        XCTAssertFalse(wrongOwner)
        let wrongID = await model.selectFranchiseEntry("kitsu:2", owner: "guest", library: library, fetch: { _ in Media(id: "kitsu:999", type: "series", name: "Wrong") })
        XCTAssertFalse(wrongID); XCTAssertEqual(model.media.id, root.id)
        let cancelled = await model.selectFranchiseEntry("kitsu:2", owner: "guest", library: library, fetch: { _ in throw CancellationError() })
        XCTAssertFalse(cancelled); XCTAssertEqual(model.selectedEpisode?.id, "kitsu:1:1")
        XCTAssertEqual(model.franchiseSelectionRevision, 0)
        let stale = await model.selectFranchiseEntry("kitsu:2", owner: "guest", library: library, fetch: { entry in
            context = UUID(); return entry.media
        })
        XCTAssertFalse(stale); XCTAssertEqual(model.media.id, root.id); XCTAssertEqual(model.franchiseSelectionRevision, 0)
        let selected = await model.selectFranchiseEntry("kitsu:2", owner: "guest", library: library, fetch: { entry in
            var media = entry.media; media.videos = [Episode(id: "kitsu:2:1", season: 1, episode: 1)]; return media
        })
        XCTAssertTrue(selected); XCTAssertEqual(model.media.id, "kitsu:2")
        XCTAssertEqual(model.media.videos?.first?.id, "kitsu:2:1"); XCTAssertNil(model.selectedEpisode)
        XCTAssertTrue(model.offers.isEmpty)
        XCTAssertEqual(model.franchiseSelectionRevision, 1)
        XCTAssertTrue(model.metadataReady); XCTAssertNil(model.error)
        let unknown = await model.selectFranchiseEntry("kitsu:999", owner: "guest", library: library, fetch: { _ in XCTFail("Unknown franchise entry must be rejected"); return root })
        XCTAssertFalse(unknown)
    }

    @MainActor func testBleachSplitEntriesKeepTheirOwnSelectorAndDoNotReintroduceTheOriginalRoot() async throws {
        let transport = fixture(43078)
        await transport.replace(.related(43078), with: related([("prequel", resource(244, name: "Bleach", date: "2004-01-01")),
            ("sequel", resource(46903, name: "Bleach Thousand Year Blood War Part 2"))]))
        await transport.replace(.related(244), with: related([("sequel", resource(43078))]))
        await transport.replace(.related(46903), with: related([]))
        let context = UUID()
        let model = DetailModel(Media(id: "kitsu:43078", type: "series", name: "TYBW"), service: HarborService(), metadataLoaded: true, contextRevision: { context })
        await model.loadFranchise(owner: "guest", library: LibraryModel(), provider: AnimeFranchiseService(transport: transport, anilistSpacing: 0))
        XCTAssertEqual(model.franchise?.rootID, "kitsu:244")
        XCTAssertTrue(model.soloFranchiseEntry); XCTAssertEqual(model.episodeOrderScope, "solo")
        XCTAssertFalse(model.franchiseChoices.contains(where: { $0.id == "kitsu:244" }))
        XCTAssertTrue(model.franchiseChoices.contains(where: { $0.id == "kitsu:46903" }))
    }

    func testKitsuIdentitySurvivesTVDBSupplementWithoutChangingPlayableEpisodes() async throws {
        let source = [Episode(id: "kitsu:7:1", season: 1, episode: 1)]
        let mapping = try json(#"{"mappings":{"kitsu_id":7,"thetvdb_id":42},"episodes":{}}"#)
        let variants = AnimeEpisodeService.variants(mapping: mapping, canonical: source, original: source, animeIdentity: true)
        XCTAssertEqual(variants.kitsuID, 7)
        let value = await TVDBService(transport: FranchiseTVDBTransport()).supplement(variants, for: Media(id: "kitsu:7", type: "series", name: "Synthetic"))
        XCTAssertEqual(value.kitsuID, 7); XCTAssertEqual(value.tvdbSeriesID, 42)
        XCTAssertEqual(value.seasons.map(\.id), source.map(\.id)); XCTAssertEqual(value.seasons.map(\.watchedKey), source.map(\.watchedKey))
    }
}

import XCTest
@testable import Harbor

private func serviceFixtureMedia(_ id: String, kind: String) -> Media {
    var media = Media(id: id, type: kind, name: id)
    media.poster = "https://example.invalid/\(id).jpg"; return media
}

@MainActor final class ServiceCatalogTests: XCTestCase {
    private func service() throws -> StreamingServiceDefinition { try XCTUnwrap(StreamingServiceDefinition.all.first { $0.key == "prime" }) }
    private func category(_ id: String) throws -> ServiceCatalogCategory { try XCTUnwrap(ServiceCatalogCategory.all.first { $0.id == id }) }
    private var configuration: MetadataConfiguration { .init(tmdbKey: "fixture-not-an-account-key", region: "ES", language: "es-ES", translateTitles: true) }

    func testCategoriesUseDistinctMovieTVGenresAndTheFullProviderCatalog() throws {
        let service = try service()
        XCTAssertEqual(ServiceCatalogCategory.all.count, 14)
        let action = try category("action"), movies = try XCTUnwrap(action.definition(service, kind: "movie", region: "ES")), tv = try XCTUnwrap(action.definition(service, kind: "series", region: "ES"))
        XCTAssertEqual(movies.parameters["with_genres"], "28"); XCTAssertEqual(tv.parameters["with_genres"], "10759")
        XCTAssertEqual(tv.parameters["with_watch_providers"], "9|119"); XCTAssertEqual(tv.parameters["watch_region"], "ES")
        XCTAssertEqual(tv.parameters["with_watch_monetization_types"], "flatrate|free|ads"); XCTAssertEqual(tv.parameters["include_adult"], "false")
        XCTAssertNil(tv.parameters["vote_count.gte"], "The complete service page must not inherit the preview's minimum-vote filter")
        XCTAssertNil(try category("reality").definition(service, kind: "movie", region: "ES"))
        XCTAssertNil(try category("romance").definition(service, kind: "series", region: "ES"))
        XCTAssertEqual(try category("horror").definition(service, kind: "series", region: "")?.parameters["with_genres"], "9648")
        XCTAssertEqual(action.definition(service, kind: "series", region: "")?.parameters["watch_region"], "US")
    }

    func testPagingKeepsAllTitlesLimitsConcurrencyAndStopsAtTwoHundredPerKind() async throws {
        let fixture = PageFixture(duplicateSecondPage: true), model = ServiceCatalogModel { rail, page, configuration in try await fixture.fetch(rail, page: page) }
        for _ in 0..<12 { await model.load(service: try service(), category: try category("all"), configuration: configuration, owner: "one", more: true) }
        XCTAssertEqual(model.movies.count, 200); XCTAssertEqual(model.series.count, 200)
        XCTAssertEqual(Set(model.movies.map(\.id)).count, 200); XCTAssertEqual(Set(model.series.map(\.id)).count, 200)
        XCTAssertFalse(model.hasMore); XCTAssertFalse(model.loading); XCTAssertNil(model.error)
        let calls = await fixture.calls
        XCTAssertEqual(calls.count, 22); XCTAssertEqual(Set(calls.filter { $0.kind == "movie" }.map(\.page)), Set(1...11))
        let peak = await fixture.peak
        XCTAssertLessThanOrEqual(peak, 2)
    }

    func testSwitchingOwnerRejectsAnOldUncooperativeRequestWithoutChangingNewRows() async throws {
        let ready = XCTestExpectation(description: "Both first-owner requests reached the controlled transport")
        let fixture = HoldingFixture(ready: ready), model = ServiceCatalogModel { rail, page, configuration in try await fixture.fetch(rail) }
        let service = try service(), category = try category("all"), configuration = configuration
        let previous = Task { await model.load(service: service, category: category, configuration: configuration, owner: "previous") }
        let result = await XCTWaiter.fulfillment(of: [ready], timeout: 5)
        XCTAssertEqual(result, .completed)
        guard result == .completed else { previous.cancel(); await fixture.release(); await previous.value; return }
        await model.load(service: service, category: category, configuration: configuration, owner: "current")
        XCTAssertEqual(model.allTitles.count, 2); XCTAssertTrue(model.allTitles.allSatisfy { $0.id.hasPrefix("current-") })
        await fixture.release(); await previous.value
        XCTAssertEqual(model.allTitles.count, 2); XCTAssertTrue(model.allTitles.allSatisfy { $0.id.hasPrefix("current-") })
    }

    func testFailedKindRetriesItsUnconsumedPageAndKeepsSuccessfulTitles() async throws {
        let fixture = PageFixture(failFirstSeries: true), model = ServiceCatalogModel { rail, page, configuration in try await fixture.fetch(rail, page: page) }
        let service = try service(), category = try category("all")
        await model.load(service: service, category: category, configuration: configuration, owner: "one")
        XCTAssertEqual(model.movies.count, 20); XCTAssertTrue(model.series.isEmpty); XCTAssertNotNil(model.error)
        let previous = model.movies.map(\.id)
        await model.load(service: service, category: category, configuration: configuration, owner: "one", more: true)
        XCTAssertEqual(Array(model.movies.prefix(20).map(\.id)), previous)
        XCTAssertEqual(model.movies.count, 40); XCTAssertEqual(model.series.count, 20); XCTAssertNil(model.error)
        let seriesPages = await fixture.calls.filter { $0.kind == "series" }.map(\.page)
        XCTAssertEqual(seriesPages, [1, 1])
    }

    func testChangingCategoryClearsPreviousRowsAndDoesNotRequestAnIneligibleKind() async throws {
        let fixture = PageFixture(), model = ServiceCatalogModel { rail, page, configuration in try await fixture.fetch(rail, page: page) }
        let service = try service()
        await model.load(service: service, category: try category("all"), configuration: configuration, owner: "one")
        XCTAssertEqual(model.series.count, 20)
        await model.load(service: service, category: try category("romance"), configuration: configuration, owner: "one")
        XCTAssertTrue(model.series.isEmpty); XCTAssertEqual(model.movies.count, 20)
        let calls = await fixture.calls
        XCTAssertEqual(calls.count, 3); XCTAssertEqual(calls.last?.kind, "movie"); XCTAssertEqual(calls.last?.genre, "10749")
    }

    private actor PageFixture {
        struct Call: Sendable { let kind: String; let page: Int; let genre: String? }
        private(set) var calls: [Call] = []
        private(set) var peak = 0
        private var active = 0
        private var failFirstSeries: Bool
        private let duplicateSecondPage: Bool
        init(failFirstSeries: Bool = false, duplicateSecondPage: Bool = false) {
            self.failFirstSeries = failFirstSeries; self.duplicateSecondPage = duplicateSecondPage
        }
        func fetch(_ rail: DiscoveryRail, page: Int) async throws -> [Media] {
            calls.append(Call(kind: rail.kind, page: page, genre: rail.parameters["with_genres"]))
            active += 1; peak = max(peak, active)
            defer { active -= 1 }
            await Task.yield()
            if rail.kind == "series", failFirstSeries { failFirstSeries = false; throw HarborError(code: "test-network") }
            let contentPage = duplicateSecondPage && page == 2 ? 1 : page
            return (0..<20).map { serviceFixtureMedia("\(rail.kind)-\(rail.parameters["with_genres"] ?? "all")-\(contentPage)-\($0)", kind: rail.kind) }
        }
    }

    private actor HoldingFixture {
        private let ready: XCTestExpectation
        private var count = 0
        private var released = false
        private var held: [(String, CheckedContinuation<[Media], Error>)] = []
        init(ready: XCTestExpectation) { self.ready = ready }
        func fetch(_ rail: DiscoveryRail) async throws -> [Media] {
            count += 1
            if count <= 2 {
                if released { return [serviceFixtureMedia("previous-" + rail.kind, kind: rail.kind)] }
                return try await withCheckedThrowingContinuation { continuation in
                    held.append((rail.kind, continuation))
                    if held.count == 2 { ready.fulfill() }
                }
            }
            return [serviceFixtureMedia("current-" + rail.kind, kind: rail.kind)]
        }
        func release() {
            released = true
            let pending = held; held = []
            for (kind, continuation) in pending { continuation.resume(returning: [serviceFixtureMedia("previous-" + kind, kind: kind)]) }
        }
    }
}

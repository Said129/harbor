import XCTest
@testable import Harbor

@MainActor private final class ControlledBillboard: MusicBillboardCalling {
    var heldRanking: CheckedContinuation<MusicBillboardRanking, any Error>?
    var heldItem: CheckedContinuation<MusicCatalogItem?, any Error>?
    private(set) var requests: [String] = []
    func ranking(_ chart: String, refresh: Bool) async throws -> MusicBillboardRanking {
        requests.append(chart)
        if chart == "hot-100" { return try await withCheckedThrowingContinuation { heldRanking = $0 } }
        return value(chart)
    }
    func resolve(_ item: MusicCatalogItem, catalog: any MusicCatalogCalling) async throws -> MusicCatalogItem? {
        try await withCheckedThrowingContinuation { heldItem = $0 }
    }
    func finishRanking() { heldRanking?.resume(returning: value("hot-100")); heldRanking = nil }
    func finishItem(_ item: MusicCatalogItem) { heldItem?.resume(returning: item); heldItem = nil }
    func dispose() { }
    private func value(_ chart: String) -> MusicBillboardRanking {
        let one = MusicCatalogItem.album(.init(id: chart + ":one", connectorId: "catalog", title: "Owned Album", artist: "First Artist", artwork: ""))
        let two = MusicCatalogItem.album(.init(id: chart + ":two", connectorId: "catalog", title: "Other Album", artist: "Second Artist", artwork: ""))
        return .init(chartId: chart, date: "2026-10-24", entries: [.init(rank: 1, item: one), .init(rank: 17, item: two)])
    }
}
@MainActor final class MusicBillboardModelTests: XCTestCase {
    func testEmptySearchShowsEveryPublishedRankBeforeFilteringAndAfterClearingSearch() async throws {
        let client = ControlledBillboard(), model = MusicBillboardModel(); model.select("billboard-200")
        await model.load(client: client)
        XCTAssertEqual(model.query, ""); XCTAssertEqual(model.entries(locale: .init(identifier: "en")).map(\.rank), [1, 17])
        model.query = "SECOND ARTIST"; XCTAssertEqual(model.entries(locale: .init(identifier: "en")).map(\.rank), [17])
        model.query = ""; XCTAssertEqual(model.entries(locale: .init(identifier: "en")).map(\.rank), [1, 17])
    }
    func testChangingChartAndCountryDiscardsLateRankingAndResolutionAndKeepsPublishedRanksDuringSearch() async throws {
        let client = ControlledBillboard(), model = MusicBillboardModel()
        let old = Task { await model.load(client: client) }
        try await wait { client.heldRanking != nil }
        model.select("billboard-200"); await model.load(client: client); client.finishRanking(); await old.value
        XCTAssertEqual(model.ranking?.chartId, "billboard-200"); XCTAssertFalse(model.loading); XCTAssertFalse(model.failure)
        let calls = client.requests; await model.load(client: client); XCTAssertEqual(client.requests, calls)
        model.query = "SECOND ARTIST"
        XCTAssertEqual(model.entries(locale: .init(identifier: "en")).map(\.rank), [17], "Searching must not renumber the chart")
        model.query = ""
        let item = try XCTUnwrap(model.ranking?.entries.first?.item)
        let lateOpen = Task { await model.open(item, client: client, catalog: MusicCatalogClient()) }
        try await wait { client.heldItem != nil }
        model.query = "old search"; model.selectCountry("GB"); client.finishItem(item); await lateOpen.value
        XCTAssertEqual(model.chart?.country, "GB"); XCTAssertEqual(model.query, ""); XCTAssertNil(model.ranking)
        XCTAssertNil(model.opened); XCTAssertNil(model.busy); XCTAssertNil(model.unmatched)
        await model.load(client: client); XCTAssertEqual(model.ranking?.chartId, model.chartID)
        XCTAssertTrue(model.available.allSatisfy { $0.country == "GB" })
    }
    private func wait(_ condition: @MainActor () -> Bool) async throws {
        for _ in 0..<150 { if condition() { return }; try await Task.sleep(for: .milliseconds(20)) }
        XCTFail("The owned Billboard request did not reach its gate"); throw HarborError(code: "owned-billboard-gate")
    }
}

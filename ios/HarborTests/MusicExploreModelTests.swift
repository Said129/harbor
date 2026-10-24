import XCTest
@testable import Harbor

@MainActor private final class ControlledExplore: MusicExploreCalling {
    private let asset: MusicExploreAsset
    init() throws { asset = try MusicExploreAsset.read() }
    private(set) var homeCalls = 0
    private(set) var pages: [(Int, Int)] = []
    var filterGate: CheckedContinuation<[MusicGenre], any Error>?
    var depthGate: CheckedContinuation<MusicGenreSelection, any Error>?
    func filter(_ filters: MusicGenreFilters, countryNames: [String: String], genreNames: [String: String]) async throws -> [MusicGenre] {
        if filters.query == "slow" { return try await withCheckedThrowingContinuation { filterGate = $0 } }
        return asset.definitions.genres.filter { $0.id == 152 }
    }
    func chart() async throws -> MusicGenreSelection { homeCalls += 1; return selectionValue(1) }
    func selection(_ genre: Int) async throws -> MusicGenreSelection { selectionValue(genre == 152 ? 1 : 99) }
    func related(_ genre: Int) async throws -> [MusicGenre] { [] }
    func tracks(_ genre: Int, page: Int) async throws -> MusicGenreSelection {
        pages.append((genre, page))
        if genre == 152 { return try await withCheckedThrowingContinuation { depthGate = $0 } }
        return selectionValue(100, done: true)
    }
    func finishFilter() { filterGate?.resume(returning: asset.definitions.genres.filter { $0.id == 132 }); filterGate = nil }
    func finishDepth() { depthGate?.resume(returning: selectionValue(2, done: true)); depthGate = nil }
    func dispose() { }
    private func selectionValue(_ id: Int, done: Bool? = nil) -> MusicGenreSelection {
        let track = MusicTrack(id: "deezer:track:\(id)", connectorId: "catalog", sourceId: String(id), playbackUrl: nil, title: "Owned \(id)", artist: "Owned artist", album: nil, artwork: "", durationSeconds: 100, durationLabel: "1:40")
        return .init(tracks: [track], positions: [nil], artists: [], albums: [], playlists: [], popularity: [:], done: done)
    }
}
@MainActor final class MusicExploreModelTests: XCTestCase {
    func testLateGenreFilterCannotReplaceNewFiltersAndTheLoadedChartSurvivesReturning() async throws {
        let client = try ControlledExplore()
        let actual = MusicExploreModel(client: client)
        await actual.loadChart(); await actual.loadChart(); XCTAssertEqual(client.homeCalls, 1)
        let old = Task { await actual.filter(.init(query: "slow"), locale: Locale(identifier: "en"), debounce: false) }
        try await wait { client.filterGate != nil }
        await actual.filter(.init(query: "Rock"), locale: Locale(identifier: "en"), debounce: false)
        client.finishFilter(); await old.value
        XCTAssertEqual(actual.genres.map(\.id), [152]); XCTAssertFalse(actual.filtering); XCTAssertNotNil(actual.chart)
        let invalid = MusicGenreFilters.read(#"{"query":"Rock","countries":["US","XX"],"family":"not-a-style"}"#, definitions: actual.asset?.definitions)
        XCTAssertEqual(invalid.countries, ["US"]); XCTAssertEqual(invalid.family, "")
    }
    func testLateDepthPageCannotAppendToAnotherGenreAndItsCursorRestartsAtTheOriginalFirstPage() async throws {
        let client = try ControlledExplore(), model = MusicGenreModel()
        await model.load(152, client: client)
        let old = Task { await model.loadNext(client: client) }
        try await wait { client.depthGate != nil }
        await model.load(132, client: client); client.finishDepth(); await old.value
        XCTAssertEqual(model.selection?.tracks.map(\.id), ["deezer:track:99"]); XCTAssertTrue(model.more)
        await model.loadNext(client: client)
        XCTAssertEqual(model.selection?.tracks.map(\.id), ["deezer:track:99", "deezer:track:100"]); XCTAssertFalse(model.more)
        XCTAssertEqual(client.pages.map { "\($0.0):\($0.1)" }, ["152:0", "132:0"])
    }
    private func wait(_ ready: @MainActor () -> Bool) async throws {
        for _ in 0..<150 { if ready() { return }; try await Task.sleep(for: .milliseconds(20)) }
        XCTFail("The original request did not reach its owned gate"); throw HarborError(code: "owned-explore-model-gate")
    }
}

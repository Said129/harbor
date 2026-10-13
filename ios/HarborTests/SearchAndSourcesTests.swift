import XCTest
@testable import Harbor

final class SearchAndSourcesTests: XCTestCase {
    // Actual public anime-kitsu metadata contract for Danmachi S1E7 (MAL 28121).
    func testDanmachiRequestsBothVerifiedIdentitiesWithoutCrossingEpisodes() async throws {
        let json = Data(#"{"id":"kitsu:9962","type":"series","name":"Dungeon ni Deai wo Motomeru no wa Machigatteiru Darou ka","imdb_id":"tt4728568","releaseInfo":"2015","videos":[{"id":"kitsu:9962:7","season":1,"episode":7,"imdb_id":"tt4728568","imdbSeason":1,"imdbEpisode":7}]}"#.utf8)
        let value = try JSONDecoder().decode(JSONValue.self, from: json)
        let media = try XCTUnwrap(Media.parse(value, kind: "series"))
        let ids = StreamRequestPolicy.ids(media, videoID: "kitsu:9962:7", season: 1, episode: 7)
        XCTAssertEqual(ids, ["kitsu:9962:7", "tt4728568:1:7"])
        let addon = Addon(manifest: .object(["id": .string("imdb-only"), "name": .string("IMDb addon"), "types": .array([.string("series")]), "resources": .array([.string("stream")]), "idPrefixes": .array([.string("tt")])]), transportUrl: "https://example.org/manifest.json", enabled: true)
        var plans: [RequestPlan] = []
        for id in ids { plans += try await CoreBridge().call("resources", ["addons": try .encoded([addon]), "resource": .string("stream"), "kind": .string("series"), "id": .string(id)]) }
        XCTAssertEqual(plans.count, 1, "An IMDb-only addon was never queried by the former single-Kitsu request")
        XCTAssertTrue(plans[0].url.contains("tt4728568"))
        var mismatched = media; mismatched.videos?[0].imdbEpisode = 8
        XCTAssertEqual(StreamRequestPolicy.ids(mismatched, videoID: "kitsu:9962:7", season: 1, episode: 7), ["kitsu:9962:7"], "Never request the wrong mapped anime episode")
        var missing = media; missing.videos?[0].imdbSeason = nil
        XCTAssertEqual(StreamRequestPolicy.ids(missing, videoID: "kitsu:9962:7", season: 1, episode: 7), ["kitsu:9962:7"])
        let encoded = try JSONEncoder().encode(media)
        XCTAssertEqual(try JSONDecoder().decode(Media.self, from: encoded).videos?.first?.imdbID, "tt4728568")
    }

    func testAnimeFiltersUseAnimeSizePolicyAndYear() throws {
        let media = Media(id: "kitsu:9962", type: "series", name: "Danmachi", releaseInfo: "2015")
        let trust = StreamFilterConfiguration(level: "balanced", addonOrder: true).trust(media, season: 1, episode: 7)
        XCTAssertEqual(trust["isAnime"], .bool(true)); XCTAssertEqual(trust["expectedYear"], .integer(2015))
        XCTAssertEqual(trust["allowSeasonPacks"], .bool(true)); XCTAssertEqual(trust["allowSizeOutliers"], .bool(true))
        let off = StreamFilterConfiguration(level: "off", addonOrder: true).trust(media, season: 1, episode: 7)
        XCTAssertEqual(off["disabled"], .bool(true))
        let source: JSONValue = .object(["addonId": .string("test"), "addonName": .string("Test"), "title": .string("Danmachi.S01E07.1080p.WEB-DL.H264.AAC"), "url": .string("https://example.org/video.mkv"), "size": .integer(180 * 1_024 * 1_024)])
        let request = try JSONEncoder().encode(JSONValue.object(["operation": .string("rank"), "streams": .array([source]), "trust": trust, "score": .object([:])]))
        XCTAssertEqual(try CoreBridge.invoke(request, as: JSONValue.self)["picker"]["all"].array.count, 1, "A normal anime episode must not be rejected using feature-film size limits")
    }

    @MainActor func testRecentSearchesPersistDeduplicateLimitAndRemove() throws {
        let suite = "search-tests-" + UUID().uuidString
        let storage = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { storage.removePersistentDomain(forName: suite) }
        let history = SearchHistory(storage: storage)
        history.record(" Oppenheimer "); history.record("Danmachi"); history.record("oppenheimer")
        XCTAssertEqual(history.items, ["oppenheimer", "Danmachi"])
        history.remove("Danmachi")
        XCTAssertEqual(SearchHistory(storage: storage).items, ["oppenheimer"])
        for number in 0..<12 { history.record(String(number)) }
        XCTAssertEqual(history.items.count, 8); XCTAssertEqual(history.items.first, "11")
        history.clear(); XCTAssertTrue(SearchHistory(storage: storage).items.isEmpty)
    }

    func testSearchHidesEmptyKitsuNavigationAndDuplicateResults() {
        let addon = Addon(manifest: .object([:]), transportUrl: "https://example.org/manifest.json", enabled: true)
        func row(_ id: String, kind: String, items: [Media]) -> CatalogRow {
            CatalogRow(plan: RequestPlan(key: id, url: "https://example.org/catalog.json", title: "Search", kind: kind, addon: addon, addonPriority: 0, timeoutMs: 8_000, catalog: nil), metas: items)
        }
        let movie = Media(id: "tt15398776", type: "movie", name: "Oppenheimer")
        let rows = SearchPresentation.rows([row("movie", kind: "movie", items: [movie]), row("kitsu", kind: "series", items: []), row("duplicate", kind: "movie", items: [movie]), row("addons", kind: "addon_catalog", items: [movie])])
        XCTAssertEqual(rows.map(\.id), ["movie"])
    }

    func testAccountEditsPreserveOtherDeviceChanges() {
        func addon(_ id: String, name: String? = nil) -> Addon { .init(manifest: .object(["id": .string(id), "name": .string(name ?? id)]), transportUrl: "https://example.org/\(id)/manifest.json", enabled: true) }
        let a = addon("a"), b = addon("b"), c = addon("c"), d = addon("d")
        let baseline = AccountCollection(addons: [a, b], records: [])
        let remoteB = addon("b", name: "Changed on Desktop")
        let merged = baseline.merging([b, d], into: [a, remoteB, c])
        XCTAssertEqual(merged.map(\.id), [b.id, c.id, d.id])
        XCTAssertEqual(merged.first?.name, "Changed on Desktop")
        XCTAssertEqual(baseline.merging([a, b, d], into: [a, c]).map(\.id), [a.id, c.id, d.id], "A remotely removed addon must stay removed")
        XCTAssertEqual(baseline.merging([b, a], into: [a, c, b]).map(\.id), [b.id, c.id, a.id])
    }
}

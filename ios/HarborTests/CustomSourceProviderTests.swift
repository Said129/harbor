import XCTest
@testable import Harbor

final class CustomSourceProviderTests: XCTestCase {
    func testTraktRequestsUseOnlyTheFixedAnonymousOriginAndRejectInjectedPathsAndInvalidPages() throws {
        let request = try HTTPClient.traktListRequest(id: "1248149", page: 2)
        XCTAssertEqual(request.url?.absoluteString, "https://api.trakt.tv/lists/1248149/items?page=2&limit=20")
        XCTAssertEqual(request.value(forHTTPHeaderField: "trakt-api-version"), "2")
        XCTAssertNotNil(request.value(forHTTPHeaderField: "trakt-api-key"))
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization")); XCTAssertNil(request.value(forHTTPHeaderField: "Cookie"))
        for id in ["0", "-1", "1/../../identity", "https://owned.invalid/", "1?token=owned", "1#fragment"] {
            XCTAssertThrowsError(try HTTPClient.traktListRequest(id: id, page: 1))
        }
        for page in [0, -1, 1_001] { XCTAssertThrowsError(try HTTPClient.traktListRequest(id: "1", page: page)) }
        let raw: JSONValue = .object(["type": .string("show"), "show": .object(["title": .string("Owned title"),
            "ids": .object(["tmdb": .integer(42), "imdb": .string("tt1234567")])])])
        XCTAssertEqual(CustomSourceCatalog.traktMedia(raw)?.id, "tmdb:tv:42", "Desktop chooses TMDB before IMDb for public list identities")
    }
    func testTheActualNativePlannerResolvesOnlyTheInstalledCatalogAndRetainsItsConfiguredRequestLocally() async throws {
        let manifest: JSONValue = .object(["id": .string("owned.addon"), "version": .string("1.0.0"), "name": .string("Owned source"),
            "resources": .array([.string("catalog")]), "types": .array([.string("movie")]),
            "catalogs": .array([.object(["id": .string("owned"), "type": .string("movie"), "name": .string("Owned titles")])])])
        let addon = Addon(manifest: manifest, transportUrl: "https://owned.invalid/configured/manifest.json", enabled: true)
        let result = try await HarborService().sourceCatalog(addonID: "owned.addon", type: "movie", id: "owned", addons: [addon])
        XCTAssertEqual(result.plan.catalog?.id, "owned"); XCTAssertEqual(result.plan.catalog?.type, "movie")
        XCTAssertTrue(result.plan.url.hasPrefix("https://owned.invalid/configured/catalog/movie/owned")); XCTAssertTrue(result.metas.isEmpty)
    }
    func testTheActualNativeAnonymousTraktClientReadsAPublicListWithoutLoadingAnAccountSession() async throws {
        let value = try await HTTPClient().traktList(id: "1248149", page: 1)
        guard case .array(let rows) = value else { XCTFail("Trakt must return its public list array"); return }
        XCTAssertFalse(rows.isEmpty); XCTAssertLessThanOrEqual(rows.count, 20)
        XCTAssertTrue(rows.contains { CustomSourceCatalog.traktMedia($0) != nil })
    }
}


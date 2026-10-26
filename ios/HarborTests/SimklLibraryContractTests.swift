import XCTest
@testable import Harbor

final class SimklLibraryContractTests: XCTestCase {
    private func reference() throws -> JSONValue {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "simkl-library-reference", withExtension: "json", subdirectory: "Fixtures"))
        return try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: url))
    }
    func testStatusOrderAndEveryListAndRatingPayloadMatch28ExecutedDesktopRequests() throws {
        let reference = try reference()
        XCTAssertEqual(reference["actual_original_typescript_executed"], .bool(true)); XCTAssertEqual(reference["provider_network_requests"].integer, 0)
        XCTAssertEqual(SimklListStatus.options(for: .movie).map(\.rawValue), reference["movie_order"].array.compactMap(\.string))
        XCTAssertEqual(SimklListStatus.options(for: .show).map(\.rawValue), reference["show_order"].array.compactMap(\.string))
        XCTAssertEqual(reference["cases"].array.count, 28)
        let ids = SimklIdentifiers(.object(["simkl": .integer(123), "imdb": .string("tt0123456"), "tmdb": .integer(456), "mal": .integer(789)]))
        for item in reference["cases"].array {
            let kind = try XCTUnwrap(SimklMediaKind(rawValue: try XCTUnwrap(item["kind"].string)))
            let target = SimklTarget(kind: kind, ids: ids), endpoint: SimklLibraryEndpoint
            switch item["action"].string {
            case "status": endpoint = .status(target, try XCTUnwrap(SimklListStatus(rawValue: try XCTUnwrap(item["value"].string))))
            case "remove": endpoint = .remove(target)
            default: endpoint = .rating(target, item["value"].integer)
            }
            let request = try SimklEndpoint.library(endpoint).request(token: "owned-library-token")
            XCTAssertEqual(request.url?.host, "api.simkl.com"); XCTAssertEqual(request.url?.path, item["expected"]["path"].string)
            XCTAssertEqual(request.httpMethod, item["expected"]["method"].string)
            XCTAssertEqual(try JSONDecoder().decode(JSONValue.self, from: XCTUnwrap(request.httpBody)), item["expected"]["body"])
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer owned-library-token")
            XCTAssertFalse(request.url!.absoluteString.contains("owned-library-token"))
        }
        XCTAssertThrowsError(try SimklEndpoint.library(.ratings).request())
        XCTAssertThrowsError(try SimklLibraryEndpoint.rating(.init(kind: .movie, ids: ids), 11).body())
        XCTAssertThrowsError(try SimklLibraryEndpoint.status(.init(kind: .movie, ids: ids), .watching).body())
        XCTAssertNil(try SimklEndpoint.detail(.anime, 7).request(token: "owned-library-token").value(forHTTPHeaderField: "Authorization"))
    }
    func testProviderIdentityResolutionAnd20FranchiseTitlesMatchExecutedDesktop() async throws {
        let reference = try reference(); XCTAssertEqual(reference["targets"].array.count, 8); XCTAssertEqual(reference["normalization"].array.count, 20)
        for item in reference["normalization"].array { XCTAssertEqual(SimklCollection.normalize(try XCTUnwrap(item["input"].string)), item["expected"].string) }
        for item in reference["targets"].array {
            let media = Media(id: try XCTUnwrap(item["id"].string), type: try XCTUnwrap(item["type"].string), name: "Owned")
            let target = try await SimklTarget.resolve(media, mapping: { id in
                guard let identity = AnimePublicIdentity(id) else { throw HarborError(code: "owned-mapping") }
                return .object(["mappings": .object([identity.mappingKey: .string(identity.number), "mal_id": .integer(123)])])
            })
            XCTAssertEqual(target?.kind.rawValue, item["expected"]["kind"].string); XCTAssertEqual(target?.ids.json, item["expected"]["ids"])
        }
        XCTAssertNil(SimklTarget.direct(.init(id: "tmdb:tv:-1", type: "series", name: "Invalid")))
        let mismatched = try await SimklTarget.resolve(.init(id: "kitsu:999", type: "series", name: "Owned"), mapping: { _ in .object(["mappings": .object(["kitsu_id": .integer(100), "mal_id": .integer(123)])]) })
        XCTAssertNil(mismatched)
    }
    func testAnimeGroupingKeepsFilmFranchisesStatusesCountsCoverFallbacksAndSearchTogether() throws {
        func item(_ id: Int, _ kind: SimklMediaKind, _ name: String, _ year: Int, _ status: SimklListStatus) -> SimklListItem {
            .init(kind: kind, ids: .init(.object(["simkl": .integer(Int64(id)), "mal": .integer(Int64(id + 100))])), title: name, year: year, status: status, watchedEpisodes: [])
        }
        var first = item(1, .anime, "Owned Saga", 2010, .completed)
        first.poster = "https://simkl.in/posters/owned_m.jpg"
        var second = item(2, .anime, "Owned Saga Season 2", 2012, .watching)
        second.addedAt = "2023-01-02T00:00:00Z"
        let film = item(3, .movie, "Owned Film", 2013, .plantowatch)
        let snapshot = SimklLibrarySnapshot(items: [first.id: first, second.id: second, film.id: film])
        let titleGroups = SimklCollection.franchises(Array(snapshot.items.values)); XCTAssertEqual(titleGroups.count, 2)
        let relations = [second.id: Set([film.id])]
        let rows = SimklCollection.rows(snapshot, kind: .anime, status: .plantowatch, query: "owned saga", relations: relations)
        let row = try XCTUnwrap(rows.first); XCTAssertEqual(rows.count, 1); XCTAssertEqual(row.items.count, 3)
        XCTAssertEqual(row.media.id, second.media.id); XCTAssertEqual(row.media.poster, first.poster); XCTAssertEqual(row.media.releaseInfo, "2010-2013")
        XCTAssertTrue(SimklCollection.rows(snapshot, kind: .movie, status: .plantowatch).isEmpty)
        XCTAssertTrue(SimklCollection.rows(snapshot, kind: .anime, status: .plantowatch, query: "missing", relations: relations).isEmpty)
        let groups = SimklCollection.groups(rows, sort: .title); XCTAssertEqual(groups.first?.label, "A to Z"); XCTAssertEqual(groups.first?.rows.count, 1)
        XCTAssertEqual(SimklCollection.counts(snapshot, kind: .anime, relations: relations)[.plantowatch], 1)
        let local = SimklListItem(kind: .movie, ids: .init(.object(["imdb": .string("tt0123456")])), title: "Owned Local", status: .plantowatch, watchedEpisodes: [])
        var aliases = SimklLibrarySnapshot(items: [local.id: local])
        let response = try JSONDecoder().decode(JSONValue.self, from: Data(#"{"movies":[{"status":"completed","movie":{"title":"Owned Local","ids":{"imdb":"tt0123456","simkl":999}}}]}"#.utf8))
        aliases.merge(response, kind: .movie)
        XCTAssertEqual(aliases.items.count, 1); XCTAssertNil(aliases.items[local.id]); XCTAssertEqual(aliases.items["movie:999"]?.status, .completed)
        let franchise = try JSONDecoder().decode(JSONValue.self, from: Data(#"{"anime":[{"status":"completed","show":{"title":"Owned Saga","ids":{"simkl":10,"mal":100,"imdb":"tt0987654"}}},{"status":"watching","show":{"title":"Owned Saga Season 2","ids":{"simkl":11,"mal":101,"imdb":"tt0987654"}}}]}"#.utf8))
        var seasons = SimklLibrarySnapshot(); seasons.merge(franchise, kind: .anime)
        XCTAssertEqual(seasons.items.count, 2)
        let later = try XCTUnwrap(seasons.items["anime:11"]); XCTAssertEqual(seasons.item(for: later.target)?.status, .watching)
    }
}

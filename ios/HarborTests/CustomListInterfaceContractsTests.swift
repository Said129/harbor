import XCTest
@testable import Harbor

@MainActor final class CustomListInterfaceContractsTests: XCTestCase {
    private func fixture() throws -> JSONValue {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "custom-list-interface-reference", withExtension: "json", subdirectory: "Fixtures"))
        let value = try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: url))
        XCTAssertEqual(value["reference"].string, "0834340cec5531650bfe78cd628628702e636987")
        XCTAssertEqual(value["actual_original_typescript_executed"], .bool(true))
        XCTAssertEqual(value["provider_network_requests"].integer, 0)
        XCTAssertEqual(value["executed_module_hashes"].objectValue.count, 5)
        return value
    }
    func testExecutedDesktopSearchPreservesGroupingLimitsAnimeTitlesAndArtwork() throws {
        let rows = try fixture()["search_cases"].array; XCTAssertEqual(rows.count, 4)
        for row in rows {
            let configuration = MetadataConfiguration(tmdbKey: "owned-fixture-key", region: "US", language: try XCTUnwrap(row["configuration"]["language"].string),
                translateTitles: row["configuration"]["translateTitles"] == .bool(true))
            let results = CustomListSearchResults.map(row["response"], english: row["english"], configuration: configuration)
            let projected = results.map { media -> JSONValue in
                var fields: [String: JSONValue] = ["id": .string(media.id), "type": .string(media.type), "name": .string(media.name)]
                fields["poster"] = media.poster.map(JSONValue.string); fields["background"] = media.background.map(JSONValue.string)
                return .object(fields)
            }
            XCTAssertEqual(JSONValue.array(projected), row["expected"], configuration.language + " translate=" + String(configuration.translateTitles))
            XCTAssertEqual(results.count, 24); XCTAssertEqual(results.filter { $0.type == "movie" }.count, 12)
        }
    }
    func testExecutedDesktopMangaTitleMatchingPreservesUnicodeAndColorQualifierRules() throws {
        let rows = try fixture()["manga_cases"].array; XCTAssertEqual(rows.count, 14)
        for row in rows {
            let query = try XCTUnwrap(row["query"].string), candidate = try XCTUnwrap(row["candidate"].string)
            XCTAssertEqual(CustomListMangaTitle.key(query), row["query_key"].string, query)
            XCTAssertEqual(CustomListMangaTitle.key(candidate), row["candidate_key"].string, candidate)
            XCTAssertEqual(CustomListMangaTitle.matches(query, title: candidate, alternate: row["alternate"].string), row["expected"] == .bool(true), query + " / " + candidate)
        }
    }
    func testSavedNativeMediaRetainsAddonOriginAndEpisodesAndReopensWithoutOtherAccountData() throws {
        let raw: JSONValue = .object(["id": .string("owned-provider:show"), "type": .string("series"), "name": .string("Owned Show"),
            "addonOrigin": .object(["id": .string("owned-provider"), "name": .string("Owned Provider"), "base": .string("https://example.org/owned/manifest.json"), "ignored": .string("discard")]),
            "videos": .array([.object(["id": .string("owned-provider:show:1"), "title": .string("Episode one"), "season": .integer(1), "episode": .integer(1)])])])
        let media = try XCTUnwrap(Media.parse(raw, kind: "series"))
        var document = CustomListsDocument()
        document.apply(.create("Owned", "", id: "owned-list"), at: 1)
        document.apply(.add("owned-list", CustomListItem.input(media)), at: 2)
        let reopened = CustomListsDocument(try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(document.raw)))
        let item = try XCTUnwrap(reopened.sorted.first?.items.first)
        XCTAssertEqual(item.raw["addonOrigin"], CustomListItem.origin(raw["addonOrigin"]))
        XCTAssertEqual(item.media.addonOrigin, media.addonOrigin)
        XCTAssertEqual(item.media.videos?.first?.id, "owned-provider:show:1")
        XCTAssertEqual(item.media.videos?.first?.episode, 1)
        XCTAssertEqual(item.raw["videos"].array.first?["streams"], JSONValue.null)
        let independent = CustomListsDocument(); XCTAssertTrue(independent.sorted.isEmpty)
    }
}

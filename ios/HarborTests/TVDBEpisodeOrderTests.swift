import XCTest
@testable import Harbor

private actor EpisodeOrderTransport: TVDBTransport {
    let replies: [TVDBRequest: JSONValue]
    private var calls: [TVDBRequest] = []
    init(_ replies: [TVDBRequest: JSONValue]) { self.replies = replies }
    func get(_ request: TVDBRequest) async throws -> JSONValue {
        calls.append(request)
        guard let response = replies[request] else { throw HarborError(code: "http-404") }
        return response
    }
    func requests() -> [TVDBRequest] { calls }
}

final class TVDBEpisodeOrderTests: XCTestCase {
    private func json(_ text: String) throws -> JSONValue { try JSONDecoder().decode(JSONValue.self, from: Data(text.utf8)) }
    private func row(_ id: Int, _ season: Int, _ number: Int, absolute: Int? = nil, name: String = "", overview: String = "", aired: String = "") throws -> TVDBOrderEpisode {
        var value: [String: JSONValue] = ["id": .integer(Int64(id)), "seasonNumber": .integer(Int64(season)), "number": .integer(Int64(number)),
                                         "name": .string(name), "overview": .string(overview), "aired": .string(aired)]
        if let absolute { value["absoluteNumber"] = .integer(Int64(absolute)) }
        return try XCTUnwrap(TVDBOrderEpisode(.object(value)))
    }
    private func build(_ kind: TVDBEpisodeOrderKind, _ canonical: [TVDBOrderEpisode], _ alternative: [TVDBOrderEpisode],
                       series: JSONValue = .null, translated: [TVDBOrderEpisode] = [], english: [TVDBOrderEpisode] = []) throws -> TVDBEpisodeOrder {
        try XCTUnwrap(TVDBEpisodeOrder.build(seriesID: 42, kind: kind, canonical: canonical, alternative: alternative,
                                             series: series, translated: translated, english: english))
    }

    func testDesktopAdvertisedOrderPriorityAliasesAndRawAbsoluteChoice() throws {
        let series = try json(#"{"seasons":[{"type":{"type":"regional","name":"Regional"}},{"type":{"type":"official","name":"Broadcast"}},{"type":{"type":"absolute","name":"Joined"}},{"type":{"type":"dvd","name":"DVD"}},{"type":{"type":"official","name":"Duplicate"}},{"type":{"type":"unsupported","name":"Ignore"}}]}"#)
        let options = TVDBEpisodeOrderOption.advertised(in: series)
        XCTAssertEqual(options.map(\.kind), [.aired, .dvd, .absolute, .tvdbabsolute, .regional])
        XCTAssertEqual(options.first?.label, "Broadcast")
        XCTAssertEqual(TVDBEpisodeOrderKind(setting: "official"), .aired)
        XCTAssertEqual(TVDBEpisodeOrderKind.allCases.map(\.slug), ["default", "dvd", "default", "absolute", "alternate", "regional"])
        XCTAssertNil(TVDBEpisodeOrderKind(setting: "../auth"))
    }

    func testDVDAlternateAndRegionalKeepCanonicalCoordinatesAndFirstOrderedID() throws {
        let canonical = try [row(1, 1, 1), row(2, 1, 2), row(3, 2, 1)]
        let dvd = try [row(3, 1, 1), row(1, 1, 2), row(3, 9, 99), row(2, 2, 1)]
        for kind in [TVDBEpisodeOrderKind.dvd, .alternate, .regional] {
            let result = try build(kind, canonical, dvd)
            XCTAssertEqual(result.seasons.map(\.id), [1, 2])
            XCTAssertEqual(result.seasons[0].episodes.map(\.id), [3, 1])
            let first = try XCTUnwrap(result.seasons.first?.episodes.first)
            XCTAssertEqual(first.canonicalSeason, 2); XCTAssertEqual(first.canonicalEpisode, 1)
            XCTAssertEqual(first.season, 2); XCTAssertEqual(first.number, 1)
            XCTAssertEqual(first.alternativeSeason, 1); XCTAssertEqual(first.alternativeEpisode, 1)
        }
    }

    func testCleanAndRawAbsoluteAreDifferentOrdersAndSpecialsStayIntentional() throws {
        let canonical = try [row(99, 5, 23, absolute: 99), row(100, 5, 24, absolute: 100), row(14, 1, 14, absolute: 14), row(500, 0, 1)]
        let reversed = [canonical[1], canonical[3], canonical[0], canonical[2]]
        let clean = try build(.absolute, canonical, reversed)
        XCTAssertEqual(clean.seasons.count, 1); XCTAssertTrue(clean.seasons[0].joined)
        XCTAssertEqual(clean.seasons[0].episodes.map(\.id), [14, 99, 100])
        XCTAssertEqual(clean.absoluteByID[99], 99)
        let raw = try build(.tvdbabsolute, canonical, reversed)
        XCTAssertEqual(raw.seasons.count, 1)
        XCTAssertEqual(raw.seasons[0].episodes.map(\.id), [100, 500, 99, 14])
        XCTAssertEqual(raw.seasons[0].episodes[2].canonicalSeason, 5)
        XCTAssertEqual(raw.seasons[0].episodes[2].canonicalEpisode, 23)
    }

    func testCanonicalCollisionsUseUniqueAlternativeSlotsWithoutLosingCanonicalReference() throws {
        let canonical = try [row(1, 1, 1), row(2, 1, 1)]
        let unique = try build(.dvd, canonical, [row(1, 3, 1), row(2, 3, 2)])
        XCTAssertEqual(unique.seasons[0].episodes.map(\.season), [3, 3])
        XCTAssertEqual(unique.seasons[0].episodes.map(\.number), [1, 2])
        XCTAssertEqual(unique.seasons[0].episodes.map(\.canonicalSeason), [1, 1])
        XCTAssertEqual(unique.seasons[0].episodes.map(\.canonicalEpisode), [1, 1])
        let ambiguous = try build(.dvd, canonical, [row(1, 3, 1), row(2, 3, 1)])
        XCTAssertEqual(ambiguous.seasons[0].episodes.map(\.season), [1, 1])
        XCTAssertEqual(ambiguous.seasons[0].episodes.map(\.number), [1, 1])
    }

    func testRequestedEnglishAndOriginalTextFallBackPerField() throws {
        let original = try [row(1, 1, 1, name: "Original one", overview: "Original overview"), row(2, 1, 2, name: "Original two", overview: "Original two overview")]
        let translated = try [row(1, 1, 1, name: "Localizado"), row(2, 1, 2, overview: "Resumen")]
        let english = try [row(1, 1, 1, name: "English one", overview: "English overview")]
        let rows = try build(.aired, original, original, translated: translated, english: english).seasons[0].episodes
        XCTAssertEqual(rows[0].name, "Localizado"); XCTAssertEqual(rows[0].overview, "English overview")
        XCTAssertEqual(rows[0].nameEn, "English one")
        XCTAssertEqual(rows[1].name, "Original two"); XCTAssertEqual(rows[1].overview, "Resumen")
        XCTAssertNil(rows[1].nameEn)
    }

    func testSeasonNamesDatesSpecialsAndMetadataEdgeCases() throws {
        let series = try json(#"{"seasons":[{"number":1,"name":"  Arc One  ","type":{"type":"official"}},{"number":2,"name":"日本語","type":{"type":"official"}},{"number":1,"name":"DVD Arc","type":{"type":"dvd"}}]}"#)
        let rows = try [row(4, 0, 1), row(2, 2, 1, aired: "2026-10-18"), row(1, 1, 2, aired: "2025-04-01"), row(3, 1, 1, aired: "2025-01-01")]
        let result = try build(.aired, rows, rows, series: series)
        XCTAssertEqual(result.seasons.map(\.id), [1, 2, 0])
        XCTAssertEqual(result.seasons[0].name, "Arc One"); XCTAssertNil(result.seasons[1].name)
        XCTAssertEqual(result.seasons[0].from, "2025-01-01"); XCTAssertEqual(result.seasons[0].to, "2025-04-01")
        XCTAssertEqual(result.seasons[0].count, 2)
        XCTAssertEqual(TVDBEpisodeOrder.seasonNames(in: series, slug: "dvd")[1], "DVD Arc")
        let zero = try XCTUnwrap(TVDBOrderEpisode(json(#"{"id":7,"number":0,"absoluteNumber":0,"image":"banners/synthetic.jpg"}"#)))
        XCTAssertEqual(zero.season, 0); XCTAssertEqual(zero.number, 0); XCTAssertEqual(zero.absolute, 0)
        XCTAssertEqual(zero.image, "https://artworks.thetvdb.com/banners/synthetic.jpg")
        XCTAssertNil(TVDBOrderEpisode(try json(#"{"id":8,"number":1,"image":""}"#))?.image)
        XCTAssertNil(TVDBOrderEpisode(try json(#"{"id":8,"number":1,"image":"https://example.invalid/a.jpg"}"#))?.image)
        XCTAssertNil(TVDBEpisodeOrder.build(seriesID: 42, kind: .aired, canonical: [], alternative: [], series: .null))
    }

    func testEveryDesktopLanguageMappingAndDefault() {
        let cases = ["en-US": "eng", "es-ES": "spa", "FR-fr": "fra", "de": "deu", "it": "ita", "ja": "jpn", "ko": "kor", "ru": "rus", "pt-BR": "por", "zh-CN": "zho", "ar": "ara", "nl": "nld", "pl": "pol", "tr": "tur", "sv": "swe", "da": "dan", "fi": "fin", "no": "nor", "cs": "ces", "hu": "hun", "el": "ell", "he": "heb", "th": "tha", "vi": "vie", "id": "ind", "uk": "ukr", "ro": "ron", "hi": "hin"]
        for (input, output) in cases { XCTAssertEqual(TVDBEpisodeOrder.language(input), output, input) }
        XCTAssertEqual(TVDBEpisodeOrder.language(nil), "eng"); XCTAssertEqual(TVDBEpisodeOrder.language("unknown"), "eng")
    }

    func testServiceOmitsEmptyOrdersSharesDiscoveryPagesAndKeepsEnglishOnMissingTranslation() async throws {
        let metadata = try json(#"{"data":{"id":42,"seasons":[{"type":{"type":"official"}},{"type":{"type":"dvd"}},{"type":{"type":"absolute"}},{"type":{"type":"regional"}}]}}"#)
        let original = try json(#"{"data":{"episodes":[{"id":1,"seasonNumber":2,"number":1,"name":"Original"}]}}"#)
        let english = try json(#"{"data":{"episodes":[{"id":1,"seasonNumber":2,"number":1,"name":"English","overview":"Fallback"}]}}"#)
        let transport = EpisodeOrderTransport([.series(42): metadata,
            .episodes(series: 42, order: "default", language: nil, page: 0): original,
            .episodes(series: 42, order: "dvd", language: nil, page: 0): try json(#"{"data":{"episodes":[]}}"#),
            .episodes(series: 42, order: "absolute", language: nil, page: 0): original,
            .episodes(series: 42, order: "default", language: "eng", page: 0): english])
        let service = TVDBService(transport: transport)
        let options = try await service.orderOptions(series: 42)
        XCTAssertEqual(options.map(\.kind), [.aired, .absolute, .tvdbabsolute])
        let result = try await service.episodeOrder(series: 42, kind: .absolute, language: "es-ES")
        XCTAssertEqual(result?.seasons[0].episodes[0].name, "English")
        XCTAssertEqual(result?.seasons[0].episodes[0].overview, "Fallback")
        let requests = await transport.requests()
        XCTAssertEqual(requests.filter { $0 == .series(42) }.count, 1)
        XCTAssertEqual(requests.filter { $0 == .episodes(series: 42, order: "default", language: nil, page: 0) }.count, 1)
        XCTAssertTrue(requests.contains(.episodes(series: 42, order: "default", language: "spa", page: 0)))
    }

    func testOrderPaginationKeepsRawDuplicatesForTheBuilderAndRejectsRepeatedFullPages() async throws {
        let a = try json(#"{"id":1,"seasonNumber":1,"number":1}"#), b = try json(#"{"id":2,"seasonNumber":1,"number":2}"#)
        let page: JSONValue = .object(["data": .object(["episodes": .array(Array(repeating: a, count: 500))])])
        let tail: JSONValue = .object(["data": .object(["episodes": .array([a, b])])])
        let first = TVDBRequest.episodes(series: 42, order: "dvd", language: nil, page: 0)
        let second = TVDBRequest.episodes(series: 42, order: "dvd", language: nil, page: 1)
        let service = TVDBService(transport: EpisodeOrderTransport([first: page, second: tail]))
        let rows = try await service.orderRows(series: 42, slug: "dvd")
        XCTAssertEqual(rows.count, 502)
        let result = try build(.dvd, rows, rows)
        XCTAssertEqual(result.seasons[0].episodes.map(\.id), [1, 2])
        let repeated = TVDBService(transport: EpisodeOrderTransport([first: page, second: page]))
        do { _ = try await repeated.orderRows(series: 42, slug: "dvd"); XCTFail("Repeating full pages must not certify a complete order") }
        catch { XCTAssertEqual((error as? HarborError)?.code, "tvdb-response") }
    }
}

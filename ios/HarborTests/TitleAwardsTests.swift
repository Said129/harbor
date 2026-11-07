import XCTest
@testable import Harbor

/// Desktop's Wikidata title awards (`src/lib/providers/wikidata.ts`): SPARQL text, row merging, collapsing and grouping.
final class TitleAwardsTests: XCTestCase {
    private static let winsJSON = """
    {"head":{"vars":["award"]},"results":{"bindings":[
    {"awardLabel":{"type":"literal","value":"Academy Award for Best Picture"},"categoryLabel":{"type":"literal","value":"Best Picture"},"recipientLabel":{"type":"literal","value":"Jane Producer"},"date":{"type":"literal","value":"2024-03-10T00:00:00Z"},"workLabel":{"type":"literal","value":"Example Film"},"workImdb":{"type":"literal","value":"tt1234567"}},
    {"awardLabel":{"value":"Academy Award for Best Picture"},"categoryLabel":{"value":"Best Picture"},"recipientLabel":{"value":"Second Producer"},"date":{"value":"2024-03-10T00:00:00Z"},"workLabel":{"value":"Example Film"},"workImdb":{"value":"tt1234567"}},
    {"awardLabel":{"value":"Academy Awards"},"date":{"value":"2024-03-10T00:00:00Z"}},
    {"awardLabel":{"value":"Golden Globe Award for Best Motion Picture - Drama"},"date":{"value":"2024-01-07T00:00:00Z"},"workLabel":{"value":"http://www.wikidata.org/entity/Q99"}},
    {"awardLabel":{"value":"Emmy Award Ceremony Special"},"date":{"value":"2023-09-18T00:00:00Z"}}
    ]}}
    """

    private static let nominationsJSON = """
    {"results":{"bindings":[
    {"awardLabel":{"value":"Academy Award for Best Actor"},"categoryLabel":{"value":"Best Actor"},"recipientLabel":{"value":"Lead Star"},"date":{"value":"2024-03-10T00:00:00Z"},"workLabel":{"value":"Example Film"},"workImdb":{"value":"tt1234567"}}
    ]}}
    """

    private func award(_ ceremony: TitleAwardCeremony, _ name: String, category: String?, year: Int?, won: Bool,
                       recipients: [String] = [], work: String? = nil, imdb: String? = nil) -> TitleAward {
        TitleAward(ceremony: ceremony, awardName: name, category: category, recipients: recipients, year: year, won: won, workTitle: work, workIMDb: imdb)
    }

    // MARK: - Request

    func testQueryUsesTheDesktopIMDbFilterAndPropertyPerKind() throws {
        let wins = try XCTUnwrap(TitleAwardParser.query(imdbID: "tt1234567", nominations: false))
        XCTAssertTrue(wins.contains("?film wdt:P345 \"tt1234567\"."))
        XCTAssertTrue(wins.contains("?film p:P166 ?statement."))
        XCTAssertFalse(wins.contains("P1411"))
        XCTAssertFalse(wins.contains("IMDB_ID"))
        XCTAssertTrue(wins.hasSuffix("LIMIT 400"))

        let nominations = try XCTUnwrap(TitleAwardParser.query(imdbID: "tt1234567", nominations: true))
        XCTAssertTrue(nominations.contains("?film p:P1411 ?statement."))
        XCTAssertFalse(nominations.contains("P166 ?statement"))
    }

    func testOnlyWellFormedTitleIDsReachTheQuery() {
        XCTAssertNil(TitleAwardParser.query(imdbID: "nm0000001", nominations: false))
        XCTAssertNil(TitleAwardParser.query(imdbID: "tt1\" } SERVICE wikibase:x", nominations: false))
        XCTAssertNil(TitleAwardParser.query(imdbID: "tt", nominations: true))
        XCTAssertTrue(TitleAwardParser.isTitleID("tt0111161"))
    }

    func testRequestURLEncodesTheQueryAndAsksForJSON() throws {
        let query = try XCTUnwrap(TitleAwardParser.query(imdbID: "tt1234567", nominations: false))
        let url = try XCTUnwrap(TitleAwardParser.requestURL(query: query))
        XCTAssertEqual(url.host, "query.wikidata.org")
        XCTAssertEqual(url.path, "/sparql")
        let text = url.absoluteString
        XCTAssertTrue(text.hasPrefix("https://query.wikidata.org/sparql?query=SELECT%20DISTINCT"))
        XCTAssertTrue(text.hasSuffix("&format=json"))
        XCTAssertFalse(text.contains(" "))
        XCTAssertFalse(text.contains("\""))
    }

    // MARK: - Rows

    func testWinRowsMergeRecipientsAndPrettifyCategories() throws {
        let rows = try XCTUnwrap(TitleAwardParser.rows(from: Data(Self.winsJSON.utf8), won: true))
        XCTAssertEqual(rows.count, 3, "The generic 'Academy Awards' body row is dropped")

        let picture = try XCTUnwrap(rows.first { $0.awardName == "Academy Award for Best Picture" })
        XCTAssertEqual(picture.ceremony, .oscar)
        XCTAssertEqual(picture.category, "Best Picture")
        XCTAssertEqual(picture.recipients, ["Jane Producer", "Second Producer"])
        XCTAssertEqual(picture.year, 2024)
        XCTAssertTrue(picture.won)
        XCTAssertEqual(picture.workTitle, "Example Film")
        XCTAssertEqual(picture.workIMDb, "tt1234567")
    }

    func testCategoryFallsBackToTheAwardNameAndWikidataURLsAreNotTitles() throws {
        let rows = try XCTUnwrap(TitleAwardParser.rows(from: Data(Self.winsJSON.utf8), won: true))
        let globe = try XCTUnwrap(rows.first { $0.ceremony == .goldenGlobe })
        XCTAssertEqual(globe.category, "Best Motion Picture - Drama", "Prefix 'Golden Globe Award for ' is removed")
        XCTAssertNil(globe.workTitle, "A workLabel that is a Wikidata URL is not a title")
        XCTAssertNil(globe.workIMDb)

        let emmy = try XCTUnwrap(rows.first { $0.ceremony == .emmy })
        XCTAssertEqual(emmy.category, "Emmy Award Ceremony Special", "No prefix matched, so the award name is the category")
        XCTAssertEqual(emmy.year, 2023)
    }

    func testNominationRowsAreNotWins() throws {
        let rows = try XCTUnwrap(TitleAwardParser.rows(from: Data(Self.nominationsJSON.utf8), won: false))
        XCTAssertEqual(rows.count, 1)
        XCTAssertFalse(rows[0].won)
        XCTAssertEqual(rows[0].category, "Best Actor")
    }

    func testUndecodableBodyIsAFailedRequest() {
        XCTAssertNil(TitleAwardParser.rows(from: Data("not json".utf8), won: true))
    }

    func testCeremonyClassificationMatchesDesktopOrder() {
        XCTAssertEqual(TitleAwardParser.ceremony(for: "Primetime Emmy Award for Outstanding Drama Series"), .emmy)
        XCTAssertEqual(TitleAwardParser.ceremony(for: "BAFTA TV Award for Best Drama Series"), .baftaTV)
        XCTAssertEqual(TitleAwardParser.ceremony(for: "British Academy Film Award for Best Film"), .bafta)
        XCTAssertEqual(TitleAwardParser.ceremony(for: "Critics' Choice Movie Award for Best Picture"), .criticsChoice)
        XCTAssertEqual(TitleAwardParser.ceremony(for: "Golden Bear"), .berlin)
        XCTAssertEqual(TitleAwardParser.ceremony(for: "Saturn Award for Best Horror Film"), .saturn)
        XCTAssertEqual(TitleAwardParser.ceremony(for: "Some Local Prize"), .other)
    }

    // MARK: - Dropping and collapsing

    func testGenericRowIsDroppedWhenTheSameSlotHasAWork() {
        let withWork = award(.goldenGlobe, "Golden Globe Award for Best Actor", category: "Best Actor", year: 2020, won: true, recipients: ["A"], work: "Film", imdb: "tt0000001")
        let generic = award(.goldenGlobe, "Golden Globe Award for Best Actor", category: "Best Actor", year: 2020, won: true, recipients: ["B"])
        let kept = TitleAwardParser.assemble(wins: [withWork, generic], nominations: [], isSeries: false)
        XCTAssertEqual(kept.count, 1)
        XCTAssertEqual(kept.first?.workIMDb, "tt0000001")
    }

    func testFilmRowsOfOneCategoryCollapseToTheWinAndTheCeremonyLatestYear() {
        let won = award(.oscar, "Academy Award for Best Picture", category: "Best Picture", year: 2024, won: true, recipients: ["Jane"], work: "Example", imdb: "tt1234567")
        let nominated = award(.oscar, "Academy Award for Best Picture", category: "Best Picture", year: 2024, won: false, recipients: ["Alex", "Sam"], work: "Other", imdb: "tt7654321")
        let director = award(.oscar, "Academy Award for Best Director", category: "Best Director", year: 2025, won: true, recipients: ["Jane"], work: "Example", imdb: "tt1234567")
        let kept = TitleAwardParser.assemble(wins: [won, director], nominations: [nominated], isSeries: false)
        XCTAssertEqual(kept.count, 2)
        let picture = kept.first { $0.category == "Best Picture" }
        XCTAssertEqual(picture?.won, true)
        XCTAssertEqual(picture?.recipients, ["Jane"])
        XCTAssertEqual(picture?.workIMDb, "tt1234567")
        XCTAssertEqual(picture?.year, 2025, "Every film row of the ceremony takes its latest year")
    }

    func testSeriesRowsKeepTheirOwnYears() {
        let first = award(.emmy, "Primetime Emmy Award for Outstanding Drama Series", category: "Outstanding Drama Series", year: 2023, won: true)
        let second = award(.emmy, "Primetime Emmy Award for Outstanding Drama Series", category: "Outstanding Drama Series", year: 2024, won: true)
        let kept = TitleAwardParser.assemble(wins: [first, second], nominations: [], isSeries: true)
        XCTAssertEqual(kept.map { $0.year }, [2023, 2024])
    }

    // MARK: - Grouping

    func testGroupsFollowTheDetailPageOrderAndSortWinsNewestFirst() {
        let entries = [
            award(.goldenGlobe, "Golden Globe Award for Best Drama", category: "Best Drama", year: 2018, won: true),
            award(.emmy, "Primetime Emmy Award for Outstanding Drama", category: "Outstanding Drama", year: 2022, won: false),
            award(.oscar, "Academy Award for Best Picture", category: "Best Picture", year: 2020, won: true),
            award(.oscar, "Academy Award for Best Director", category: "Best Director", year: 2024, won: true),
            award(.oscar, "Academy Award for Best Actor", category: "Best Actor", year: 2019, won: false),
            award(.oscar, "Academy Award", category: nil, year: 2021, won: true),
            award(.other, "Local Prize", category: "Local", year: 2010, won: true),
        ]
        let groups = TitleAwardParser.groups(entries)
        XCTAssertEqual(groups.map { $0.ceremony }, [.oscar, .emmy, .goldenGlobe])

        let oscar = groups[0]
        XCTAssertEqual(oscar.wins.map { $0.category }, ["Best Director", "Best Picture"], "Won rows, newest first")
        XCTAssertEqual(oscar.nominations.map { $0.category }, ["Best Actor"])
        XCTAssertEqual(oscar.winCount, 3, "Totals include the row without a category")
        XCTAssertEqual(oscar.nominationCount, 1)
        XCTAssertEqual(oscar.years, [2019, 2020, 2021, 2024])
        XCTAssertEqual(oscar.yearSpan, "2019–2024")
        let expectedCounts = "3 " + DesktopInterfaceText.value("Wins") + " · 1 " + DesktopInterfaceText.value("Nomination")
        XCTAssertEqual(oscar.countLine, expectedCounts)
    }

    func testSingleYearAndNoCategoryRowsStillGroup() {
        let entries = [award(.bifa, "British Independent Film Award", category: nil, year: 2015, won: false)]
        let groups = TitleAwardParser.groups(entries)
        XCTAssertEqual(groups.count, 1)
        XCTAssertTrue(groups[0].wins.isEmpty)
        XCTAssertTrue(groups[0].nominations.isEmpty)
        XCTAssertEqual(groups[0].nominationCount, 1)
        XCTAssertEqual(groups[0].yearSpan, "2015")
    }

    // MARK: - Network

    func testClientRunsBothQueriesAndMergesTheirRows() async {
        let client = TitleAwardsClient(transport: StubWikidataTransport { request in
            let url = request.url?.absoluteString ?? ""
            let body = url.contains("P1411") ? TitleAwardsTests.nominationsJSON : TitleAwardsTests.winsJSON
            return TitleAwardsReply(status: 200, data: Data(body.utf8))
        })
        let load = await client.load(imdbID: "tt1234567", isSeries: false)
        XCTAssertTrue(load.complete)
        XCTAssertTrue(load.entries.contains { !$0.won && $0.category == "Best Actor" })
        XCTAssertTrue(load.entries.contains { $0.won && $0.category == "Best Picture" })
    }

    func testFailedNominationRequestKeepsWinsButMarksTheLoadIncomplete() async {
        let client = TitleAwardsClient(transport: StubWikidataTransport { request in
            let url = request.url?.absoluteString ?? ""
            if url.contains("P1411") { return TitleAwardsReply(status: 500, data: Data()) }
            return TitleAwardsReply(status: 200, data: Data(TitleAwardsTests.winsJSON.utf8))
        })
        let load = await client.load(imdbID: "tt1234567", isSeries: false)
        XCTAssertFalse(load.complete)
        XCTAssertEqual(load.entries.count, 3)
        XCTAssertTrue(load.entries.allSatisfy { $0.won })
    }

    func testInvalidIDMakesNoRequest() async {
        let client = TitleAwardsClient(transport: StubWikidataTransport { _ in
            TitleAwardsReply(status: 200, data: Data(TitleAwardsTests.winsJSON.utf8))
        })
        let load = await client.load(imdbID: "nm0000001", isSeries: false)
        XCTAssertEqual(load, TitleAwardsLoad(entries: [], complete: false))
    }
}

/// Answers each Wikidata request from a closure, without touching the network.
private struct StubWikidataTransport: TitleAwardsTransport {
    let respond: @Sendable (URLRequest) -> TitleAwardsReply

    func send(_ request: URLRequest) async throws -> TitleAwardsReply {
        respond(request)
    }
}

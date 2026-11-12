import XCTest
@testable import Harbor

/// F11 S342: the OpenSubtitles key in the auto-sync (Desktop's tier-0 exact-file lookup).
final class F11OpenSubtitlesHashSwapTests: XCTestCase {
    private typealias Rules = OpenSubtitlesHashSwapRules

    private let answer = """
    {"data":[
     {"id":"11","type":"subtitle","attributes":{"language":"en","download_count":10,"from_trusted":true,"hearing_impaired":false,"ai_translated":false,"machine_translated":false,"moviehash_match":true,"release":"Movie.2020","fps":23.976,"feature_details":{"imdb_id":133093},"files":[{"file_id":901,"file_name":"a.srt"}]}},
     {"id":"12","attributes":{"language":"en","download_count":900,"from_trusted":false,"moviehash_match":true,"files":[{"file_id":902,"file_name":"b.srt"}]}},
     {"id":"13","attributes":{"language":"fr","download_count":5000,"moviehash_match":true,"files":[{"file_id":903,"file_name":"c.srt"}]}},
     {"id":"14","attributes":{"language":"en","download_count":7,"moviehash_match":false,"files":[{"file_id":904,"file_name":"d.srt"}]}},
     {"id":"15","attributes":{"language":"en","moviehash_match":true,"files":[]}}
    ]}
    """

    private func entries() -> [OpenSubtitlesHashSwapRules.Entry] {
        Rules.parse(Data(answer.utf8))
    }

    func testRowsWithoutAFileAreDroppedAndTheIDsArePadded() {
        let parsed = entries()
        XCTAssertEqual(parsed.map { $0.id }, ["11", "12", "13", "14"])
        XCTAssertEqual(parsed[0].imdbID, "tt0133093")
        XCTAssertEqual(parsed[0].fileID, 901)
        XCTAssertTrue(parsed[0].fromTrusted)
        XCTAssertFalse(parsed[3].hashMatch)
        XCTAssertEqual(Rules.parse(Data("not json".utf8)), [])
    }

    func testScoreFollowsDesktop() {
        let parsed = entries()
        XCTAssertEqual(Rules.score(parsed[0]), 100_010)
        XCTAssertEqual(Rules.score(parsed[1]), 900)
    }

    func testGateKeepsHashMatchesInTheWantedLanguageBestFirst() {
        let gated = Rules.gate(entries(), languages: ["en"], imdbID: nil)
        XCTAssertEqual(gated.candidates.map { $0.id }, ["11", "12"])
        XCTAssertEqual(gated.exact?.id, "11")
        let anyLanguage = Rules.gate(entries(), languages: [], imdbID: nil)
        XCTAssertEqual(anyLanguage.candidates.map { $0.id }, ["11", "13", "12"])
    }

    func testGateDropsAnotherTitleButKeepsRowsWithoutOne() {
        let gated = Rules.gate(entries(), languages: ["en"], imdbID: "tt0000001")
        XCTAssertEqual(gated.candidates.map { $0.id }, ["12"])
        XCTAssertEqual(gated.exact?.id, "12")
    }

    func testOnlyATrustedNonMachineMatchIsExact() {
        let few = "{\"data\":[{\"id\":\"1\",\"attributes\":{\"language\":\"en\",\"download_count\":10,\"moviehash_match\":true,\"files\":[{\"file_id\":5}]}}]}"
        let fewGate = Rules.gate(Rules.parse(Data(few.utf8)), languages: ["en"], imdbID: nil)
        XCTAssertNil(fewGate.exact)
        XCTAssertEqual(fewGate.candidates.count, 1)
        let machine = "{\"data\":[{\"id\":\"2\",\"attributes\":{\"language\":\"en\",\"download_count\":100000,\"machine_translated\":true,\"moviehash_match\":true,\"files\":[{\"file_id\":6}]}}]}"
        XCTAssertNil(Rules.gate(Rules.parse(Data(machine.utf8)), languages: ["en"], imdbID: nil).exact)
        let enough = "{\"data\":[{\"id\":\"3\",\"attributes\":{\"language\":\"en\",\"download_count\":50,\"moviehash_match\":true,\"files\":[{\"file_id\":7}]}}]}"
        XCTAssertEqual(Rules.gate(Rules.parse(Data(enough.utf8)), languages: ["en"], imdbID: nil).exact?.id, "3")
    }

    func testMovieHashShape() {
        XCTAssertTrue(Rules.isMovieHash("8e245d9679d31e12"))
        XCTAssertTrue(Rules.isMovieHash("8E245D9679D31E12"))
        XCTAssertFalse(Rules.isMovieHash("8e245d9679d31e1"))
        XCTAssertFalse(Rules.isMovieHash("8e245d9679d31e1g"))
    }

    func testSearchAddressCarriesTheHashAndTheLanguages() throws {
        let url = try XCTUnwrap(Rules.searchURL(hash: "8e245d9679d31e12", languages: ["en", "es"]))
        XCTAssertEqual(url.host, "api.opensubtitles.com")
        XCTAssertEqual(url.scheme, "https")
        XCTAssertEqual(url.path, "/api/v1/subtitles")
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertEqual(items.first { $0.name == "moviehash" }?.value, "8e245d9679d31e12")
        XCTAssertEqual(items.first { $0.name == "languages" }?.value, "en,es")
        XCTAssertNil(Rules.searchURL(hash: "nope", languages: ["en"]))
    }

    func testTheKeyIsSentToTheApiOnlyAndNeverWithTheFileRequest() throws {
        XCTAssertEqual(Rules.searchHeaders(key: "k")["Api-Key"], "k")
        let download = try XCTUnwrap(Rules.downloadRequest(fileID: 901, key: "test-key"))
        XCTAssertEqual(download.httpMethod, "POST")
        XCTAssertEqual(download.url?.host, "api.opensubtitles.com")
        XCTAssertEqual(download.value(forHTTPHeaderField: "Api-Key"), "test-key")
        XCTAssertEqual(String(data: download.httpBody ?? Data(), encoding: .utf8), "{\"file_id\":901}")
        XCTAssertNil(Rules.downloadRequest(fileID: 0, key: "k"))
        XCTAssertNil(Rules.downloadRequest(fileID: 5, key: ""))
        XCTAssertNil(Rules.downloadRequest(fileID: 5, key: "a\nb"))
        let link = try XCTUnwrap(URL(string: "https://dl.opensubtitles.com/file/1.srt"))
        let file = Rules.fileRequest(link)
        XCTAssertNil(file.value(forHTTPHeaderField: "Api-Key"))
        XCTAssertNil(file.value(forHTTPHeaderField: "Authorization"))
        XCTAssertEqual(file.url, link)
    }

    func testOnlyAnHttpsLinkWithoutCredentialsIsFollowed() {
        XCTAssertEqual(Rules.downloadLink(Data("{\"link\":\"https://dl.opensubtitles.com/x/1.srt\",\"remaining\":3}".utf8))?.host, "dl.opensubtitles.com")
        XCTAssertNil(Rules.downloadLink(Data("{\"link\":\"http://dl.opensubtitles.com/x/1.srt\"}".utf8)))
        XCTAssertNil(Rules.downloadLink(Data("{\"link\":\"https://user:pw@dl.opensubtitles.com/x/1.srt\"}".utf8)))
        XCTAssertNil(Rules.downloadLink(Data("{}".utf8)))
        XCTAssertNil(Rules.downloadLink(Data("oops".utf8)))
    }

    func testTheTrackLanguageComesFirstAndAloneWhenKnown() {
        XCTAssertEqual(Rules.languages(trackLanguage: "es", preferred: ["en", "fr"]), ["es"])
        XCTAssertEqual(Rules.languages(trackLanguage: "", preferred: ["en", "en", "fr"]), ["en", "fr"])
        XCTAssertEqual(Rules.languages(trackLanguage: "", preferred: []), [])
    }

    func testASwapThatChangesNothingIsNotOffered() {
        let current = (0..<20).map { Double($0) * 5 + 1 }
        XCTAssertTrue(Rules.timelinesMatch(current, current.map { $0 + 0.1 }))
        XCTAssertFalse(Rules.timelinesMatch(current, current.map { $0 + 2 }))
        XCTAssertFalse(Rules.timelinesMatch(current, Array(current.dropLast())))
        XCTAssertFalse(Rules.timelinesMatch([], []))
        var mostly = current
        for index in 0..<3 { mostly[index] += 30 }
        XCTAssertFalse(Rules.timelinesMatch(current, mostly))
    }
}

import XCTest
@testable import Harbor

final class VODPlaylistTests: XCTestCase {
    func testMixedPlaylistClassificationSeriesGroupingAndCredentialEncoding() throws {
        // Original test-only input covers conflicting provider hints and paths.
        let playlist = """
        #EXTM3U
        #EXTINF:-1 group-title="Movies",Noticias
        https://example.invalid/live/1.ts
        #EXTINF:-1 tvg-type="movie",US - Example Film (2020) 1080p
        https://example.invalid/movie/2.m3u8
        #EXTINF:-1 group-title="Series",AR-MA - المسلسل S01E02
        https://example.invalid/series/3.mkv
        #EXTINF:-1 group-title="Series",AR-MA - المسلسل S01E10
        https://example.invalid/series/4.mkv
        #EXTINF:-1 tvg-type="series",السلسلة S01E01
        https://example.invalid/series/5.mkv
        #EXTINF:-1,Film S01E02
        https://example.invalid/6.mp4
        """
        let channels = try M3UParser.parse(Data(playlist.utf8), source: UUID().uuidString)
        XCTAssertEqual(channels.count, 6)
        XCTAssertEqual(VODTitles.kind(channels[0]), "live")
        XCTAssertEqual(VODTitles.kind(channels[5]), "movie")
        let catalog = try VODLibrary.build(channels)
        XCTAssertEqual(catalog.movies.count, 2)
        XCTAssertEqual(catalog.movies.first(where: { $0.year == 2020 })?.title, "Example Film")
        XCTAssertEqual(catalog.series.count, 2, "Non-Latin show titles must not collapse into one empty normalized key")
        let show = try XCTUnwrap(catalog.series.first { $0.title == "المسلسل" })
        XCTAssertEqual(show.episodes.map(\.episode), [2, 10])

        let account = try XtreamAccount.make(server: "https://example.invalid:8443/server", username: "test+user", password: "pass/word?&=#")
        let api = try account.api("get_series_info", extra: ["series_id": "42"])
        let components = try XCTUnwrap(URLComponents(url: api, resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.queryItems?.first { $0.name == "password" }?.value, account.password)
        let stream = try account.stream(kind: "series", id: "42", ext: "mkv")
        XCTAssertTrue(stream.contains("pass%2Fword%3F%26%3D%23"))
        XCTAssertNil(URLComponents(string: stream)?.query)
        XCTAssertThrowsError(try account.stream(kind: "movie", id: "../42", ext: "mp4"))
        let decoded = try XCTUnwrap(XtreamAccount.fromPlaylist(try account.api(nil).absoluteString))
        XCTAssertEqual(decoded, account)
    }
}

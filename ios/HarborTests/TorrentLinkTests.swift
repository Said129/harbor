import XCTest
@testable import Harbor

/// Desktop's magnet and direct-link recognition (`lib/torrent/magnet.ts`) for Search.
final class TorrentLinkTests: XCTestCase {
    private let hex = "aabbccddeeff00112233445566778899aabbccdd"
    private let base32 = "VK54ZXPO74ABCIRTIRKWM54ITGVLXTG5"

    func testHashesAndMagnetsAreRecognised() {
        XCTAssertTrue(TorrentLink.isMagnetInput(hex)); XCTAssertTrue(TorrentLink.isMagnetInput("  " + hex.uppercased() + " "))
        XCTAssertTrue(TorrentLink.isMagnetInput(base32))
        XCTAssertTrue(TorrentLink.isMagnetInput("MAGNET:?xt=urn:btih:" + hex))
        XCTAssertFalse(TorrentLink.isMagnetInput("Breaking Bad")); XCTAssertFalse(TorrentLink.isMagnetInput(String(hex.dropLast())))
        XCTAssertFalse(TorrentLink.isMagnetInput("https://example.org/a.mkv"))
    }

    func testBase32AndHexInfoHashesAgree() {
        XCTAssertEqual(TorrentLink.base32ToHex(base32), hex)
        XCTAssertEqual(TorrentLink.parseMagnet(base32)?.infoHash, hex)
        XCTAssertEqual(TorrentLink.parseMagnet(hex.uppercased())?.infoHash, hex, "Hashes are stored in lowercase")
        XCTAssertNil(TorrentLink.base32ToHex("AAAA")); XCTAssertNil(TorrentLink.base32ToHex(String(repeating: "1", count: 32)))
    }

    func testMagnetFieldsAreDecodedLikeURLSearchParams() throws {
        let link = "magnet:?xt=urn:btih:\(hex.uppercased())&dn=Owned.Show+S01E02%20%281080p%29&tr=udp%3A%2F%2Ftracker.example.org%3A1337&tr=&tr=http%3A%2F%2Fb.example.org%2Fannounce"
        let parsed = try XCTUnwrap(TorrentLink.parseMagnet(link))
        XCTAssertEqual(parsed.infoHash, hex)
        XCTAssertEqual(parsed.name, "Owned.Show S01E02 (1080p)", "+ is a space and escapes are decoded")
        XCTAssertEqual(parsed.trackers, ["udp://tracker.example.org:1337", "http://b.example.org/announce"], "Empty trackers are dropped")
        XCTAssertEqual(TorrentLink.parseMagnet("magnet:?xt=urn:btih:\(base32)&xt=urn:btih:\(hex)")?.infoHash, hex, "A base32 hash converts")
        XCTAssertNil(TorrentLink.parseMagnet("magnet:?dn=No+hash")); XCTAssertNil(TorrentLink.parseMagnet("magnet:?xt=urn:btih:short"))
        XCTAssertNil(TorrentLink.parseMagnet("magnet:"), "Without a query there is no hash")
        XCTAssertNil(TorrentLink.parseMagnet("not a link"))
        XCTAssertNil(TorrentLink.parseMagnet("magnet:?xt=urn:btih:\(hex)&dn=")?.name, "An empty name is no name")
    }

    func testDirectVideoLinksNeedAHttpPathWithAVideoExtension() {
        for good in ["https://cdn.example.org/a/Show.S01E01.MKV", "http://example.org/v.mp4?token=1", "https://example.org/live/index.m3u8#t=1", "https://example.org/x.m2ts"] {
            XCTAssertTrue(TorrentLink.isDirectVideoURL(good), good)
        }
        for bad in ["https://example.org/watch?v=a.mp4", "https://example.org/page.html", "ftp://example.org/a.mkv", "file:///private/a.mkv", "a.mkv", "https:///a.mkv", "Breaking Bad"] {
            XCTAssertFalse(TorrentLink.isDirectVideoURL(bad), bad)
        }
        XCTAssertEqual(TorrentLink.fileTitle("https://cdn.example.org/a/My%20Film%20%282020%29.mkv", fallback: "Direct stream"), "My Film (2020).mkv")
        XCTAssertEqual(TorrentLink.fileTitle("https://cdn.example.org/", fallback: "Direct stream"), "Direct stream")
    }

    func testSearchInputPrefersMagnetsThenLinksThenTitles() {
        XCTAssertEqual(SearchInput.classify("  " + hex + "\n"), .magnet(hex))
        XCTAssertEqual(SearchInput.classify("https://cdn.example.org/a.mp4"), .directURL("https://cdn.example.org/a.mp4"))
        XCTAssertEqual(SearchInput.classify("Breaking Bad"), .query("Breaking Bad"))
        XCTAssertEqual(SearchInput.classify(""), .query(""))
    }
}

/// Desktop's "Watch on" providers (`tmdb-watch.ts`).
final class WatchProvidersTests: XCTestCase {
    private func provider(_ id: Int, _ name: String, logo: String? = "/logo.png", priority: Int? = nil) -> JSONValue {
        var fields: [String: JSONValue] = ["provider_id": .integer(Int64(id)), "provider_name": .string(name)]
        if let logo { fields["logo_path"] = .string(logo) }
        if let priority { fields["display_priority"] = .integer(Int64(priority)) }
        return .object(fields)
    }

    func testRegionListsServicesByPriorityOnceEachWithALogo() {
        let spain: JSONValue = .object(["link": .string("https://www.themoviedb.org/movie/1/watch?locale=ES"),
            "flatrate": .array([provider(8, "Netflix", priority: 5), provider(9, "Prime", priority: 1), provider(8, "Netflix again", priority: 0)]),
            "free": .array([provider(10, "No logo", logo: nil), provider(11, "Free TV")]),
            "ads": .array([provider(12, "Ads", priority: 2)]),
            "rent": .array([provider(13, "Rental")])])
        let found = TMDBService.watchProviders(.object(["results": .object(["ES": spain, "US": .object([:])])]), region: "es")
        XCTAssertEqual(found.map(\.name), ["Netflix again", "Prime", "Ads", "Free TV"], "By priority, once per service, skipping services without a logo and rentals")
        XCTAssertEqual(found.first?.link, "https://www.themoviedb.org/movie/1/watch?locale=ES")
        XCTAssertEqual(found.first?.logo, "https://image.tmdb.org/t/p/w154/logo.png")
    }

    func testMissingRegionFallsBackToTheUnitedStatesAndCapsAtEight() {
        let many: [JSONValue] = (1...12).map { provider($0, "Service \($0)") }
        let us: JSONValue = .object(["flatrate": .array(many)])
        let found = TMDBService.watchProviders(.object(["results": .object(["US": us])]), region: "ZZ")
        XCTAssertEqual(found.count, 8); XCTAssertEqual(found.first?.name, "Service 1", "Equal priorities keep TMDB's order")
        XCTAssertEqual(found.first?.link, "", "A region without a link has none")
        XCTAssertTrue(TMDBService.watchProviders(.object(["results": .object([:])]), region: "ES").isEmpty)
        XCTAssertTrue(TMDBService.watchProviders(.null, region: "ES").isEmpty)
    }

    func testDetailsSavedBeforeProvidersExistedStillDecode() throws {
        let data = Data(#"{"countries":[],"studios":[],"cast":[],"crew":[],"recommendations":[],"similar":[],"trailers":[],"backdrops":[],"posters":[],"logos":[],"collection":[]}"#.utf8)
        let details = try JSONDecoder().decode(MediaDetails.self, from: data)
        XCTAssertNil(details.watchProviders)
    }
}
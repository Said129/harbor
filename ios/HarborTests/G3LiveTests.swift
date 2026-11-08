import XCTest
@testable import Harbor

/// Desktop parity rules for Live TV and VOD: series logo fill (`vod.ts`), Xtream stream base
/// (`xtream.ts`), M3U decorative rows and get.php guide links (`m3u.ts`), the live-screen search
/// (`use-channel-filter.ts`) and group relevance (`group-relevance.ts`). No network, no UI.
final class G3LiveTests: XCTestCase {
    private func channel(_ id: String, _ name: String, group: String? = nil, url: String? = nil, logo: String? = nil) -> LiveChannel {
        LiveChannel(id: id, source: "s1", tvgID: nil, name: name, logo: logo, group: group, url: url ?? "https://example.com/\(id).m3u8", catchup: nil, duration: nil, attributes: [:])
    }

    // MARK: Series logo (vod.ts)

    func testSeriesLogoFillsFromLaterEpisodeWhenFirstHasNone() throws {
        let library = try VODLibrary.build([
            channel("e1", "Show S01E01", url: "https://example.com/series/u/p/1.mkv", logo: nil),
            channel("e2", "Show S01E02", url: "https://example.com/series/u/p/2.mkv", logo: "https://img.example.com/show.png"),
        ])
        XCTAssertEqual(library.series.count, 1)
        XCTAssertEqual(library.series.first?.logo, "https://img.example.com/show.png")
    }

    func testSeriesLogoKeepsTheFirstUsableLogo() throws {
        let library = try VODLibrary.build([
            channel("e1", "Show S01E01", url: "https://example.com/series/u/p/1.mkv", logo: "https://img.example.com/first.png"),
            channel("e2", "Show S01E02", url: "https://example.com/series/u/p/2.mkv", logo: "https://img.example.com/second.png"),
        ])
        XCTAssertEqual(library.series.first?.logo, "https://img.example.com/first.png")
    }

    func testEmptyLogoCountsAsMissing() {
        XCTAssertNil(VODLibrary.fillLogo(nil, from: nil))
        XCTAssertEqual(VODLibrary.fillLogo("", from: ""), "", "Desktop leaves an empty logo as it is when no episode has one")
        XCTAssertEqual(VODLibrary.fillLogo("", from: "https://img.example.com/a.png"), "https://img.example.com/a.png")
        XCTAssertEqual(VODLibrary.fillLogo("https://img.example.com/a.png", from: "https://img.example.com/b.png"), "https://img.example.com/a.png")
    }

    // MARK: Xtream stream base (xtream.ts deriveStreamBase)

    func testHTTPSServerWithoutAnyPortIsForcedToHTTPSHost() {
        XCTAssertEqual(XtreamClient.streamBase("http://example.com:8080", serverProtocol: "https", httpsPort: nil, port: nil), "https://example.com")
        XCTAssertEqual(XtreamClient.streamBase("http://example.com", serverProtocol: "HTTPS", httpsPort: "", port: "  "), "https://example.com")
    }

    func testHTTPSPortIsPreferredThenPort() {
        XCTAssertEqual(XtreamClient.streamBase("http://example.com", serverProtocol: "https", httpsPort: "9443", port: "8443"), "https://example.com:9443")
        XCTAssertEqual(XtreamClient.streamBase("http://example.com", serverProtocol: "https", httpsPort: "", port: "8443"), "https://example.com:8443")
    }

    func testOutOfRangePortIsDropped() {
        XCTAssertEqual(XtreamClient.streamBase("http://example.com", serverProtocol: "https", httpsPort: "99999", port: nil), "https://example.com")
    }

    func testNonHTTPSServerKeepsItsBase() {
        XCTAssertEqual(XtreamClient.streamBase("http://example.com:8080", serverProtocol: "http", httpsPort: "9443", port: nil), "http://example.com:8080")
        XCTAssertEqual(XtreamClient.streamBase("http://example.com:8080", serverProtocol: nil, httpsPort: nil, port: nil), "http://example.com:8080")
    }

    // MARK: M3U decorative rows (m3u.ts isDecorativeRow)

    func testSeparatorAndSymbolOnlyNamesAreDecorative() {
        for name in ["", "   ", "----", "★★★", "══", "📺📺", "| - |"] {
            XCTAssertTrue(M3UParser.isDecorativeRow(name), name)
        }
    }

    func testNamesWithLettersOrDigitsAreChannels() {
        for name in ["CNN", "24", "Canal 5", "★ Sports ★", "قناة الجزيرة"] {
            XCTAssertFalse(M3UParser.isDecorativeRow(name), name)
        }
    }

    func testParserDropsDecorativeRowsAndUsesTitleWhenTvgNameIsEmpty() throws {
        let text = """
        #EXTM3U
        #EXTINF:-1 tvg-name="----",----
        http://example.com/decor.ts
        #EXTINF:-1 tvg-name="" group-title="News",Fallback Title
        http://example.com/news.ts
        """
        let channels = try M3UParser.parse(Data(text.utf8), source: "s1")
        XCTAssertEqual(channels.map(\.name), ["Fallback Title"])
        XCTAssertEqual(channels.first?.group, "News")
    }

    // MARK: get.php guide links (m3u.ts deriveEpgUrls)

    func testGetPHPLinkDerivesXMLTVThenGuideLinks() {
        XCTAssertEqual(LiveTVEPG.derivedURLs(playlist: "http://example.com:8080/get.php?username=ann&password=s3cret&type=m3u_plus&output=ts"), [
            "http://example.com:8080/xmltv.php?username=ann&password=s3cret",
            "http://example.com:8080/get.php?username=ann&password=s3cret&type=epg",
        ])
    }

    func testPlayerAPILinkAlsoDerivesGuideLinks() {
        XCTAssertEqual(LiveTVEPG.derivedURLs(playlist: "https://example.com/player_api.php?username=a&password=b"), [
            "https://example.com/xmltv.php?username=a&password=b",
            "https://example.com/get.php?username=a&password=b&type=epg",
        ])
    }

    func testPlainPlaylistAndMissingCredentialsDeriveNothing() {
        XCTAssertEqual(LiveTVEPG.derivedURLs(playlist: "https://example.com/list.m3u"), [])
        XCTAssertEqual(LiveTVEPG.derivedURLs(playlist: "https://example.com/get.php?username=a"), [])
    }

    // MARK: Live TV search (use-channel-filter.ts + arabicAwareMatch)

    func testEmptyQueryMatchesEveryChannel() {
        let item = channel("c1", "CNN HD", group: "News")
        XCTAssertTrue(LiveTVSearch.channelMatches(item, query: ""))
        XCTAssertTrue(LiveTVSearch.channelMatches(item, query: "   "))
    }

    func testSingleCharacterQueryIsNotRejected() {
        let item = channel("c1", "CNN HD", group: "News")
        XCTAssertTrue(LiveTVSearch.channelMatches(item, query: "c"))
        XCTAssertFalse(LiveTVSearch.channelMatches(item, query: "z"))
    }

    func testSearchMatchesNameOrGroupCaseInsensitively() {
        let item = channel("c1", "CNN HD", group: "News")
        XCTAssertTrue(LiveTVSearch.channelMatches(item, query: "  NEWS "))
        XCTAssertTrue(LiveTVSearch.channelMatches(item, query: "cnn hd"))
        XCTAssertFalse(LiveTVSearch.channelMatches(item, query: "sports"))
    }

    func testArabicSearchFoldsTehMarbutaAndHeh() {
        let item = channel("c3", "قناة الجزيرة", group: "أخبار")
        // teh marbuta (ة) in the channel name, heh (ه) in the query.
        XCTAssertTrue(LiveTVSearch.channelMatches(item, query: "قناه"))
        // plain alef in the query, hamza alef (أ) in the group.
        XCTAssertTrue(LiveTVSearch.channelMatches(item, query: "اخبار"))
        XCTAssertFalse(LiveTVSearch.channelMatches(item, query: "رياضة"))
    }

    // MARK: Group relevance (group-relevance.ts)

    func testRegionGroupsFirstThenNeutralThenAlphabetical() {
        let groups = ["Random", "Sports", "US | News", "Spanish", "ES Canal"]
        XCTAssertEqual(LiveTVGroupOrder.sortedGroups(groups, region: "US", preferredLanguages: ["English"]), [
            "US | News", "Sports", "ES Canal", "Random", "Spanish",
        ])
    }

    func testRegionScoresHeadThenAnyToken() {
        XCTAssertEqual(LiveTVGroupOrder.score("US | News", region: "US", preferredLanguages: []), 100)
        XCTAssertEqual(LiveTVGroupOrder.score("Canal US", region: "us", preferredLanguages: []), 80)
        XCTAssertEqual(LiveTVGroupOrder.score("Sports", region: "US", preferredLanguages: []), 5)
        XCTAssertEqual(LiveTVGroupOrder.score("", region: "US", preferredLanguages: []), 0)
    }

    func testLanguagesScoreByPreferenceRank() {
        let languages = ["French", "Spanish"]
        XCTAssertEqual(LiveTVGroupOrder.score("French Films", region: "XX", preferredLanguages: languages), 60)
        XCTAssertEqual(LiveTVGroupOrder.score("Spanish Movies", region: "XX", preferredLanguages: languages), 55)
        XCTAssertEqual(LiveTVGroupOrder.score("News Spanish", region: "XX", preferredLanguages: languages), 40)
        XCTAssertEqual(LiveTVGroupOrder.sortedGroups(["Others", "Spanish Movies", "ES Kids", "French Films"], region: "XX", preferredLanguages: languages), [
            "French Films", "ES Kids", "Spanish Movies", "Others",
        ])
    }
}

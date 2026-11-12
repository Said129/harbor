import XCTest
@testable import Harbor

/// Live TV rules added in the F6 parity pass: Desktop's most-watched channel order (`channel-order.ts`), the
/// guide address rule with a typed `epgUrl` (`playlist-entry.ts`, `use-epg.ts`), and the XMLTV reader's window and
/// gzip signature (`xmltv.ts`). Expected values were traced by hand against the Desktop code.
final class F6LiveTVTests: XCTestCase {
    private func channel(_ id: String, group: String? = nil) -> LiveChannel {
        LiveChannel(id: id, source: "s1", tvgID: nil, name: id, logo: nil, group: group, url: "https://example.com/\(id).m3u8", catchup: nil, duration: nil, attributes: [:])
    }

    // MARK: Most-watched order

    func testPinnedFirstThenMostWatchedThenTheRest() {
        let list = [channel("a"), channel("b"), channel("c"), channel("d")]
        let ordered = LiveTVCatalogOrder.userChannelOrder(list, pinned: ["d"], plays: ["b": 3, "c": 2])
        XCTAssertEqual(ordered.map(\.id), ["d", "b", "a", "c"])
    }

    func testEqualPlayCountsKeepTheSourceOrderAndCountsBelowTheMinimumStayInRest() {
        let list = [channel("a"), channel("b"), channel("c")]
        let ordered = LiveTVCatalogOrder.userChannelOrder(list, pinned: [], plays: ["c": 5, "b": 5, "a": 2])
        XCTAssertEqual(ordered.map(\.id), ["b", "c", "a"])
    }

    func testWithoutPinsOrWatchedChannelsTheListIsUnchanged() {
        let list = [channel("a"), channel("b")]
        XCTAssertEqual(LiveTVCatalogOrder.userChannelOrder(list, pinned: [], plays: ["a": 1]).map(\.id), ["a", "b"])
    }

    func testHiddenCategoriesLeaveTheCatalogAfterTheOrderIsBuilt() {
        let list = [channel("a", group: "News"), channel("b", group: "Sports")]
        let prefs = LiveGroupPrefs(pinned: [], hidden: ["Sports"])
        let ordered = LiveTVCatalogOrder.catalog(list, region: "", preferredLanguages: [], pinnedChannels: [], prefs: prefs, plays: ["b": 9])
        XCTAssertEqual(ordered.map(\.id), ["a"])
    }

    // MARK: Guide addresses

    func testTypedGuideAddressComesFirstAndIsTheOnlyOneForAPlainList() {
        let source = LivePlaylistSource(id: "3F2504E0-4F89-11D3-9A0C-0305E82C3301", name: "Lista", url: "https://lista.example.com/list.m3u", epgURL: "https://guide.example.com/xmltv.xml")
        let urls = LiveTVGuideService.urls(for: source).map { $0.absoluteString }
        XCTAssertEqual(urls.first, "https://guide.example.com/xmltv.xml")
        XCTAssertEqual(urls.count, 1)
    }

    func testAnEmptyTypedGuideAddressIsIgnored() {
        let source = LivePlaylistSource(id: "3F2504E0-4F89-11D3-9A0C-0305E82C3302", name: "Lista", url: "https://lista.example.com/list.m3u", epgURL: "")
        XCTAssertTrue(LiveTVGuideService.urls(for: source).isEmpty)
    }

    func testAnXtreamPlaylistLinkStillNamesTwoGuideAddressesAfterTheTypedOne() {
        let source = LivePlaylistSource(id: "3F2504E0-4F89-11D3-9A0C-0305E82C3303", name: "Xtream", url: "https://lista.example.com/get.php?username=user&password=pass&type=m3u", epgURL: "https://guide.example.com/xmltv.xml")
        let urls = LiveTVGuideService.urls(for: source).map { $0.absoluteString }
        XCTAssertEqual(urls.count, 3)
        XCTAssertEqual(urls.first, "https://guide.example.com/xmltv.xml")
    }

    // MARK: XMLTV reader

    func testGuideParsesChannelNamesAndProgrammes() throws {
        let xml = "<tv><channel id=\"c1\"><display-name>One</display-name></channel><programme start=\"20260101120000 +0000\" stop=\"20260101130000 +0000\" channel=\"c1\"><title>Show</title></programme></tv>"
        let guide = try LiveTVXMLTV.parse(Data(xml.utf8), window: nil)
        XCTAssertEqual(guide.programs["c1"]?.count, 1)
        XCTAssertEqual(guide.displayNames["c1"], "One")
        XCTAssertFalse(guide.isEmpty)
    }

    func testProgrammesOutsideTheWindowAreDropped() throws {
        let xml = "<tv><programme start=\"20100101120000 +0000\" stop=\"20100101130000 +0000\" channel=\"c1\"><title>Old</title></programme></tv>"
        let window = Date(timeIntervalSince1970: 1_767_225_600)...Date(timeIntervalSince1970: 1_767_312_000)
        let guide = try LiveTVXMLTV.parse(Data(xml.utf8), window: window)
        XCTAssertNil(guide.programs["c1"])
        XCTAssertTrue(guide.isEmpty)
    }

    func testGzipSignatureIsRecognised() {
        XCTAssertTrue(LiveTVXMLTV.isGzip(Data([0x1f, 0x8b, 0x08, 0x00])))
        XCTAssertFalse(LiveTVXMLTV.isGzip(Data("<tv/>".utf8)))
    }

    func testATruncatedGzipBodyIsRefused() {
        XCTAssertThrowsError(try LiveTVXMLTV.gunzip(Data([0x1f, 0x8b, 0x08, 0x00])))
    }
}

import XCTest
@testable import Harbor

final class R23XMLTVTests: XCTestCase {
    private let sample = """
    <?xml version="1.0" encoding="UTF-8"?>
    <tv>
      <channel id="one.us"><display-name>Channel One</display-name><icon src="http://logos.example/one.png"/></channel>
      <channel id="two"><display-name>Two &amp; Co</display-name></channel>
      <programme start="20261108100000 +0000" stop="20261108110000 +0000" channel="one.us"><title>Morning</title><desc>Early &lt;show&gt;</desc></programme>
      <programme start="20261108120000 +0100" stop="20261108130000 +0100" channel="one.us"><title><![CDATA[Late & <cut>]]></title></programme>
      <programme start="20261108120000" stop="20261108110000" channel="one.us"><title>Backwards</title></programme>
      <programme start="20261108100000" stop="20261108101500" channel="two"><title></title></programme>
      <programme start="bad" stop="20261108101500" channel="two"><title>Bad</title></programme>
      <programme start="20261108100000" stop="20261108101500"><title>No channel</title></programme>
    </tv>
    """

    private let twoShows = """
    <tv>
      <programme start="20261108100000 +0000" stop="20261108110000 +0000" channel="one.us"><title>A</title></programme>
      <programme start="20261108110000 +0000" stop="20261108120000 +0000" channel="one.us"><title>B</title></programme>
    </tv>
    """

    private func channel(_ id: String, name: String, tvgID: String?, url: String = "http://example.com/live.m3u8", attributes: [String: String] = [:]) -> LiveChannel {
        LiveChannel(id: id, source: "source", tvgID: tvgID, name: name, logo: nil, group: nil, url: url, catchup: nil, duration: nil, attributes: attributes)
    }

    private func at(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSince1970: seconds)
    }

    private func date(_ raw: String) -> Date {
        Date(timeIntervalSince1970: LiveTVXMLTV.parseTime(raw) ?? 0)
    }

    func testParsesChannelNamesAndProgrammes() throws {
        let guide = try LiveTVXMLTV.parse(Data(sample.utf8))
        XCTAssertEqual(guide.displayNames["one.us"], "Channel One")
        XCTAssertEqual(guide.displayNames["two"], "Two & Co")
        let one = try XCTUnwrap(guide.programs["one.us"])
        XCTAssertEqual(one.map(\.title), ["Morning", "Late & <cut>"])
        XCTAssertEqual(one[0].description, "Early <show>")
        XCTAssertNil(one[1].description)
        XCTAssertEqual(try XCTUnwrap(guide.programs["two"]).map(\.title), ["Untitled"])
        XCTAssertEqual(guide.programs.count, 2)
    }

    func testDropsProgrammesWithoutAUsableWindowOrChannel() throws {
        let guide = try LiveTVXMLTV.parse(Data(sample.utf8))
        let titles = (guide.programs["one.us"] ?? []).map(\.title) + (guide.programs["two"] ?? []).map(\.title)
        XCTAssertFalse(titles.contains("Backwards"))
        XCTAssertFalse(titles.contains("Bad"))
        XCTAssertFalse(titles.contains("No channel"))
    }

    func testXMLTVTimesAreUTCUnlessAnOffsetFollows() {
        XCTAssertEqual(LiveTVXMLTV.parseTime("19700101000000"), 0)
        XCTAssertEqual(LiveTVXMLTV.parseTime("19700101010000 +0100"), 0)
        XCTAssertEqual(LiveTVXMLTV.parseTime("20261108100000 -0530"), LiveTVXMLTV.parseTime("20261108153000"))
        XCTAssertEqual(LiveTVXMLTV.parseTime("20261108100000 +0130"), LiveTVXMLTV.parseTime("20261108083000"))
        XCTAssertNil(LiveTVXMLTV.parseTime("not a time"))
    }

    func testRefusesGzipBodiesAndKeepsDesktopsSizeCap() {
        XCTAssertThrowsError(try LiveTVXMLTV.parse(Data([0x1f, 0x8b, 0x08, 0x00])))
        XCTAssertEqual(LiveTVXMLTV.maximumBytes, 200 * 1024 * 1024)
    }

    func testNowAndNextAroundProgrammeEdges() throws {
        let programs = try XCTUnwrap(LiveTVXMLTV.parse(Data(twoShows.utf8)).programs["one.us"])
        let middle = LiveTVGuideLookup.nowNext(programs, at: date("20261108103000"))
        XCTAssertEqual(middle.current?.title, "A")
        XCTAssertEqual(middle.next?.title, "B")
        let boundary = LiveTVGuideLookup.nowNext(programs, at: date("20261108110000"))
        XCTAssertEqual(boundary.current?.title, "B")
        XCTAssertNil(boundary.next)
        let gapBefore = LiveTVGuideLookup.nowNext(programs, at: date("20261108090000"))
        XCTAssertNil(gapBefore.current)
        XCTAssertEqual(gapBefore.next?.title, "A")
        let afterEnd = LiveTVGuideLookup.nowNext(programs, at: date("20261108120000"))
        XCTAssertNil(afterEnd.current)
        XCTAssertNil(afterEnd.next)
        XCTAssertNil(LiveTVGuideLookup.nowNext(nil, at: at(0)).current)
    }

    func testMatchesByTvgIDThenByChannelName() throws {
        let guide = try LiveTVXMLTV.parse(Data(sample.utf8))
        let byID = channel("a", name: "Anything", tvgID: "one.us")
        XCTAssertEqual(LiveTVGuideLookup.programs(for: byID, guide: guide, tvgIDCounts: [:])?.count, 2)
        let byName = channel("b", name: "channel one", tvgID: nil)
        XCTAssertEqual(LiveTVGuideLookup.programs(for: byName, guide: guide, tvgIDCounts: [:])?.count, 2)
        XCTAssertNil(LiveTVGuideLookup.programs(for: channel("c", name: "Other", tvgID: nil), guide: guide, tvgIDCounts: [:]))
    }

    func testSharedTvgIDNeedsItsWordsInTheChannelName() throws {
        let guide = try LiveTVXMLTV.parse(Data(sample.utf8))
        let counts = ["one.us": 2]
        XCTAssertNotNil(LiveTVGuideLookup.programs(for: channel("a", name: "One HD", tvgID: "one.us"), guide: guide, tvgIDCounts: counts))
        XCTAssertNil(LiveTVGuideLookup.programs(for: channel("b", name: "Sport", tvgID: "one.us"), guide: guide, tvgIDCounts: counts))
    }

    func testTvgShiftMovesTheChannelsProgrammes() throws {
        let guide = try LiveTVXMLTV.parse(Data(sample.utf8))
        let shifted = channel("s", name: "Shifted", tvgID: "one.us", attributes: ["tvg-shift": "2"])
        let programs = try XCTUnwrap(LiveTVGuideLookup.programs(for: shifted, guide: guide, tvgIDCounts: [:]))
        XCTAssertEqual(programs.first?.start, guide.programs["one.us"]?.first?.start.addingTimeInterval(7_200))
    }

    func testOverlappingProgrammesKeepTheLongerOne() {
        let programs = [
            LiveProgram(id: "1", title: "Short", description: nil, start: at(0), end: at(1_800)),
            LiveProgram(id: "2", title: "Long", description: nil, start: at(900), end: at(4_500)),
            LiveProgram(id: "3", title: "Tail", description: nil, start: at(4_500), end: at(5_000)),
            LiveProgram(id: "4", title: "Empty", description: nil, start: at(6_000), end: at(6_000)),
        ]
        XCTAssertEqual(LiveTVGuideLookup.sanitize(programs).map(\.title), ["Long", "Tail"])
    }

    func testTokenizeAndNormalizeFollowDesktop() {
        XCTAssertEqual(LiveTVGuideLookup.tokenize("HD One US"), ["one"])
        XCTAssertEqual(LiveTVGuideLookup.tokenize("BBC 1 a"), ["bbc", "1"])
        XCTAssertEqual(LiveTVGuideLookup.normalizeTvgID("sportOne.us"), "sport One us")
    }

    func testXtreamCatchupBuildsTheTimeshiftLink() {
        let xtream = channel("x", name: "X", tvgID: nil, url: "http://srv.example:8080/live/user/pass/42.ts", attributes: ["catchup": "xtream"])
        XCTAssertEqual(LiveTVCatchup.url(for: xtream, start: at(0), end: at(3_600), now: at(60)), "http://srv.example:8080/timeshift/user/pass/60/1970-01-01:00-00/42.ts")
    }

    func testFlussonicCatchupRewritesTheChunkName() {
        let flussonic = channel("f", name: "F", tvgID: nil, url: "http://f.example/hls/index.m3u8?token=x", attributes: ["catchup": "flussonic"])
        XCTAssertEqual(LiveTVCatchup.url(for: flussonic, start: at(0), end: at(3_600), now: at(60)), "http://f.example/hls/index-0-3600.m3u8?token=x")
    }

    func testCatchupTemplateAndDefaultQuery() {
        let template = channel("t", name: "T", tvgID: nil, url: "http://a.example/stream.ts", attributes: ["catchup": "append", "catchup-source": "start=${start}&end=${end}"])
        XCTAssertEqual(LiveTVCatchup.url(for: template, start: at(0), end: at(3_600), now: at(60)), "http://a.example/stream.ts?start=0&end=3600")
        let standard = channel("d", name: "D", tvgID: nil, url: "http://a.example/stream.ts", attributes: ["catchup": "default"])
        XCTAssertEqual(LiveTVCatchup.url(for: standard, start: at(0), end: at(3_600), now: at(60)), "http://a.example/stream.ts?utc=0&lutc=60")
        XCTAssertNil(LiveTVCatchup.url(for: channel("n", name: "N", tvgID: nil, url: "http://a.example/stream.ts"), start: at(0), end: at(3_600)))
    }
}

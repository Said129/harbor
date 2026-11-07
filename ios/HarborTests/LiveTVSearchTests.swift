import XCTest
@testable import Harbor

/// Desktop's Live TV search (`searchLiveTvChannels`, `arabicAwareMatch`) and region top networks
/// (`src/lib/iptv/top-networks.ts`). Expected values were traced by hand against the Desktop regexes and scores.
final class LiveTVSearchTests: XCTestCase {
    private func channel(_ id: String, _ name: String, group: String? = nil, url: String? = nil) -> LiveChannel {
        LiveChannel(id: id, source: "s1", tvgID: nil, name: name, logo: nil, group: group, url: url ?? "https://example.com/\(id).m3u8", catchup: nil, duration: nil, attributes: [:])
    }

    // MARK: Search

    func testShortOrBlankQueryReturnsNothing() {
        let list = [channel("c1", "CNN HD", group: "News")]
        XCTAssertEqual(LiveTVSearch.channels(matching: "c", in: list).count, 0)
        XCTAssertEqual(LiveTVSearch.channels(matching: "   ", in: list).count, 0)
    }

    func testMatchesNameOrGroupCaseInsensitivelyAndTrimsTheQuery() {
        let list = [channel("c1", "CNN HD", group: "News"), channel("c2", "Canal 5", group: "Mexico")]
        XCTAssertEqual(LiveTVSearch.channels(matching: "  NEWS ", in: list).map(\.id), ["c1"])
        XCTAssertEqual(LiveTVSearch.channels(matching: "canal", in: list).map(\.id), ["c2"])
    }

    func testFirstChannelPerURLWinsOnlyAfterAMatch() {
        let list = [
            channel("c0", "Sport", url: "https://example.com/shared"),
            channel("c1", "CNN", url: "https://example.com/shared"),
            channel("c2", "CNN HD", url: "https://example.com/shared"),
            channel("c3", "CNN Backup", url: "https://example.com/other"),
        ]
        XCTAssertEqual(LiveTVSearch.channels(matching: "cnn", in: list).map(\.id), ["c1", "c3"])
    }

    func testResultsStopAtEightInSourceOrder() {
        let list = (1...10).map { channel("s\($0)", "Sport \($0)") }
        let hits = LiveTVSearch.channels(matching: "sport", in: list)
        XCTAssertEqual(hits.count, 8)
        XCTAssertEqual(hits.map(\.id), ["s1", "s2", "s3", "s4", "s5", "s6", "s7", "s8"])
    }

    func testArabicMatchesAcrossTehMarbutaAndAlefVariants() {
        let list = [channel("c1", "CNN HD", group: "News"), channel("c3", "قناة الجزيرة", group: "أخبار")]
        // teh marbuta (ة) in the channel name, heh (ه) in the query.
        XCTAssertEqual(LiveTVSearch.channels(matching: "قناه", in: list).map(\.id), ["c3"])
        // plain alef in the query, hamza alef (أ) in the group.
        XCTAssertEqual(LiveTVSearch.channels(matching: "اخبار", in: list).map(\.id), ["c3"])
        XCTAssertEqual(LiveTVSearch.channels(matching: "أخبار", in: list).map(\.id), ["c3"])
    }

    func testNormalizeArabicFoldsLettersAndDigits() {
        XCTAssertEqual(LiveTVSearch.normalizeArabic("إسلام"), "اسلام")
        XCTAssertEqual(LiveTVSearch.normalizeArabic("٢٠٢٤"), "2024")
        XCTAssertEqual(LiveTVSearch.normalizeArabic("  Foo   BAR "), "foo bar")
        XCTAssertFalse(LiveTVSearch.hasArabic("abc"))
        XCTAssertTrue(LiveTVSearch.hasArabic("abc الجزيرة"))
    }

    // MARK: Region top networks

    private var regionChannels: [LiveChannel] {
        [
            channel("r1", "ABC HD", group: "US"),
            channel("r2", "ABC Family", group: "US"),
            channel("r3", "NBC News", group: "US"),
            channel("r4", "NBC HD", group: "US"),
            channel("r5", "CNN", group: "News"),
        ]
    }

    func testRowsExistOnlyForKnownRegions() {
        XCTAssertEqual(LiveTVRegionNetworks.rows(for: "us").count, 9)
        XCTAssertEqual(LiveTVRegionNetworks.rows(for: "BR").count, 2)
        XCTAssertEqual(LiveTVRegionNetworks.rows(for: "gb").count, 2)
        XCTAssertTrue(LiveTVRegionNetworks.rows(for: "FR").isEmpty)
    }

    func testNetworksResolveInTableOrderAndExcludedChannelsAreSkipped() {
        let defs = LiveTVRegionNetworks.rows(for: "US").flatMap { $0.networks }
        let resolved = LiveTVRegionNetworks.resolve(regionChannels, defs: defs)
        XCTAssertEqual(resolved.map { $0.def.id }, ["abc", "nbc", "cnn"])
        XCTAssertEqual(resolved.map { $0.channel.id }, ["r1", "r4", "r5"])
    }

    func testHigherScoredChannelWinsANetwork() {
        let list = [channel("a1", "ABC", group: "US"), channel("a2", "ABC HD", group: "US")]
        let abc = LiveTVRegionNetworks.rows(for: "US")[0].networks
        let resolved = LiveTVRegionNetworks.resolve(list, defs: abc)
        XCTAssertEqual(resolved.map { $0.channel.id }, ["a2"])
    }

    func testFilterByRegionReadsGroupTokens() {
        XCTAssertEqual(LiveTVRegionNetworks.filterByRegion(regionChannels, region: "US").map(\.id), ["r1", "r2", "r3", "r4"])
        XCTAssertEqual(LiveTVRegionNetworks.filterByRegion(regionChannels, region: "FR").count, 5)
    }

    func testPromoteToFrontPutsResolvedNetworksFirst() {
        let promoted = LiveTVRegionNetworks.promoteToFront(regionChannels, rows: LiveTVRegionNetworks.rows(for: "US"))
        XCTAssertEqual(promoted.map(\.id), ["r1", "r4", "r5", "r2", "r3"])
    }

    func testSectionsKeepOnlyRowsWithAResolvedNetwork() {
        let sections = LiveTVRegionNetworks.sections(region: "US", channels: [regionChannels[0]])
        XCTAssertEqual(sections.map { $0.title }, ["Broadcast networks"])
        XCTAssertEqual(sections.first?.networks.map { $0.def.id } ?? [], ["abc"])
        XCTAssertTrue(LiveTVRegionNetworks.sections(region: "FR", channels: regionChannels).isEmpty)
    }
}

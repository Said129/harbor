import XCTest
@testable import Harbor

/// Desktop's live channel and category order, pins, hidden categories, favourites, sports period headings and
/// the Xtream short-EPG fallback. Fake data only: no network, no UI.
final class R21LiveTests: XCTestCase {
    private func channel(_ id: String, group: String?, source: String = "s1", url: String? = nil, attributes: [String: String] = [:]) -> LiveChannel {
        LiveChannel(id: id, source: source, tvgID: nil, name: "Name " + id, logo: nil, group: group, url: url ?? "https://example.com/\(id).m3u8", catchup: nil, duration: nil, attributes: attributes)
    }

    func testChannelsSortByGroupRelevanceThenGroupName() {
        let input = [channel("c1", group: "Other"), channel("c2", group: nil), channel("c3", group: "Movies"), channel("c4", group: "US News"), channel("c5", group: "US News")]
        let output = LiveTVCatalogOrder.channelsByGroupRelevance(input, region: "US", preferredLanguages: [])
        XCTAssertEqual(output.map(\.id), ["c4", "c5", "c3", "c1", "c2"])
    }

    func testEqualGroupScoresSortByNameAndKeepSourceOrderWithinAGroup() {
        let input = [channel("b1", group: "Beta"), channel("a1", group: "Alpha"), channel("a2", group: "Alpha")]
        let output = LiveTVCatalogOrder.channelsByGroupRelevance(input, region: "XX", preferredLanguages: [])
        XCTAssertEqual(output.map(\.id), ["a1", "a2", "b1"])
    }

    func testPinnedChannelsComeFirstInPinOrder() {
        let input = [channel("a", group: nil), channel("b", group: nil), channel("c", group: nil), channel("d", group: nil)]
        XCTAssertEqual(LiveTVCatalogOrder.pinnedFirst(input, pinned: ["c", "a", "missing"]).map(\.id), ["c", "a", "b", "d"])
        XCTAssertEqual(LiveTVCatalogOrder.pinnedFirst(input, pinned: []).map(\.id), ["a", "b", "c", "d"])
    }

    func testPinnedCategoriesFirstAndHiddenCategoriesRemoved() {
        let groups = ["X", "Y", "Z", "W"]
        let prefs = LiveGroupPrefs(pinned: ["Z", "X"], hidden: ["Y"])
        XCTAssertEqual(LiveTVCatalogOrder.groups(groups, prefs: prefs), ["Z", "X", "W"])
        XCTAssertEqual(LiveTVCatalogOrder.groups(groups, prefs: LiveGroupPrefs()), groups)
    }

    func testCatalogHidesChannelsOfHiddenCategoriesAndTreatsNoGroupAsUncategorized() {
        let input = [channel("m1", group: "Movies"), channel("n1", group: nil), channel("s1", group: "Sports")]
        let hiddenMovies = LiveTVCatalogOrder.catalog(input, region: "XX", preferredLanguages: [], pinnedChannels: [], prefs: LiveGroupPrefs(hidden: ["Movies"]))
        XCTAssertEqual(hiddenMovies.map(\.id), ["s1", "n1"])
        let hiddenUncategorized = LiveTVCatalogOrder.catalog(input, region: "XX", preferredLanguages: [], pinnedChannels: [], prefs: LiveGroupPrefs(hidden: ["Uncategorized"]))
        XCTAssertEqual(hiddenUncategorized.map(\.id), ["m1", "s1"])
    }

    func testPinningACategoryClearsItsHideAndHidingClearsItsPin() {
        let pinned = LiveTVCatalogOrder.togglingPin(LiveGroupPrefs(pinned: [], hidden: ["A"]), group: "A")
        XCTAssertEqual(pinned, LiveGroupPrefs(pinned: ["A"], hidden: []))
        XCTAssertEqual(LiveTVCatalogOrder.togglingPin(pinned, group: "A"), LiveGroupPrefs())
        let hidden = LiveTVCatalogOrder.togglingHidden(LiveGroupPrefs(pinned: ["A"], hidden: []), group: "A")
        XCTAssertEqual(hidden, LiveGroupPrefs(pinned: [], hidden: ["A"]))
        XCTAssertEqual(LiveTVCatalogOrder.togglingHidden(hidden, group: "A"), LiveGroupPrefs())
    }

    func testChannelPinToggleKeepsPinOrder() {
        XCTAssertEqual(LiveTVCatalogOrder.togglingChannelPin(["a"], channelID: "b"), ["a", "b"])
        XCTAssertEqual(LiveTVCatalogOrder.togglingChannelPin(["a", "b"], channelID: "a"), ["b"])
    }

    func testFavoritesKeepTheirOwnDataWithoutAPlaylistAndSortBySourceThenName() {
        let items = [
            channel("b", group: "Old", source: "s2", url: "https://example.com/b.m3u8"),
            channel("z", group: "Old", source: "s1", url: "https://example.com/z.m3u8"),
            channel("a", group: "Old", source: "s1", url: "https://example.com/a.m3u8"),
            channel("none", group: "Old", source: "s1", url: ""),
        ]
        let output = LiveTVCatalogOrder.favoriteChannels(items, sourceNames: ["s1": "Alpha list", "s2": "Beta list"])
        XCTAssertEqual(output.map(\.id), ["a", "z", "b"])
        XCTAssertEqual(output.map(\.group), ["Alpha list", "Alpha list", "Beta list"])
        XCTAssertEqual(output.first?.url, "https://example.com/a.m3u8")
    }

    func testSportsPeriodHeadingsFollowDesktopSport() {
        XCTAssertEqual(SportsPeriodHeading.heading(group: "tennis", leagueID: "ATP", period: 2), .template("Set {n}", 2))
        XCTAssertEqual(SportsPeriodHeading.heading(group: "volleyball", leagueID: "VNL", period: 5), .template("Set {n}", 5))
        XCTAssertEqual(SportsPeriodHeading.heading(group: "basketball", leagueID: "NBA", period: 4), .template("Quarter {n}", 4))
        XCTAssertEqual(SportsPeriodHeading.heading(group: "basketball", leagueID: "NBA", period: 5), .word("Overtime", 1))
        XCTAssertEqual(SportsPeriodHeading.heading(group: "basketball", leagueID: "NCAAB", period: 2), .template("Period {n}", 2))
        XCTAssertEqual(SportsPeriodHeading.heading(group: "football", leagueID: "NFL", period: 6), .word("Overtime", 2))
        XCTAssertEqual(SportsPeriodHeading.heading(group: "hockey", leagueID: "NHL", period: 3), .template("Period {n}", 3))
        XCTAssertEqual(SportsPeriodHeading.heading(group: "hockey", leagueID: "NHL", period: 4), .word("Overtime", 1))
        XCTAssertEqual(SportsPeriodHeading.heading(group: "baseball", leagueID: "MLB", period: 7), .word("Innings", 7))
        XCTAssertEqual(SportsPeriodHeading.heading(group: "cricket", leagueID: "ICC", period: 1), .word("Innings", 1))
        XCTAssertEqual(SportsPeriodHeading.heading(group: "soccer", leagueID: "EPL", period: 1), .template("Period {n}", 1))
    }

    func testXtreamShortEPGFallbackSkipsFailuresAndPlainChannels() async {
        let xtream = channel("x1", group: "News", attributes: [XtreamShortEPGFallback.streamIDAttribute: "1"])
        let failing = channel("x2", group: "News", attributes: [XtreamShortEPGFallback.streamIDAttribute: "2"])
        let plain = channel("p1", group: "News")
        let program = LiveProgram(id: "p", title: "Late", description: nil, start: Date(timeIntervalSince1970: 200), end: Date(timeIntervalSince1970: 300))
        let early = LiveProgram(id: "e", title: "Early", description: nil, start: Date(timeIntervalSince1970: 100), end: Date(timeIntervalSince1970: 200))
        let output = await XtreamShortEPGFallback.hydrate([xtream, failing, plain], base: [:]) { channel in
            if channel.id == "x2" { throw HarborError(code: "xtream-network") }
            return [program, early]
        }
        XCTAssertEqual(output[xtream.id]?.map(\.title), ["Early", "Late"])
        XCTAssertNil(output[failing.id])
        XCTAssertNil(output[plain.id])
    }

    func testXtreamShortEPGFallbackLeavesAGuideThatAlreadyExistsAlone() async {
        let existing = [LiveProgram(id: "k", title: "Known", description: nil, start: Date(timeIntervalSince1970: 1), end: Date(timeIntervalSince1970: 2))]
        var calls = 0
        let channels = [channel("x1", group: nil, attributes: [XtreamShortEPGFallback.streamIDAttribute: "1"])]
        let output = await XtreamShortEPGFallback.hydrate(channels, base: ["t": existing]) { _ in calls += 1; return [] }
        XCTAssertEqual(calls, 0)
        XCTAssertEqual(output.keys.sorted(), ["t"])
    }

    func testXtreamShortEPGFallbackLooksAtNoMoreThan120Channels() async {
        let channels = (0..<130).map { channel("x\($0)", group: nil, attributes: [XtreamShortEPGFallback.streamIDAttribute: "\($0)"]) }
        var calls = 0
        _ = await XtreamShortEPGFallback.hydrate(channels, base: [:]) { _ in calls += 1; return [] }
        XCTAssertEqual(calls, 120)
    }
}

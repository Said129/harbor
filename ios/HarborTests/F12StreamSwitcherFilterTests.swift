import XCTest
@testable import Harbor

final class F12StreamSwitcherFilterTests: XCTestCase {
    private func offer(_ id: Int, source: String? = nil, url: String? = nil, cached: Bool? = nil, languages: [String] = [],
                       name: String = "Addon", flagged: Bool = false) -> StreamOffer {
        var fields: [String: JSONValue] = ["addonId": .string("test"), "addonName": .string("Test"), "name": .string(name)]
        if let source = source { fields["source"] = .string(source) }
        if let url = url { fields["url"] = .string(url) }
        if let cached = cached { fields["cached"] = .object(["realdebrid": .bool(cached)]) }
        fields["audioLanguages"] = .array(languages.map { JSONValue.string($0) })
        if flagged {
            fields["reasons"] = .array([.object(["signal": .string("filtered:size-stub"), "delta": .integer(0)])])
        }
        return StreamOffer(id: id, raw: .object(fields))
    }

    private func ids(_ offers: [StreamOffer]) -> [Int] {
        return offers.map { $0.id }
    }

    func testSourceGroupMirrorsDesktopMapping() {
        let expected: [String: String] = [
            "REMUX": "Remux", "BluRay": "BluRay", "BDRip": "BluRay", "WEB-DL": "WEB-DL", "WEBRip": "WEBRip", "HDRip": "WEBRip",
            "HDTV": "HDTV", "DVDRip": "HDTV", "CAM": "CAM", "TS": "CAM", "HDTS": "CAM", "TC": "CAM", "SCR": "CAM"
        ]
        for (source, group) in expected {
            XCTAssertEqual(StreamSwitcherFilters.group(offer(1, source: source)), group, source)
        }
        XCTAssertNil(StreamSwitcherFilters.group(offer(2, source: "Other")))
        XCTAssertNil(StreamSwitcherFilters.group(offer(3)))
    }

    func testSourceGroupsAreListedInDesktopOrderWithCounts() {
        let list: [StreamOffer] = [
            offer(1, source: "CAM"), offer(2, source: "WEB-DL"), offer(3, source: "REMUX"), offer(4, source: "WEB-DL"),
            offer(5, source: "BDRip"), offer(6, source: "Other")
        ]
        let groups = StreamSwitcherFilters.sourceGroups(in: list)
        XCTAssertEqual(groups.map { $0.name }, ["Remux", "BluRay", "WEB-DL", "CAM"])
        XCTAssertEqual(groups.map { $0.count }, [1, 1, 2, 1])
        XCTAssertEqual(ids(StreamSwitcherFilters.applyGroup(list, group: "WEB-DL")), [2, 4])
        XCTAssertEqual(ids(StreamSwitcherFilters.applyGroup(list, group: nil)), [1, 2, 3, 4, 5, 6])
    }

    func testCachedOnlyKeepsDirectLinksCachedStreamsAndMarkedOnes() {
        let list: [StreamOffer] = [
            offer(1, url: "https://example.org/a.mkv"),
            offer(2, cached: true),
            offer(3, cached: false),
            offer(4, name: "Torrentio \u{26A1} 1080p"),
            offer(5, name: "Plain torrent"),
            offer(6, name: "Comet \u{26A1}\u{FE0F} 4K"),
            offer(7, name: "Sootio \u{2705}")
        ]
        XCTAssertEqual(ids(StreamSwitcherFilters.applyCached(list, cachedOnly: true, hasDebrid: true)), [1, 2, 4, 6, 7],
                       "the bolt counts with or without the emoji variation selector")
        XCTAssertEqual(StreamSwitcherFilters.uncachedCount(in: list), 2)
    }

    func testCachedOnlyNeverEmptiesTheListAndNeedsADebridService() {
        let none: [StreamOffer] = [offer(1, cached: false), offer(2)]
        XCTAssertEqual(ids(StreamSwitcherFilters.applyCached(none, cachedOnly: true, hasDebrid: true)), [1, 2], "nothing cached keeps everything")
        let some: [StreamOffer] = [offer(1, url: "https://example.org/a.mkv"), offer(2)]
        XCTAssertEqual(ids(StreamSwitcherFilters.applyCached(some, cachedOnly: true, hasDebrid: false)), [1, 2], "no debrid keeps everything")
        XCTAssertEqual(ids(StreamSwitcherFilters.applyCached(some, cachedOnly: false, hasDebrid: true)), [1, 2])
    }

    func testPreferredLanguagesAreDeduplicatedAndJapaneseIsAnimeOnly() {
        let plain = StreamSwitcherFilters.preferredLanguages(ranking: ["Spanish", "English"], audio: ["English", "Japanese"], isAnime: false)
        XCTAssertEqual(plain, ["Spanish", "English"])
        let anime = StreamSwitcherFilters.preferredLanguages(ranking: ["Spanish"], audio: ["English", "Japanese"], isAnime: true)
        XCTAssertEqual(anime, ["Spanish", "English", "Japanese"])
        XCTAssertEqual(StreamSwitcherFilters.languageCode("jp"), "ja")
        XCTAssertEqual(StreamSwitcherFilters.languageCode(" Spanish "), "es")
        XCTAssertEqual(StreamSwitcherFilters.languageCode("Esperanto"), "es")
        XCTAssertEqual(StreamSwitcherFilters.abbreviated(["Spanish", "English", "spanish"]), "ES, EN")
        XCTAssertEqual(StreamSwitcherFilters.abbreviated([]), "")
    }

    func testLanguageMatchFollowsDesktopRules() {
        let preferred: [String] = ["Spanish", "English"]
        XCTAssertTrue(StreamSwitcherFilters.matchesLanguages([], preferred: preferred), "no audio language listed always matches")
        XCTAssertTrue(StreamSwitcherFilters.matchesLanguages(["Multi"], preferred: preferred))
        XCTAssertTrue(StreamSwitcherFilters.matchesLanguages(["french", "SPANISH"], preferred: preferred))
        XCTAssertTrue(StreamSwitcherFilters.matchesLanguages(["English (US)"], preferred: preferred), "a longer name starting with the preference matches")
        XCTAssertFalse(StreamSwitcherFilters.matchesLanguages(["French", "German"], preferred: preferred))
        XCTAssertFalse(StreamSwitcherFilters.matchesLanguages(["French"], preferred: []))
    }

    func testLanguageFilterNeedsPreferencesAndCountsWhatItHides() {
        let list: [StreamOffer] = [
            offer(1, languages: ["Spanish"]), offer(2, languages: ["French"]), offer(3, languages: []), offer(4, languages: ["Japanese"])
        ]
        let preferred: [String] = ["Spanish"]
        XCTAssertEqual(ids(StreamSwitcherFilters.applyLanguages(list, preferred: preferred, enabled: true)), [1, 3])
        XCTAssertEqual(ids(StreamSwitcherFilters.applyLanguages(list, preferred: preferred, enabled: false)), [1, 2, 3, 4])
        XCTAssertEqual(ids(StreamSwitcherFilters.applyLanguages(list, preferred: [], enabled: true)), [1, 2, 3, 4])
        XCTAssertEqual(StreamSwitcherFilters.languageHiddenCount(in: list, preferred: preferred), 2)
        XCTAssertEqual(StreamSwitcherFilters.languageHiddenCount(in: list, preferred: []), 0)
    }

    func testFlaggedStreamsJoinTheListOnlyWhenShown() {
        let kept: [StreamOffer] = [offer(1, url: "https://example.org/a.mkv"), offer(2, url: "https://example.org/b.mkv")]
        let flagged: [StreamOffer] = [offer(10, url: "https://example.org/c.mkv", flagged: true)]
        var filters = StreamSwitcherFilters()
        XCTAssertEqual(ids(filters.apply(kept: kept, flagged: flagged, hasDebrid: false, preferred: [])), [1, 2])
        filters.showFlagged = true
        XCTAssertEqual(ids(filters.apply(kept: kept, flagged: flagged, hasDebrid: false, preferred: [])), [1, 2, 10])
        XCTAssertTrue(flagged[0].isFlagged)
        XCTAssertFalse(kept[0].isFlagged)
    }

    func testFiltersCombineInDesktopOrder() {
        let kept: [StreamOffer] = [
            offer(1, source: "WEB-DL", url: "https://example.org/a.mkv", languages: ["Spanish"]),
            offer(2, source: "WEB-DL", languages: ["Spanish"]),
            offer(3, source: "BluRay", url: "https://example.org/c.mkv", languages: ["Spanish"]),
            offer(4, source: "WEB-DL", url: "https://example.org/d.mkv", languages: ["French"])
        ]
        var filters = StreamSwitcherFilters()
        filters.cachedOnly = true
        filters.sourceGroup = "WEB-DL"
        filters.preferredLanguageOnly = true
        XCTAssertEqual(ids(filters.apply(kept: kept, flagged: [], hasDebrid: true, preferred: ["Spanish"])), [1])
        XCTAssertEqual(filters.activeCount, 3)
        filters = StreamSwitcherFilters()
        XCTAssertEqual(filters.activeCount, 0)
        XCTAssertEqual(ids(filters.apply(kept: kept, flagged: [], hasDebrid: true, preferred: ["Spanish"])), [1, 2, 3, 4])
    }

    func testRejectionBecomesAFlaggedStreamTheSwitcherCanList() {
        let stream: JSONValue = .object(["addonId": .string("test"), "addonName": .string("Test"), "url": .string("https://example.org/a.mkv")])
        let rejection: JSONValue = .object(["stream": stream, "reason": .string("size-stub")])
        guard let flagged = HarborService.flaggedStream(rejection) else { return XCTFail("a rejection with a stream is listed") }
        XCTAssertEqual(flagged["tier"].string, "ROUGH")
        XCTAssertEqual(flagged["url"].string, "https://example.org/a.mkv", "the fields playback needs are kept")
        XCTAssertEqual(flagged["reasons"].array.first?["signal"].string, "filtered:size-stub")
        XCTAssertTrue(StreamOffer(id: 5, raw: flagged).isFlagged)
        XCTAssertEqual(StreamOffer(id: 5, raw: flagged).quality, "ROUGH")
        XCTAssertNil(HarborService.flaggedStream(.object(["reason": .string("size-stub")])), "a rejection without a stream is dropped")
    }
}

import XCTest
@testable import Harbor

/// Desktop's saved stream filters (`lib/streams/custom-filters.ts`, `views/settings/stream-filters-panel.tsx`, `views/play-picker.tsx`).
final class CustomStreamFiltersTests: XCTestCase {
    private let gigabyte = 1_073_741_824

    private func offer(_ id: Int, _ fields: [String: JSONValue]) -> StreamOffer {
        StreamOffer(id: id, raw: .object(fields))
    }

    /// A 4K remux with HDR10, cached on Real-Debrid, 40 seeders and 60 GB.
    private var streamA: StreamOffer {
        offer(1, ["name": .string("Movie 4K REMUX"), "resolution": .string("4K"), "source": .string("BluRay"), "codec": .string("HEVC"),
                  "audio": .object(["codec": .string("TrueHD")]), "hdrFormat": .string("HDR10"),
                  "cached": .object(["rd": .bool(true)]), "inLibrary": .object([:]), "seeders": .integer(40), "size": .integer(Int64(60 * gigabyte))])
    }

    /// A 1080p WEB-DL, not cached, 3 seeders and 2 GB. Its name says 4K, which must not matter.
    private var streamB: StreamOffer {
        offer(2, ["name": .string("Movie 4K WEB"), "resolution": .string("1080p"), "source": .string("WEB-DL"), "codec": .string("AVC"),
                  "audio": .object(["codec": .string("AAC")]), "hdrFormat": .null,
                  "cached": .object(["rd": .bool(false)]), "inLibrary": .object([:]), "seeders": .integer(3), "size": .integer(Int64(2 * gigabyte))])
    }

    /// A 720p WEBRip with no seeder count, no size and no HDR field.
    private var streamC: StreamOffer {
        offer(3, ["name": .string("Movie 720p"), "resolution": .string("720p"), "source": .string("WEBRip"), "codec": .string("AVC"),
                  "audio": .object(["codec": .string("AAC")]), "cached": .object([:]), "inLibrary": .object([:])])
    }

    /// A 1080p HEVC Dolby Vision stream in the debrid library, with unsigned seeder and size numbers (8 GB).
    private var streamD: StreamOffer {
        offer(4, ["name": .string("Movie 1080p DV"), "resolution": .string("1080p"), "source": .string("WEB-DL"), "codec": .string("HEVC"),
                  "audio": .object(["codec": .string("DD+")]), "hdrFormat": .string("DV"),
                  "cached": .object([:]), "inLibrary": .object(["tb": .bool(true)]), "seeders": .unsigned(120), "size": .unsigned(UInt64(8 * gigabyte))])
    }

    /// Exactly 10 GB and 720p, so a 10 GB limit must let it through.
    private var streamE: StreamOffer {
        offer(5, ["resolution": .string("720p"), "source": .string("HDTV"), "codec": .string("AVC"), "audio": .object(["codec": .string("AC3")]),
                  "seeders": .integer(1), "size": .integer(Int64(10 * gigabyte))])
    }

    private var streams: [StreamOffer] { [streamA, streamB, streamC, streamD, streamE] }

    private func matchedIDs(_ filter: CustomStreamFilter) -> [Int] {
        streams.filter { filter.matches($0) }.map { $0.id }
    }

    private func isolatedDefaults() throws -> UserDefaults {
        let suite = "owned.custom.stream.filters." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return defaults
    }

    func testAnEmptyFilterHasNoPreferencesAndKeepsEveryStream() {
        let empty = CustomStreamFilter(id: "empty", name: "Any")
        XCTAssertFalse(empty.hasPreferences)
        XCTAssertEqual(matchedIDs(empty), [1, 2, 3, 4, 5], "A filter with no preferences matches every stream")
        let applied = CustomStreamFilters.apply(streams, filter: empty)
        XCTAssertEqual(applied.offers.map { $0.id }, [1, 2, 3, 4, 5])
        XCTAssertFalse(applied.fellBack)
        XCTAssertFalse(CustomStreamFilters.apply(streams, filter: nil).fellBack)
    }

    func testCategoriesReadParsedFieldsNotTheReleaseName() {
        let fourK = CustomStreamFilter(id: "4k", name: "4K", resolution: ["4K"])
        XCTAssertEqual(matchedIDs(fourK), [1], "Stream B says 4K in its name but is 1080p, so it does not match")
    }

    func testValuesInOneCategoryAreOrAndCategoriesAreAnd() {
        let either = CustomStreamFilter(id: "either", name: "Either", resolution: ["4K", "1080p"])
        XCTAssertEqual(matchedIDs(either), [1, 2, 4], "Any listed resolution matches")
        let both = CustomStreamFilter(id: "both", name: "Both", resolution: ["4K", "1080p"], source: ["WEB-DL"])
        XCTAssertEqual(matchedIDs(both), [2, 4], "Every set category must match, so the BluRay 4K stream is out")
    }

    func testAudioReadsTheAudioCodec() {
        let trueHD = CustomStreamFilter(id: "truehd", name: "TrueHD", audio: ["TrueHD"])
        XCTAssertEqual(matchedIDs(trueHD), [1])
        let dolby = CustomStreamFilter(id: "dd", name: "DD", audio: ["DD+", "AC3"])
        XCTAssertEqual(matchedIDs(dolby), [4, 5])
    }

    func testHdrOnlyNeedsAnHdrFormat() {
        let hdr = CustomStreamFilter(id: "hdr", name: "HDR", requireHdr: true)
        XCTAssertEqual(matchedIDs(hdr), [1, 4], "HDR10 and Dolby Vision pass; a null or missing HDR field does not")
    }

    func testCachedOnlyReadsCachedOrInLibrary() {
        let cached = CustomStreamFilter(id: "cached", name: "Cached", cachedOnly: true)
        XCTAssertEqual(matchedIDs(cached), [1, 4], "Cached on a debrid service, or already in the library")
    }

    func testMinimumSeedersNeedsACountAndZeroMeansAny() {
        let forty = CustomStreamFilter(id: "seeds", name: "Seeds", minSeeders: 10)
        XCTAssertEqual(matchedIDs(forty), [1, 4], "3 and missing seeders fail; 40 and unsigned 120 pass")
        let zero = CustomStreamFilter(id: "zero", name: "Zero", minSeeders: 0)
        XCTAssertFalse(zero.hasPreferences)
        XCTAssertEqual(matchedIDs(zero), [1, 2, 3, 4, 5], "0 accepts any seeder count, even a missing one")
    }

    func testMaximumSizeAllowsUnknownSizesAndCountsGigabytes() {
        let ten = CustomStreamFilter(id: "size", name: "Size", maxSizeGb: 10)
        XCTAssertEqual(matchedIDs(ten), [2, 3, 4, 5], "Unknown size (C) and exactly 10 GB (E) pass; 60 GB (A) does not")
        let tiny = CustomStreamFilter(id: "tiny", name: "Tiny", maxSizeGb: 1)
        XCTAssertEqual(matchedIDs(tiny), [3], "A known size above the limit fails, an unknown size still passes")
    }

    func testApplyKeepsMatchesAndFallsBackWhenNothingMatches() {
        let hd = CustomStreamFilter(id: "720", name: "720", resolution: ["720p"])
        let applied = CustomStreamFilters.apply(streams, filter: hd)
        XCTAssertEqual(applied.offers.map { $0.id }, [3, 5])
        XCTAssertFalse(applied.fellBack)

        let sd = CustomStreamFilter(id: "sd", name: "SD", resolution: ["SD"])
        let fallback = CustomStreamFilters.apply(streams, filter: sd)
        XCTAssertEqual(fallback.offers.map { $0.id }, [1, 2, 3, 4, 5], "When nothing matches, the unfiltered list stays")
        XCTAssertTrue(fallback.fellBack)
    }

    func testDecodesDesktopShapeAndDropsRowsThatCannotBeUsed() {
        let text = """
        [
          {"id":"f1","name":"  Best  ","resolution":["4K","1080p"],"source":["REMUX"],"codec":["HEVC"],"audio":["Atmos","Other"],
           "requireHdr":true,"cachedOnly":false,"minSeeders":5,"maxSizeGb":20},
          {"id":"","name":"No id"},
          {"id":"f3","name":"   "},
          {"id":"f4","name":"Negative","minSeeders":-2,"maxSizeGb":-1,"resolution":["4K","4K","8K"]},
          {"id":"f1","name":"Duplicate"}
        ]
        """
        let filters = CustomStreamFilters.decodeList(text)
        XCTAssertEqual(filters.map { $0.id }, ["f1", "f4"], "Rows without an id or name and duplicate ids are dropped")
        let best = filters[0]
        XCTAssertEqual(best.name, "Best")
        XCTAssertEqual(best.resolution, ["4K", "1080p"])
        XCTAssertEqual(best.source, ["REMUX"])
        XCTAssertEqual(best.codec, ["HEVC"])
        XCTAssertEqual(best.audio, ["Atmos", "Other"])
        XCTAssertTrue(best.requireHdr)
        XCTAssertFalse(best.cachedOnly)
        XCTAssertEqual(best.minSeeders, 5)
        XCTAssertEqual(best.maxSizeGb, 20)
        let negative = filters[1]
        XCTAssertNil(negative.minSeeders, "A negative seeder count is not set")
        XCTAssertNil(negative.maxSizeGb, "A negative size is not set")
        XCTAssertEqual(negative.resolution, ["4K", "8K"], "Repeats are removed; unknown values are kept as text")
    }

    func testBadJSONGivesNoFilters() {
        XCTAssertEqual(CustomStreamFilters.decodeList("not json"), [])
        XCTAssertEqual(CustomStreamFilters.decodeList("{}"), [])
    }

    func testEncodedListDecodesBackToTheSameFilters() throws {
        let filter = CustomStreamFilter(id: "round", name: "Round trip", resolution: ["4K"], source: ["REMUX"], codec: [], audio: ["TrueHD"],
                                        requireHdr: true, cachedOnly: true, minSeeders: 12, maxSizeGb: 25.5)
        let text = try XCTUnwrap(CustomStreamFilters.encodeList([filter]))
        XCTAssertTrue(text.contains("\"maxSizeGb\":25.5"))
        XCTAssertTrue(text.contains("\"requireHdr\":true"))
        XCTAssertEqual(CustomStreamFilters.decodeList(text), [filter])
    }

    func testBuilderFieldsValidateLikeDesktop() {
        XCTAssertTrue(CustomStreamFilters.parseMinSeeders("").valid)
        XCTAssertNil(CustomStreamFilters.parseMinSeeders("").value)
        XCTAssertEqual(CustomStreamFilters.parseMinSeeders(" 12 ").value, 12)
        XCTAssertEqual(CustomStreamFilters.parseMinSeeders("0").value, 0)
        XCTAssertFalse(CustomStreamFilters.parseMinSeeders("2.5").valid, "Seeders must be a whole number")
        XCTAssertFalse(CustomStreamFilters.parseMinSeeders("-1").valid)
        XCTAssertFalse(CustomStreamFilters.parseMinSeeders("many").valid)

        XCTAssertNil(CustomStreamFilters.parseMaxSizeGb("").value)
        XCTAssertEqual(CustomStreamFilters.parseMaxSizeGb("1.5").value, 1.5)
        XCTAssertFalse(CustomStreamFilters.parseMaxSizeGb("-2").valid, "A size must be 0 or more")
        XCTAssertFalse(CustomStreamFilters.parseMaxSizeGb("big").valid)

        XCTAssertEqual(CustomStreamFilters.gigabyteText(20), "20")
        XCTAssertEqual(CustomStreamFilters.gigabyteText(1.5), "1.5")
    }

    func testDimensionListShowsThreeValuesThenACount() {
        XCTAssertNil(CustomStreamFilters.dimensionText([]))
        XCTAssertEqual(CustomStreamFilters.dimensionText(["4K"]), "4K")
        XCTAssertEqual(CustomStreamFilters.dimensionText(["4K", "1080p", "720p"]), "4K, 1080p, 720p")
        XCTAssertEqual(CustomStreamFilters.dimensionText(["4K", "1080p", "720p", "480p"]), "4K, 1080p, 720p, +1")
    }

    func testChipTogglesAddAndRemoveOneValue() {
        XCTAssertEqual(CustomStreamFilters.toggled("4K", in: ["1080p"]), ["1080p", "4K"])
        XCTAssertEqual(CustomStreamFilters.toggled("1080p", in: ["1080p", "4K"]), ["4K"])
    }

    func testStoreSavesActivatesAndTogglesTheFilter() throws {
        let defaults = try isolatedDefaults()
        let best = CustomStreamFilter(id: "best", name: "Best", resolution: ["4K"])
        CustomStreamFilterStore.save(best, defaults: defaults)
        XCTAssertEqual(CustomStreamFilterStore.filters(defaults: defaults), [best])
        XCTAssertEqual(CustomStreamFilterStore.activeFilter(defaults: defaults), best, "Saving a filter with preferences makes it active")
        CustomStreamFilterStore.toggleActive("best", defaults: defaults)
        XCTAssertNil(CustomStreamFilterStore.activeFilter(defaults: defaults))
        CustomStreamFilterStore.toggleActive("best", defaults: defaults)
        XCTAssertEqual(CustomStreamFilterStore.activeID(defaults: defaults), "best")
    }

    func testSavingAnEmptyFilterClearsOnlyTheActiveFilterWhenItIsTheSameOne() throws {
        let defaults = try isolatedDefaults()
        let active = CustomStreamFilter(id: "active", name: "Active", resolution: ["1080p"])
        let other = CustomStreamFilter(id: "other", name: "Other")
        CustomStreamFilterStore.save(active, defaults: defaults)
        CustomStreamFilterStore.save(other, defaults: defaults)
        XCTAssertEqual(CustomStreamFilterStore.activeID(defaults: defaults), "active", "An empty filter does not take over the active one")
        var emptied = active
        emptied.resolution = []
        CustomStreamFilterStore.save(emptied, defaults: defaults)
        XCTAssertNil(CustomStreamFilterStore.activeID(defaults: defaults), "Emptying the active filter turns it off")
    }

    func testDeletingTheActiveFilterClearsIt() throws {
        let defaults = try isolatedDefaults()
        let filter = CustomStreamFilter(id: "gone", name: "Gone", cachedOnly: true)
        CustomStreamFilterStore.save(filter, defaults: defaults)
        CustomStreamFilterStore.delete("gone", defaults: defaults)
        XCTAssertEqual(CustomStreamFilterStore.filters(defaults: defaults), [])
        XCTAssertNil(CustomStreamFilterStore.activeID(defaults: defaults))
    }

    func testApplyActiveUsesTheStoredFilterAndItsFallback() throws {
        let defaults = try isolatedDefaults()
        CustomStreamFilterStore.save(CustomStreamFilter(id: "hd", name: "HD", resolution: ["720p"]), defaults: defaults)
        let filtered = CustomStreamFilterStore.applyActive(streams, defaults: defaults)
        XCTAssertEqual(filtered.offers.map { $0.id }, [3, 5])
        XCTAssertFalse(filtered.fellBack)
        CustomStreamFilterStore.setActiveID(nil, defaults: defaults)
        XCTAssertEqual(CustomStreamFilterStore.applyActive(streams, defaults: defaults).offers.map { $0.id }, [1, 2, 3, 4, 5])
    }
}

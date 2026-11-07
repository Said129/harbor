import XCTest
@testable import Harbor

/// Desktop's stream pipeline additions (`lib/streams/pipeline.ts`, `anitomy.ts`, `anime-identity-core.ts`,
/// `library.ts`): corroborated early-leak rescue, anime stream enrichment and the debrid library merge.
@MainActor final class StreamPipelineAdditionsTests: XCTestCase {
    private let gib = 1_073_741_824.0
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func daysAgo(_ days: Double) -> Date { now.addingTimeInterval(-days * 86_400) }

    private func rejection(_ reason: String, resolution: String, size: Double, group: String?) -> JSONValue {
        var stream: [String: JSONValue] = ["resolution": .string(resolution), "size": .number(size), "title": .string("Movie.2026.\(resolution)")]
        if let group { stream["releaseGroupNormalized"] = .string(group) }
        return .object(["reason": .string(reason), "stream": .object(stream)])
    }

    // MARK: Corroborated early-leak rescue

    func testRescueWindowFollowsDesktopBounds() {
        XCTAssertTrue(StreamEarlyLeakRescue.isInWindow(releaseDate: daysAgo(10), now: now))
        XCTAssertTrue(StreamEarlyLeakRescue.isInWindow(releaseDate: daysAgo(59.9), now: now))
        XCTAssertFalse(StreamEarlyLeakRescue.isInWindow(releaseDate: daysAgo(60), now: now), "days < 60 is strict")
        XCTAssertTrue(StreamEarlyLeakRescue.isInWindow(releaseDate: now.addingTimeInterval(80 * 86_400), now: now), "days -80 > -90")
        XCTAssertFalse(StreamEarlyLeakRescue.isInWindow(releaseDate: now.addingTimeInterval(100 * 86_400), now: now), "days -100 is outside")
    }

    func testReleaseDateReadsIsoDatesAsUTCMidnight() {
        XCTAssertEqual(StreamEarlyLeakRescue.releaseDate("2026-09-01"), Date(timeIntervalSince1970: 1_788_220_800))
        XCTAssertNil(StreamEarlyLeakRescue.releaseDate("not a date"))
        XCTAssertNil(StreamEarlyLeakRescue.releaseDate(nil))
    }

    func testRescueRestoresThreeStreamsOfOneCorroboratedCluster() {
        let rejected = (0..<3).map { _ in rejection("fresh-cinema-fake-web", resolution: "1080p", size: 2 * gib, group: "FLUX") }
        XCTAssertEqual(StreamEarlyLeakRescue.rescuedIndices(rejected, releaseDate: daysAgo(10), now: now), [0, 1, 2])
    }

    func testRescueAcceptsTwoReleaseGroupsButNotOneGroupTwice() {
        let twoGroups = [
            rejection("new-release-stub-1200mb", resolution: "1080p", size: 2 * gib, group: "FLUX"),
            rejection("new-release-stub-1200mb", resolution: "1080p", size: 2 * gib, group: "NTb"),
        ]
        XCTAssertEqual(StreamEarlyLeakRescue.rescuedIndices(twoGroups, releaseDate: daysAgo(10), now: now), [0, 1])
        let oneGroup = [
            rejection("new-release-stub-1200mb", resolution: "1080p", size: 2 * gib, group: "FLUX"),
            rejection("new-release-stub-1200mb", resolution: "1080p", size: 2 * gib, group: "FLUX"),
        ]
        XCTAssertEqual(StreamEarlyLeakRescue.rescuedIndices(oneGroup, releaseDate: daysAgo(10), now: now), [])
    }

    func testFourKNeedsTwoAndAHalfGiBAndQuarterGiBBuckets() {
        let small4K = (0..<3).map { _ in rejection("fresh-cinema-fake-4k-web", resolution: "4K", size: 2 * gib, group: "FLUX") }
        XCTAssertEqual(StreamEarlyLeakRescue.rescuedIndices(small4K, releaseDate: daysAgo(10), now: now), [])
        let large4K = (0..<3).map { _ in rejection("fresh-cinema-fake-4k-web", resolution: "4K", size: 3 * gib, group: "FLUX") }
        XCTAssertEqual(StreamEarlyLeakRescue.rescuedIndices(large4K, releaseDate: daysAgo(10), now: now), [0, 1, 2])
        // 2.00 and 2.10 GiB share the 2.00 bucket (8.4 rounds to 8); 2.20 GiB is in the 2.25 bucket (8.8 rounds to 9).
        let buckets = [2.0, 2.1, 2.2].map { rejection("fresh-cinema-fake-web", resolution: "1080p", size: $0 * gib, group: "FLUX") }
        XCTAssertEqual(StreamEarlyLeakRescue.rescuedIndices(buckets, releaseDate: daysAgo(10), now: now), [])
    }

    func testRescueIgnoresOtherReasonsResolutionsAndSmallStreams() {
        let otherReason = (0..<3).map { _ in rejection("size-stub", resolution: "1080p", size: 2 * gib, group: "FLUX") }
        XCTAssertEqual(StreamEarlyLeakRescue.rescuedIndices(otherReason, releaseDate: daysAgo(10), now: now), [])
        let sd = (0..<3).map { _ in rejection("fresh-cinema-fake-web", resolution: "720p", size: 2 * gib, group: "FLUX") }
        XCTAssertEqual(StreamEarlyLeakRescue.rescuedIndices(sd, releaseDate: daysAgo(10), now: now), [])
        let tiny = (0..<3).map { _ in rejection("fresh-cinema-fake-web", resolution: "1080p", size: 0.9 * gib, group: "FLUX") }
        XCTAssertEqual(StreamEarlyLeakRescue.rescuedIndices(tiny, releaseDate: daysAgo(10), now: now), [])
    }

    func testRescueNeedsAKnownReleaseDateInWindow() {
        let rejected = (0..<3).map { _ in rejection("fresh-cinema-fake-web", resolution: "1080p", size: 2 * gib, group: "FLUX") }
        XCTAssertEqual(StreamEarlyLeakRescue.rescuedIndices(rejected, releaseDate: nil, now: now), [])
        XCTAssertEqual(StreamEarlyLeakRescue.rescuedIndices(rejected, releaseDate: daysAgo(400), now: now), [])
    }

    // MARK: Anime stream enrichment

    func testParsesBracketGroupTitleEpisodeAndChecksum() {
        let found = AnimeStreamEnrichment.parse("[SubsPlease] One Piece - 1100 (1080p) [A1B2C3D4].mkv")
        XCTAssertEqual(found.releaseGroup, "SubsPlease")
        XCTAssertEqual(found.animeTitle, "One Piece")
        XCTAssertEqual(found.episodeNumber, 1100)
        XCTAssertEqual(found.resolution, "1080p")
        XCTAssertEqual(found.fileChecksum, "A1B2C3D4")
        XCTAssertFalse(found.isBatch)
        XCTAssertNil(found.episodeTitle)
    }

    func testParsesSeasonAndEpisodeTokens() {
        let found = AnimeStreamEnrichment.parse("Show Name S02E05 1080p.mkv")
        XCTAssertEqual(found.season, 2)
        XCTAssertEqual(found.episodeNumber, 5)
        XCTAssertEqual(found.animeTitle, "Show Name")
        XCTAssertNil(found.releaseGroup)
    }

    func testBatchKeywordMarksSeasonPackWithoutEpisode() {
        let found = AnimeStreamEnrichment.parse("[Judas] Series Name Batch (01-24) [1080p].mkv")
        XCTAssertTrue(found.isBatch)
        XCTAssertNil(found.episodeNumber)
        XCTAssertEqual(found.releaseGroup, "Judas")
        XCTAssertTrue(AnimeStreamEnrichment.parse("Show 01-12 [1080p]").isBatch, "a range of 2 or more episodes is a batch")
    }

    func testGroupNormalisesToUpperAlphanumerics() {
        XCTAssertEqual(AnimeStreamEnrichment.normalizedGroup("Erai-raws"), "ERAIRAWS")
    }

    func testEnrichmentReplacesRecognisedFieldsAndKeepsTheRest() {
        let parsed: JSONValue = .object([
            "title": .string("[Erai-raws] Show - 05 [1080p].mkv"),
            "name": .string("Torrentio"),
            "addonId": .string("torrentio"),
            "episode": .integer(1),
        ])
        let enriched = AnimeStreamEnrichment.enriched(parsed)
        // Desktop searches for the episode as written ("5"), so the leading zero in "05" leaves the dash in the title.
        XCTAssertEqual(enriched["parsedTitle"], .string("Show - 05"))
        XCTAssertEqual(enriched["episode"], .integer(5))
        XCTAssertEqual(enriched["releaseGroup"], .string("Erai-raws"))
        XCTAssertEqual(enriched["releaseGroupNormalized"], .string("ERAIRAWS"))
        XCTAssertEqual(enriched["resolution"], .string("1080p"))
        XCTAssertEqual(enriched["addonId"], .string("torrentio"))
        XCTAssertEqual(enriched["name"], .string("Torrentio"))
        XCTAssertEqual(enriched["seasonPack"], .null, "a single episode is not a season pack")
    }

    func testEnrichmentMarksBatchAsSeasonPackAndPrefersBehaviourHintFilename() {
        let batch: JSONValue = .object(["title": .string("Something else"), "behaviorHints": .object(["filename": .string("[Judas] Series Name Batch (01-24) [1080p].mkv")])])
        XCTAssertEqual(AnimeStreamEnrichment.enriched(batch)["seasonPack"], .bool(true))
        XCTAssertEqual(AnimeStreamEnrichment.primaryFilename(.object(["name": .string("Name only")])), "Name only")
        let nothing: JSONValue = .object(["addonId": .string("x")])
        XCTAssertEqual(AnimeStreamEnrichment.enriched(nothing), nothing)
    }

    func testExactEpisodeFilterKeepsExpectedAliasesAndPacks() {
        func stream(_ episode: Int?, pack: Bool = false) -> JSONValue {
            var fields: [String: JSONValue] = ["seasonPack": .bool(pack), "name": .string("s")]
            if let episode { fields["episode"] = .integer(Int64(episode)) }
            return .object(fields)
        }
        let parsed = [stream(1100), stream(1101), stream(1101, pack: true), stream(nil)]
        let aliased = AnimeStreamEnrichment.filterExactEpisode(parsed, isAnime: true, expected: 1100, aliases: [1101], trustDisabled: false)
        XCTAssertEqual(aliased.kept.count, 4)
        XCTAssertTrue(aliased.dropped.isEmpty)

        let strict = AnimeStreamEnrichment.filterExactEpisode(parsed, isAnime: true, expected: 1100, aliases: [], trustDisabled: false)
        XCTAssertEqual(strict.kept.count, 3, "the pack and the episode-less stream stay")
        XCTAssertEqual(strict.dropped.count, 1)
        XCTAssertEqual(strict.dropped.first?["reason"], JSONValue.string("anime-episode-mismatch:1101-vs-1100"))
    }

    func testExactEpisodeFilterOnlyRunsForAnimeWithKnownEpisodeAndTrustOn() {
        let parsed = [JSONValue.object(["episode": .integer(1101)])]
        XCTAssertEqual(AnimeStreamEnrichment.filterExactEpisode(parsed, isAnime: false, expected: 1100, aliases: [], trustDisabled: false).kept.count, 1)
        XCTAssertEqual(AnimeStreamEnrichment.filterExactEpisode(parsed, isAnime: true, expected: 1100, aliases: [], trustDisabled: true).kept.count, 1)
        XCTAssertEqual(AnimeStreamEnrichment.filterExactEpisode(parsed, isAnime: true, expected: nil, aliases: [], trustDisabled: false).kept.count, 1)
    }

    // MARK: Debrid library merge

    /// A title table for the fake parser. Names not in the table parse to their whole text.
    private func parser(_ table: [String: DebridLibraryMerge.Title]) -> DebridLibraryMerge.Parser {
        { text in table[text] ?? DebridLibraryMerge.Title(title: text) }
    }

    func testMovieLibraryMatchUsesTheYearWindowOfOneYear() {
        let table: [String: DebridLibraryMerge.Title] = [
            "Inception.2010.1080p": .init(title: "Inception", year: 2010, resolution: "1080p"),
            "Inception.2015.1080p": .init(title: "Inception", year: 2015, resolution: "1080p"),
            "Inception.2011.720p": .init(title: "Inception", year: 2011, resolution: "720p"),
        ]
        let items = [
            DebridLibraryMerge.Item(provider: .rd, hash: "aaaa", name: "Inception.2010.1080p"),
            DebridLibraryMerge.Item(provider: .rd, hash: "bbbb", name: "Inception.2015.1080p"),
            DebridLibraryMerge.Item(provider: .tb, hash: "cccc", name: "Inception.2011.720p"),
            DebridLibraryMerge.Item(provider: .tb, hash: "", name: "Inception.2010.1080p"),
        ]
        let query = DebridLibraryMerge.Query(type: .movie, title: "Inception", year: 2010, season: nil, episode: nil)
        let streams = DebridLibraryMerge.streams(items: items, query: query, parse: parser(table))
        XCTAssertEqual(streams.count, 2)
        XCTAssertEqual(streams[0]["infoHash"], .string("aaaa"))
        XCTAssertEqual(streams[0]["addonId"], .string("rd-library"))
        XCTAssertEqual(streams[0]["fileIdx"], .null, "no file index for a name-level match")
        XCTAssertTrue(streams[0]["title"].string?.hasPrefix("[RD+] Real-Debrid ") ?? false)
        XCTAssertEqual(streams[1]["infoHash"], .string("cccc"))
        XCTAssertEqual(streams[1]["addonId"], .string("tb-library"))
        XCTAssertTrue(streams[1]["title"].string?.hasPrefix("[TB+] TorBox ") ?? false)
    }

    func testSeriesLibraryMatchNeedsTheRequestedSeasonAndEpisode() {
        let table: [String: DebridLibraryMerge.Title] = [
            "Show.S02E03.1080p": .init(title: "Show", season: 2, episode: 3, resolution: "1080p"),
            "Show.S01E03": .init(title: "Show", season: 1, episode: 3),
        ]
        let items = [
            DebridLibraryMerge.Item(provider: .ad, hash: "1111", name: "Show.S02E03.1080p"),
            DebridLibraryMerge.Item(provider: .ad, hash: "2222", name: "Show.S01E03"),
            DebridLibraryMerge.Item(provider: .ad, hash: "3333", name: "Show Complete"),
        ]
        let query = DebridLibraryMerge.Query(type: .series, title: "Show", year: nil, season: 2, episode: 3)
        let streams = DebridLibraryMerge.streams(items: items, query: query, parse: parser(table))
        XCTAssertEqual(streams.map { $0["infoHash"] }, [.string("1111")], "wrong season and a title without season or episode are rejected")
    }

    func testFileLevelMatchPicksTheRequestedFileAndKeepsItsIndex() {
        let table: [String: DebridLibraryMerge.Title] = [
            "Show.S02E03.mkv": .init(title: "Show", season: 2, episode: 3),
            "Show.S02E04.mkv": .init(title: "Show", season: 2, episode: 4),
        ]
        let item = DebridLibraryMerge.Item(provider: .pm, hash: "dddd", name: "Show Pack", files: ["Show.S02E03.mkv", "Show.S02E04.mkv"])
        let query = DebridLibraryMerge.Query(type: .series, title: "Show", year: nil, season: 2, episode: 4)
        let found = DebridLibraryMerge.match(item, query: query, parse: parser(table))
        XCTAssertEqual(found?.fileIndex, 1)
        let stream = DebridLibraryMerge.stream(item, found ?? DebridLibraryMerge.Match(fileIndex: nil, parsedTitle: "", resolution: nil, codec: nil))
        XCTAssertEqual(stream["name"], .string("Show.S02E04.mkv"))
        XCTAssertEqual(stream["fileIdx"], .integer(1))
    }

    func testPositionalMatchUsesTheNthVideoFileWithoutExtras() {
        let item = DebridLibraryMerge.Item(provider: .ad, hash: "eeee", name: "Show Pack",
                                           files: ["Show/01.mkv", "Show/02.mkv", "Show/03.mkv", "Show/Extras/NCOP.mkv"])
        let query = DebridLibraryMerge.Query(type: .series, title: "Show", year: nil, season: nil, episode: 2)
        XCTAssertEqual(DebridLibraryMerge.match(item, query: query, parse: parser([:]))?.fileIndex, 1)
        let beyond = DebridLibraryMerge.Query(type: .series, title: "Show", year: nil, season: nil, episode: 4)
        XCTAssertNil(DebridLibraryMerge.match(item, query: beyond, parse: parser([:])))
    }

    func testNormalizeDropsSpacesAndPunctuation() {
        XCTAssertEqual(DebridLibraryMerge.normalize("Spider-Man: No Way Home"), "spidermannowayhome")
    }

    func testMergeJoinsLibraryAndAddonStreamsWithTheSameIdentity() {
        let library: JSONValue = .object(["infoHash": .string("ABCD"), "name": .string("X"), "title": .string("[RD+] Real-Debrid Library"),
                                          "addonId": .string("rd-library"), "addonName": .string("Real-Debrid Library")])
        let addon: JSONValue = .object(["infoHash": .string("abcd"), "name": .string("X"), "addonId": .string("torrentio"), "addonName": .string("Torrentio"),
                                        "sources": .array([.string("tracker:a")]), "url": .string("https://cdn.example.org/a.mkv")])
        let other: JSONValue = .object(["infoHash": .string("1234"), "addonId": .string("torrentio"), "addonName": .string("Torrentio")])
        let merged = DebridLibraryMerge.mergeAndDedupe(library: [library], addons: [addon, other])
        XCTAssertEqual(merged.count, 2)
        XCTAssertEqual(merged[0]["contributors"].array.map { $0["id"] }, [.string("rd-library"), .string("torrentio")])
        XCTAssertEqual(merged[0]["sources"], .array([.string("tracker:a")]))
        XCTAssertEqual(merged[0]["url"], .string("https://cdn.example.org/a.mkv"))
        XCTAssertEqual(merged[1]["infoHash"], .string("1234"))
    }

    func testIdentityUsesHashAndFileIndexOrUrlOrName() {
        XCTAssertEqual(DebridLibraryMerge.identity(.object(["infoHash": .string("AB"), "fileIdx": .integer(2)])), "hash:ab:2")
        XCTAssertEqual(DebridLibraryMerge.identity(.object(["url": .string("https://a.example.org/x")])), "url:https://a.example.org/x")
        XCTAssertEqual(DebridLibraryMerge.identity(.object(["name": .string("N"), "title": .string("T")])), "n:N:T")
    }

    func testListingsKeepProviderOrderAndSkipFailedProviders() async {
        let lister: DebridLibraryMerge.Lister = { provider in
            if provider == .tb { return nil }
            return [DebridLibraryMerge.Item(provider: provider, hash: provider.rawValue + "hash", name: provider.name)]
        }
        let items = await DebridLibraryMerge.listings(providers: [.rd, .tb, .ad], list: lister)
        XCTAssertEqual(items.map { $0.provider }, [.rd, .ad])
    }

    func testListerWithoutAClientContributesNothing() async {
        let none = await DebridLibraryMerge.lister(nil)(.rd)
        XCTAssertNil(none)
    }
}

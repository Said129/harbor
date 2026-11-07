import XCTest
@testable import Harbor

/// Desktop's "Auto-skip stalled streams" (`views/player.tsx`, `lib/player/stall-wait.ts`) and
/// "Stay on one source for a season" (`lib/season-lock.ts`, `play-picker.tsx`).
final class StreamStallPolicyTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func offer(_ id: Int, _ fields: [String: JSONValue]) -> StreamOffer { StreamOffer(id: id, raw: .object(fields)) }

    private func playable(_ id: Int, tier: String, url: String) -> StreamOffer {
        offer(id, ["tier": .string(tier), "url": .string(url)])
    }

    private func isolatedDefaults() -> UserDefaults {
        let suite = "owned.streams.stall." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return defaults
    }

    private func input(elapsed: Double, sample: StreamStallPolicy.Sample = .init(), automatic: Bool = true, attempts: Int = 1) -> StreamStallPolicy.Input {
        StreamStallPolicy.Input(elapsedSeconds: elapsed, sample: sample, automatic: automatic, attempts: attempts)
    }

    // MARK: Stall switching

    func testWaitIsClampedToDesktopRangeAndFallsBackToTenSeconds() {
        XCTAssertEqual(StreamStallPolicy.waitSeconds(nil), 10, "A missing value is the Desktop default")
        XCTAssertEqual(StreamStallPolicy.waitSeconds(3), 5, "Below 5 seconds is raised to 5")
        XCTAssertEqual(StreamStallPolicy.waitSeconds(500), 120, "Above 120 seconds is lowered to 120")
        XCTAssertEqual(StreamStallPolicy.waitSeconds(20), 20)
        XCTAssertEqual(StreamStallPolicy.waitChoices, [10, 20, 30, 45, 60])
    }

    func testSwitchesOnlyAfterTheFullWaitWhileNothingHasStarted() {
        XCTAssertEqual(StreamStallPolicy.decide(enabled: true, waitSeconds: 10, input: input(elapsed: 9.9)), .wait)
        XCTAssertEqual(StreamStallPolicy.decide(enabled: true, waitSeconds: 10, input: input(elapsed: 10)), .switchStream)
    }

    func testTheFeatureOffNeverSwitches() {
        XCTAssertEqual(StreamStallPolicy.decide(enabled: false, waitSeconds: 10, input: input(elapsed: 600)), .keep)
    }

    func testAnyStartedSignalKeepsTheSource() {
        let started: [StreamStallPolicy.Sample] = [
            .init(paused: true),
            .init(position: 0.5),
            .init(videoWidth: 1920, videoHeight: 1080),
        ]
        for sample in started {
            XCTAssertEqual(StreamStallPolicy.decide(enabled: true, waitSeconds: 10, input: input(elapsed: 60, sample: sample)), .keep)
        }
        XCTAssertEqual(StreamStallPolicy.decide(enabled: true, waitSeconds: 10, input: input(elapsed: 60, sample: .init(videoWidth: 1920, videoHeight: 0))), .switchStream,
                       "A width without a height is not video")
    }

    func testOnlyAutomaticStartsAreWatched() {
        XCTAssertEqual(StreamStallPolicy.decide(enabled: true, waitSeconds: 10, input: input(elapsed: 60, automatic: false)), .keep,
                       "A source the person picked by hand is left alone, as Desktop's autoFired check does")
    }

    func testLiveEndedOrFailedSourcesAreNotSwitched() {
        XCTAssertEqual(StreamStallPolicy.decide(enabled: true, waitSeconds: 10, input: input(elapsed: 60, sample: .init(live: true))), .keep)
        XCTAssertEqual(StreamStallPolicy.decide(enabled: true, waitSeconds: 10, input: input(elapsed: 60, sample: .init(ended: true))), .keep)
        XCTAssertEqual(StreamStallPolicy.decide(enabled: true, waitSeconds: 10, input: input(elapsed: 60, sample: .init(failed: true))), .keep,
                       "A hard failure already has its own retry chain")
    }

    func testTheAttemptBudgetStopsTheChain() {
        XCTAssertEqual(StreamStallPolicy.maximumAttempts, 8, "Same limit as DetailModel.autoAttemptLimit")
        XCTAssertEqual(StreamStallPolicy.decide(enabled: true, waitSeconds: 10, input: input(elapsed: 60, attempts: 7)), .switchStream)
        XCTAssertEqual(StreamStallPolicy.decide(enabled: true, waitSeconds: 10, input: input(elapsed: 60, attempts: 8)), .keep)
    }

    func testNextCandidatePrefersTheHighestResolutionThenListOrder() {
        let offers = [
            playable(1, tier: "720p", url: "https://a.example/720.mkv"),
            playable(2, tier: "1080p", url: "https://a.example/1080-a.mkv"),
            playable(3, tier: "1080p", url: "https://a.example/1080-b.mkv"),
        ]
        XCTAssertEqual(StreamStallPolicy.nextCandidate(offers, tried: [])?.id, 2)
        XCTAssertEqual(StreamStallPolicy.nextCandidate(offers, tried: [2])?.id, 3)
        XCTAssertEqual(StreamStallPolicy.nextCandidate(offers, tried: [2, 3])?.id, 1)
        XCTAssertNil(StreamStallPolicy.nextCandidate(offers, tried: [1, 2, 3]))
    }

    func testNextCandidateSkipsCopiesOfATriedSourceAndUnplayableOnes() {
        let offers = [
            playable(1, tier: "1080p", url: "https://a.example/same.mkv"),
            playable(2, tier: "1080p", url: "https://a.example/same.mkv"),
            offer(3, ["tier": .string("1080p")]),
            playable(4, tier: "480p", url: "https://a.example/480.mkv"),
        ]
        XCTAssertEqual(StreamStallPolicy.nextCandidate(offers, tried: [1])?.id, 4,
                       "The copy with the same URL and the offer without a playable URL are skipped")
    }

    // MARK: Season source lock

    func testTheLockAppliesToSeriesAndAnimeOnlyWhenEnabled() {
        XCTAssertTrue(SeasonSourceLock.applies(enabled: true, mediaType: "series", metaID: "tt1"))
        XCTAssertTrue(SeasonSourceLock.applies(enabled: true, mediaType: "movie", metaID: "kitsu:9"))
        XCTAssertFalse(SeasonSourceLock.applies(enabled: true, mediaType: "movie", metaID: "tt1"))
        XCTAssertFalse(SeasonSourceLock.applies(enabled: false, mediaType: "series", metaID: "tt1"))
    }

    func testTheLockIsKeptPerSeasonAndAnimeIgnoresTheSeason() {
        let defaults = isolatedDefaults()
        let first = playable(1, tier: "1080p", url: "https://a.example/s2e1.mkv")
        SeasonSourceLock.save(first, metaID: "tt1", season: 2, owner: "profile", defaults: defaults, now: now)
        XCTAssertNotNil(SeasonSourceLock.read(metaID: "tt1", season: 2, owner: "profile", defaults: defaults, now: now))
        XCTAssertNil(SeasonSourceLock.read(metaID: "tt1", season: 3, owner: "profile", defaults: defaults, now: now), "Another season has no lock")
        XCTAssertNil(SeasonSourceLock.read(metaID: "tt1", season: 2, owner: "other", defaults: defaults, now: now), "Another profile has no lock")

        SeasonSourceLock.save(first, metaID: "kitsu:9", season: 3, owner: "profile", defaults: defaults, now: now)
        XCTAssertNotNil(SeasonSourceLock.read(metaID: "kitsu:9", season: 1, owner: "profile", defaults: defaults, now: now),
                        "Anime read the series-wide lock whatever the season")
    }

    func testANewPickReplacesTheLockAndClearRemovesIt() {
        let defaults = isolatedDefaults()
        let old = playable(1, tier: "1080p", url: "https://a.example/old.mkv")
        let new = playable(2, tier: "1080p", url: "https://a.example/new.mkv")
        SeasonSourceLock.save(old, metaID: "tt1", season: 1, owner: "profile", defaults: defaults, now: now)
        SeasonSourceLock.save(new, metaID: "tt1", season: 1, owner: "profile", defaults: defaults, now: now)
        let lock = SeasonSourceLock.read(metaID: "tt1", season: 1, owner: "profile", defaults: defaults, now: now)
        XCTAssertEqual(lock?.url, "https://a.example/new.mkv")
        SeasonSourceLock.clear(metaID: "tt1", season: 1, owner: "profile", defaults: defaults, now: now)
        XCTAssertNil(SeasonSourceLock.read(metaID: "tt1", season: 1, owner: "profile", defaults: defaults, now: now))
    }

    func testTheLockExpiresAfterDesktopsHundredTwentyDayLifetime() {
        let defaults = isolatedDefaults()
        SeasonSourceLock.save(playable(1, tier: "720p", url: "https://a.example/x.mkv"), metaID: "tt1", season: 1, owner: "profile", defaults: defaults, now: now)
        XCTAssertNotNil(SeasonSourceLock.read(metaID: "tt1", season: 1, owner: "profile", defaults: defaults, now: now.addingTimeInterval(119 * 86_400)))
        XCTAssertNil(SeasonSourceLock.read(metaID: "tt1", season: 1, owner: "profile", defaults: defaults, now: now.addingTimeInterval(121 * 86_400)))
    }

    func testTheLockMatchesTheSameTorrentOrBingeGroupOrExactRelease() {
        let saved = offer(1, ["infoHash": .string("ABCDEF"), "fileIdx": .integer(2)])
        let lock = SeasonLockEntry(saved, seriesWide: false, now: now)
        XCTAssertTrue(lock.matches(offer(9, ["infoHash": .string("abcdef"), "fileIdx": .integer(2)])), "Info hashes compare without case")
        XCTAssertTrue(lock.matches(offer(9, ["infoHash": .string("abcdef"), "fileIdx": .integer(5)])),
                      "Desktop's streamMatchesSource compares only the info hash when both have one")

        let bingeLock = SeasonLockEntry(offer(2, ["url": .string("https://a.example/b.mkv"), "behaviorHints": .object(["bingeGroup": .string("group-x")])]), seriesWide: false, now: now)
        XCTAssertTrue(bingeLock.matches(offer(3, ["url": .string("https://b.example/c.mkv"), "behaviorHints": .object(["bingeGroup": .string("group-x")])])))

        let release = SeasonLockEntry(offer(4, ["addonId": .string("addon.one"), "resolution": .string("1080p"), "source": .string("WEB")]), seriesWide: false, now: now)
        XCTAssertTrue(release.matches(offer(5, ["addonId": .string("addon.one"), "resolution": .string("1080p"), "source": .string("WEB")])))
        XCTAssertFalse(release.matches(offer(6, ["addonId": .string("addon.one"), "resolution": .string("720p"), "source": .string("WEB")])))
    }

    func testAPlayableLockedReleaseMovesToTheFrontOtherwiseTheOrderStays() {
        let other = playable(1, tier: "1080p", url: "https://a.example/other.mkv")
        let locked = offer(2, ["tier": .string("720p"), "url": .string("https://a.example/locked.mkv"), "addonId": .string("addon.a"),
                               "resolution": .string("720p"), "source": .string("WEB")])
        let third = playable(3, tier: "480p", url: "https://a.example/third.mkv")
        let lock = SeasonLockEntry(locked, seriesWide: false, now: now)
        XCTAssertEqual(SeasonSourceLock.ordered([other, locked, third], lock: lock).map(\.id), [2, 1, 3])
        XCTAssertEqual(SeasonSourceLock.ordered([other, locked, third], lock: nil).map(\.id), [1, 2, 3])

        let unplayable = offer(2, ["tier": .string("720p"), "infoHash": .string("hash")])
        let stuckLock = SeasonLockEntry(unplayable, seriesWide: false, now: now)
        XCTAssertEqual(SeasonSourceLock.ordered([other, unplayable, third], lock: stuckLock).map(\.id), [1, 2, 3],
                       "A locked release that cannot start now leaves the ranking alone")
    }
}

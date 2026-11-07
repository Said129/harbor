import XCTest
@testable import Harbor

final class ContinueWatchingSettingsTests: XCTestCase {
    private func json(_ name: String) throws -> JSONValue {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
        return try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: url))
    }
    private func superMedia() throws -> Media {
        var source = try XCTUnwrap(Media.parse(json("dbs-source"), kind: "series"))
        let canonical = try XCTUnwrap(Media.parse(json("dbs-canonical"), kind: "series"))
        source.videos = AnimeEpisodeService.applying(try json("dbs-mapping"), canonical: canonical.videos ?? [], to: source.videos ?? [], animeIdentity: false)
        return source
    }
    private func record(offset: Int64 = 323_000) -> LibraryRecord {
        LibraryRecord(raw: .object([
            "_id": .string("tt4644488"), "type": .string("series"), "name": .string("Dragon Ball Super"),
            "removed": .bool(false), "temp": .bool(false), "_mtime": .string("2026-10-17T10:00:00Z"),
            "state": .object(["season": .integer(5), "episode": .integer(23), "video_id": .string("tt4644488:5:23"), "timeOffset": .integer(offset), "duration": .integer(1_400_000)])
        ]))
    }

    func testAdvanceRuleMovesToNextEpisodeOnlyWhenEnabled() {
        XCTAssertTrue(ContinueWatchingAdvance.advances(enabled: true, selectedSeason: 5, selectedEpisode: 24, currentSeason: 5, currentEpisode: 23))
        XCTAssertFalse(ContinueWatchingAdvance.advances(enabled: false, selectedSeason: 5, selectedEpisode: 24, currentSeason: 5, currentEpisode: 23))
    }

    func testAdvanceRuleStaysPutWhenEpisodeMatchesOrCoordinatesAreMissing() {
        XCTAssertFalse(ContinueWatchingAdvance.advances(enabled: true, selectedSeason: 5, selectedEpisode: 23, currentSeason: 5, currentEpisode: 23))
        XCTAssertFalse(ContinueWatchingAdvance.advances(enabled: true, selectedSeason: nil, selectedEpisode: nil, currentSeason: 5, currentEpisode: 23))
        XCTAssertFalse(ContinueWatchingAdvance.advances(enabled: true, selectedSeason: 5, selectedEpisode: 24, currentSeason: nil, currentEpisode: nil))
    }

    func testEnabledCardStillAdvancesFromFinishedEpisode() throws {
        let media = try superMedia()
        let finished = record(offset: 1_390_000)
        let presentation = ContinueWatchingPresentation(record: finished, media: media, watched: [])
        XCTAssertTrue(presentation.upNext)
        XCTAssertEqual(presentation.episode?.id, "tt4644488:5:24")
    }

    func testDisabledCardKeepsFinishedEpisodeAndItsProgress() throws {
        let media = try superMedia()
        let finished = record(offset: 1_390_000)
        let presentation = ContinueWatchingPresentation(record: finished, media: media, watched: [], advanceNext: false)
        XCTAssertFalse(presentation.upNext)
        XCTAssertEqual(presentation.progress, finished.progress)
        XCTAssertEqual(presentation.episode?.id, "tt4644488:5:23")
    }

    /// Dragon Ball fixture trimmed after `lastEpisode` of season 5. `nextReleased` sets the air date of episode 24, when it exists.
    private func caughtUpMedia(lastEpisode: Int, nextReleased: String? = nil) throws -> Media {
        var media = try superMedia()
        var videos: [Episode] = []
        for var episode in media.videos ?? [] where (episode.season ?? 0, episode.episode ?? 0) <= (5, lastEpisode) {
            if episode.season == 5, episode.episode == 24, let nextReleased { episode.released = nextReleased }
            videos.append(episode)
        }
        media.videos = videos
        return media
    }

    func testCaughtUpSeriesLeavesTheRowWhenNothingAfterItIsLeft() throws {
        let presentation = ContinueWatchingPresentation(record: record(offset: 1_390_000), media: try caughtUpMedia(lastEpisode: 23), watched: [])
        XCTAssertTrue(presentation.hidden)
        XCTAssertNil(presentation.airsAt)
    }

    func testCaughtUpSeriesWithAnUnairedNextEpisodeStaysOnlyWhenTheRuleIsOff() throws {
        let media = try caughtUpMedia(lastEpisode: 24, nextReleased: "2999-01-01T00:00:00Z")
        let removed = ContinueWatchingPresentation(record: record(offset: 1_390_000), media: media, watched: [])
        XCTAssertTrue(removed.hidden)
        let kept = ContinueWatchingPresentation(record: record(offset: 1_390_000), media: media, watched: [], hideCaughtUp: false)
        XCTAssertFalse(kept.hidden)
        XCTAssertEqual(kept.episode?.id, "tt4644488:5:23")
    }

    func testTimerKeepsTheCardWaitingUntilTheNextEpisodeAirs() throws {
        let media = try caughtUpMedia(lastEpisode: 24, nextReleased: "2999-01-01T00:00:00Z")
        let airs = try XCTUnwrap(media.videos?.first(where: { $0.season == 5 && $0.episode == 24 })?.releaseDate)
        let waiting = ContinueWatchingPresentation(record: record(offset: 1_390_000), media: media, watched: [], endMode: .timer)
        XCTAssertFalse(waiting.hidden)
        XCTAssertFalse(waiting.upNext)
        XCTAssertEqual(waiting.airsAt, airs)
        let hidden = ContinueWatchingPresentation(record: record(offset: 1_390_000), media: media, watched: [], endMode: .hide)
        XCTAssertTrue(hidden.hidden)
        XCTAssertNil(hidden.airsAt)
    }

    func testReleasedNextEpisodeIsNeverHiddenByCaughtUpRules() throws {
        let presentation = ContinueWatchingPresentation(record: record(offset: 1_390_000), media: try superMedia(), watched: [], hideCaughtUp: true, endMode: .hide)
        XCTAssertTrue(presentation.upNext)
        XCTAssertFalse(presentation.hidden)
    }

    func testCaughtUpOutcomeFollowsDesktopRules() {
        let now = Date(timeIntervalSince1970: 0)
        let later = now.addingTimeInterval(3_600)
        func outcome(finished: Bool = true, advancing: Bool = false, hasNext: Bool = true, airs: Date? = nil, hide: Bool = true, end: ContinueWatchingEnd = .hide) -> ContinueWatchingOutcome {
            ContinueWatchingAdvance.outcome(finished: finished, advancing: advancing, hasNext: hasNext, nextAirDate: airs, now: now, hideCaughtUp: hide, endMode: end)
        }
        XCTAssertEqual(outcome(finished: false, hasNext: false), .show)
        XCTAssertEqual(outcome(advancing: true, hasNext: false), .show)
        XCTAssertEqual(outcome(airs: later, end: .timer), .waiting(later))
        XCTAssertEqual(outcome(airs: later, end: .hide), .hide)
        XCTAssertEqual(outcome(hasNext: true, hide: false), .show)
        XCTAssertEqual(outcome(hasNext: false, hide: false), .hide)
    }

    func testCountdownUsesTheLargestUnitLikeDesktop() {
        let now = Date(timeIntervalSince1970: 0)
        XCTAssertEqual(ContinueWatchingAdvance.countdown(until: now.addingTimeInterval(2 * 86_400 + 3 * 3_600), now: now), .days(2, 3))
        XCTAssertEqual(ContinueWatchingAdvance.countdown(until: now.addingTimeInterval(5 * 3_600 + 10 * 60), now: now), .hours(5, 10))
        XCTAssertEqual(ContinueWatchingAdvance.countdown(until: now.addingTimeInterval(42 * 60), now: now), .minutes(42))
        XCTAssertEqual(ContinueWatchingAdvance.countdown(until: now.addingTimeInterval(10), now: now), .minutes(1))
        XCTAssertEqual(ContinueWatchingAdvance.countdown(until: now.addingTimeInterval(-1), now: now), .airingNow)
    }

    func testEpisodeStillLeadsOnlyWhenPreferredAndTheCardIsNotUpNext() throws {
        var episode = Episode(id: "tt4644488:5:23", season: 5, episode: 23)
        episode.thumbnail = "https://images.example/still.jpg"
        XCTAssertEqual(ContinueWatchingAdvance.stillURL(episode: episode, upNext: false, prefer: true), "https://images.example/still.jpg")
        XCTAssertNil(ContinueWatchingAdvance.stillURL(episode: episode, upNext: false, prefer: false))
        XCTAssertNil(ContinueWatchingAdvance.stillURL(episode: episode, upNext: true, prefer: true))
        XCTAssertNil(ContinueWatchingAdvance.stillURL(episode: nil, upNext: false, prefer: true))
    }
}

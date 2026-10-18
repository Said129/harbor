import XCTest
@testable import Harbor

final class LibraryContinuityTests: XCTestCase {
    func testEarlierViewsDoNotHideTheCurrentSeriesEpisodeOrMovieRewatch() throws {
        let series = try record(#"{"_id":"tt0944947","type":"series","name":"Series","removed":true,"temp":true,"_mtime":"2026-10-10T09:00:00Z","state":{"video_id":"tt0944947:2:3","timeOffset":120000,"duration":3600000,"flaggedWatched":0,"timesWatched":12}}"#)
        XCTAssertTrue(series.continuing, "Desktop's cumulative timesWatched counts earlier episodes")
        XCTAssertEqual(series.resume(for: ResumeTarget(id: series.id, season: 2, episode: 3))?.entry.ms, 120_000)
        XCTAssertNil(series.resume(for: ResumeTarget(id: series.id, season: 2, episode: 2)))

        var fields = series.raw.objectValue
        fields["type"] = .string("movie")
        let movie = LibraryRecord(raw: .object(fields))
        XCTAssertTrue(movie.watched, "Keep the history of previous watches")
        XCTAssertTrue(movie.continuing, "A current rewatch must still appear")
        XCTAssertEqual(movie.resume(for: ResumeTarget(id: movie.id))?.entry.ms, 120_000)
    }

    func testMovieCreditsAreExcludedWhileSeriesKeepTheirCurrentEpisodeLikeDesktop() throws {
        let original = try record(#"{"_id":"tt0133093","type":"movie","name":"Movie","removed":false,"temp":false,"_mtime":"2026-10-10T09:00:00Z","state":{"timeOffset":3240000,"duration":3600000,"flaggedWatched":0}}"#)
        XCTAssertFalse(original.continuing, "Desktop's 90 percent cutoff does not require a manual watched flag")
        XCTAssertEqual(original.resume(for: ResumeTarget(id: original.id))?.entry.ms, 0)

        var fields = original.raw.objectValue
        fields["type"] = .string("series")
        fields["state"] = .object(["video_id": .string(original.id + ":1:1"), "timeOffset": .integer(3_240_000), "duration": .integer(3_600_000), "flaggedWatched": .integer(1)])
        let series = LibraryRecord(raw: .object(fields))
        XCTAssertTrue(series.continuing, "A completed series video remains the anchor for continuing to another episode")
        XCTAssertEqual(series.resume(for: ResumeTarget(id: series.id, season: 1, episode: 1))?.entry.ms, 3_240_000)
        fields["state"] = .object(["timeOffset": .integer(0), "duration": .integer(3_600_000), "flaggedWatched": .integer(1)])
        XCTAssertFalse(LibraryRecord(raw: .object(fields)).continuing, "Desktop writes zero after the finale")
        fields["state"] = original.raw["state"]
        fields["removed"] = .bool(true)
        XCTAssertFalse(LibraryRecord(raw: .object(fields)).continuing, "A removed non-temporary record must not reappear")
    }

    func testAnimeVideoCoordinatesAndNumericCloudDatesAreAcceptedWithoutCrossingEpisodes() throws {
        let anime = try record(#"{"_id":"kitsu:142","type":"anime","name":"Anime","removed":false,"temp":false,"_ctime":1791621000000,"_mtime":1791622800000,"state":{"video_id":"kitsu:142:3","lastWatched":1791621900000,"timeOffset":120000,"duration":1440000,"timesWatched":2}}"#)
        XCTAssertTrue(try XCTUnwrap(anime.media).episodic)
        XCTAssertTrue(anime.continuing)
        XCTAssertEqual(anime.playbackCoordinates.season, 1)
        XCTAssertEqual(anime.playbackCoordinates.episode, 3)
        let resume = try XCTUnwrap(anime.resume(for: ResumeTarget(id: anime.id, season: 1, episode: 3, videoId: "provider-video-3")))
        XCTAssertEqual(resume.entry.ms, 120_000)
        XCTAssertEqual(resume.entry.t, 1_791_621_900_000)
        XCTAssertEqual(anime.activityTimestamp, 1_791_622_800_000)
        XCTAssertNil(anime.resume(for: ResumeTarget(id: anime.id, season: 1, episode: 2)))
        XCTAssertNil(anime.resume(for: ResumeTarget(id: "kitsu:143", season: 1, episode: 3)))

        let older = try record(#"{"_id":"older","type":"movie","name":"Older","_ctime":"2026-01-01T00:00:00Z"}"#)
        XCTAssertEqual(LibraryListing.select([older, anime], display: LibraryDisplay(), query: "").map(\.id), [anime.id, older.id])
        XCTAssertEqual(LibraryRecord.timestamp("1791622800000"), anime.activityTimestamp)
        XCTAssertNil(LibraryRecord.timestamp(JSONValue.number(.infinity)))
        XCTAssertNil(LibraryRecord.timestamp(JSONValue.integer(-1)))
    }

    func testPlayTitleAdvancesPastFinishedEpisodesButKeepsPartialRewatchesAndSpecials() throws {
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-10-10T12:00:00Z"))
        let videos = [Episode(id: "show:2:3", season: 2, episode: 3, released: "2026-11-01T12:00:00Z"), Episode(id: "show:1:2", season: 1, episode: 2), Episode(id: "show:0:1", season: 0, episode: 1), Episode(id: "show:2:2", season: 2, episode: 2), Episode(id: "show:2:1", season: 2, episode: 1)]
        let finished = try record(#"{"_id":"show","type":"series","name":"Series","state":{"video_id":"show:1:2","timeOffset":3240000,"duration":3600000,"timesWatched":2}}"#)
        XCTAssertEqual(EpisodeSequence.startingEpisode(videos, record: finished, watched: ["1:2", "2:1"], now: now)?.id, "show:2:2")
        var media = try XCTUnwrap(finished.media); media.videos = videos
        let presentation = ContinueWatchingPresentation(record: finished, media: media, watched: ["1:2", "2:1"], now: now)
        XCTAssertTrue(presentation.upNext)
        XCTAssertEqual(presentation.episode?.id, "show:2:2")
        XCTAssertEqual(presentation.progress, 0)
        XCTAssertEqual(finished.raw["state"]["video_id"].string, "show:1:2", "The next-episode card must not write fictitious playback to Stremio")
        XCTAssertEqual(EpisodeSequence.startingEpisode(videos, record: finished, watched: ["1:2", "2:1", "2:2"], now: now)?.id, "show:1:2", "Do not select an unaired episode when caught up")
        var fields = finished.raw.objectValue
        fields["state"] = .object(["video_id": .string("show:1:2"), "timeOffset": .integer(120_000), "duration": .integer(3_600_000)])
        XCTAssertEqual(EpisodeSequence.startingEpisode(videos, record: LibraryRecord(raw: .object(fields)), watched: ["1:2"], now: now)?.id, "show:1:2", "A partial rewatch is the resume target even with a historical watched bit")
        fields["state"] = .object(["video_id": .string("show:0:1"), "timeOffset": .integer(3_600_000), "duration": .integer(3_600_000)])
        XCTAssertEqual(EpisodeSequence.startingEpisode(videos, record: LibraryRecord(raw: .object(fields)), watched: ["0:1"], now: now)?.id, "show:0:1")
        XCTAssertEqual(EpisodeSequence.startingEpisode(videos, record: nil, watched: ["1:2"], now: now)?.id, "show:2:1")
    }

    func testCloudPlaybackPreservesProviderFieldsAndResetsThePreviousEpisodeFlag() throws {
        let original = try record(#"{"_id":"show","type":"series","name":"Series","removed":true,"providerField":"preserved","state":{"video_id":"show:1:1","timeOffset":3600000,"timeWatched":3600000,"duration":3600000,"overallTimeWatched":7200000,"timesWatched":3,"flaggedWatched":1,"noNotif":true}}"#)
        var media = try XCTUnwrap(original.media)
        media.videos = [Episode(id: "show:1:1", season: 1, episode: 1), Episode(id: "show:1:2", season: 1, episode: 2)]
        var fields = original.raw.objectValue
        let target = ResumeTarget(id: "show", season: 1, episode: 2)
        try LibraryPlayback.apply(ResumeSnapshot(positionMs: 120_000, durationMs: 3_600_000, timestampMs: 1_791_621_900_000, exiting: false), target: target, media: media, to: &fields)
        let current = LibraryRecord(raw: .object(fields))
        XCTAssertEqual(current.raw["providerField"].string, "preserved")
        XCTAssertEqual(current.raw["state"]["noNotif"], .bool(true))
        XCTAssertEqual(current.raw["temp"], .bool(true))
        XCTAssertEqual(current.raw["state"]["video_id"].string, "show:1:2")
        XCTAssertEqual(current.raw["state"]["flaggedWatched"].numericValue, 0)
        XCTAssertEqual(current.raw["state"]["timesWatched"].numericValue, 3)
        XCTAssertEqual(current.raw["state"]["overallTimeWatched"].numericValue, 10_800_000)
        XCTAssertTrue(current.continuing)
        XCTAssertEqual(current.resume(for: target)?.entry.t, 1_791_621_900_000)

        let finished = ResumeSnapshot(positionMs: 3_300_000, durationMs: 3_600_000, timestampMs: 1_791_622_000_000, exiting: true)
        try LibraryPlayback.apply(finished, target: target, media: media, to: &fields)
        try LibraryPlayback.apply(finished, target: target, media: media, to: &fields)
        let state = JSONValue.object(fields)["state"]
        XCTAssertEqual(state["timesWatched"].numericValue, 4, "Repeated terminal writes must not double-count a finished episode")
        XCTAssertEqual(state["overallTimeWatched"].numericValue, 10_800_000)
        XCTAssertEqual(try WatchedCodec.decode(state["watched"].string, videos: media.videos ?? []), ["1:2"])
    }

    func testStartingOverResetsTheCurrentMovieWithoutDeletingItsHistoryAndRejectsInvalidSnapshots() throws {
        let original = try record(#"{"_id":"movie","type":"movie","name":"Movie","state":{"video_id":"movie","flaggedWatched":1,"timesWatched":2,"duration":3600000,"timeOffset":3500000}}"#)
        let media = try XCTUnwrap(original.media)
        let target = ResumeTarget(id: media.id)
        var fields = original.raw.objectValue
        try LibraryPlayback.apply(ResumeSnapshot(positionMs: 0, durationMs: 3_600_000, timestampMs: 1_791_621_900_000, exiting: true), target: target, media: media, to: &fields)
        XCTAssertEqual(JSONValue.object(fields)["state"]["flaggedWatched"].numericValue, 0)
        XCTAssertEqual(JSONValue.object(fields)["state"]["timesWatched"].numericValue, 2)
        let preserved = fields
        XCTAssertThrowsError(try LibraryPlayback.apply(ResumeSnapshot(positionMs: .nan, durationMs: 0, timestampMs: 1, exiting: true), target: target, media: media, to: &fields))
        XCTAssertThrowsError(try LibraryPlayback.apply(ResumeSnapshot(positionMs: 0, durationMs: 0, timestampMs: 1, exiting: true), target: ResumeTarget(id: "other"), media: media, to: &fields))
        XCTAssertEqual(fields, preserved)
    }

    private func record(_ source: String) throws -> LibraryRecord {
        LibraryRecord(raw: try JSONDecoder().decode(JSONValue.self, from: Data(source.utf8)))
    }
}

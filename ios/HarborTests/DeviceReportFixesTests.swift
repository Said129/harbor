import Foundation
import XCTest
@testable import Harbor

/// Fixes that came from using the build on a phone: downloads with no visible progress, a music bar that would not stay
/// closed, and episodes locked behind "Próximamente".
final class DownloadProgressPresentationTests: XCTestCase {
    private let started = Date(timeIntervalSince1970: 1_000_000)

    func testNothingReceivedSaysItIsConnectingAndHintsAfterThirtySeconds() {
        let early = DownloadProgressPresentation.make(received: 0, expected: 0, paused: false, bytesPerSecond: nil, started: started, now: started.addingTimeInterval(5))
        XCTAssertEqual(early.phase, .connecting)
        XCTAssertNil(early.fraction)
        XCTAssertEqual(early.headline, "Conectando con la fuente…")
        XCTAssertNil(early.hint)
        let late = DownloadProgressPresentation.make(received: 0, expected: 0, paused: false, bytesPerSecond: nil, started: started, now: started.addingTimeInterval(31))
        XCTAssertNotNil(late.hint, "A source that stays silent tells the person to try another")
    }

    func testAKnownSizeGivesAPercentageSpeedAndTimeLeft() {
        let value = DownloadProgressPresentation.make(received: 250_000_000, expected: 1_000_000_000, paused: false, bytesPerSecond: 5_000_000, started: started, now: started.addingTimeInterval(60))
        XCTAssertEqual(value.phase, .sized)
        XCTAssertEqual(try XCTUnwrap(value.fraction), 0.25, accuracy: 0.0001)
        XCTAssertTrue(value.headline.hasSuffix("25 %"), value.headline)
        XCTAssertTrue(value.detail.contains("/s"), "The speed is shown: \(value.detail)")
        XCTAssertGreaterThanOrEqual(value.detail.components(separatedBy: " · ").count, 3, "Size, speed and time left: \(value.detail)")
        XCTAssertNil(value.hint)
    }

    func testAnUnknownTotalStillShowsTheBytesThatArrived() {
        let value = DownloadProgressPresentation.make(received: 40_000_000, expected: 0, paused: false, bytesPerSecond: nil, started: started, now: started.addingTimeInterval(20))
        XCTAssertEqual(value.phase, .unsized)
        XCTAssertNil(value.fraction)
        XCTAssertTrue(value.detail.contains("descargados"), value.detail)
        XCTAssertNotNil(value.hint, "The person is told why there is no percentage")
    }

    func testAPausedDownloadShowsItsPercentageWithoutASpeed() {
        let value = DownloadProgressPresentation.make(received: 500, expected: 1_000, paused: true, bytesPerSecond: 9_999, started: started, now: started.addingTimeInterval(9))
        XCTAssertEqual(value.phase, .paused)
        XCTAssertTrue(value.headline.contains("50 %"), value.headline)
        XCTAssertFalse(value.detail.contains("/s"))
    }

    func testReceivingMoreThanExpectedNeverPassesOneHundredPercent() {
        let value = DownloadProgressPresentation.make(received: 2_000, expected: 1_000, paused: false, bytesPerSecond: nil, started: started, now: started)
        XCTAssertEqual(try XCTUnwrap(value.fraction), 1, accuracy: 0.0001)
    }

    func testTheTaskExpectationStandsInWhenTheServerReportsNoLength() {
        XCTAssertEqual(DownloadProgressPresentation.expectedBytes(reported: 800, taskExpectation: 900), 800)
        XCTAssertEqual(DownloadProgressPresentation.expectedBytes(reported: -1, taskExpectation: 900), 900)
        XCTAssertEqual(DownloadProgressPresentation.expectedBytes(reported: -1, taskExpectation: -1), 0)
    }

    func testSpeedNeedsTwoReadingsASecondApartAndIsSmoothed() {
        XCTAssertNil(DownloadProgressPresentation.smoothedSpeed(previous: nil, bytes: 100, lastBytes: 0, seconds: 0.4))
        XCTAssertEqual(try XCTUnwrap(DownloadProgressPresentation.smoothedSpeed(previous: nil, bytes: 2_000, lastBytes: 0, seconds: 2)), 1_000, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(DownloadProgressPresentation.smoothedSpeed(previous: 1_000, bytes: 3_000, lastBytes: 1_000, seconds: 1)), 1_400, accuracy: 0.001)
    }
}

final class EpisodeUpcomingTests: XCTestCase {
    private func episode(hoursAhead: Double, now: Date) -> Episode {
        Episode(id: "show:2:3", season: 2, episode: 3, released: ISO8601DateFormatter().string(from: now.addingTimeInterval(hoursAhead * 3_600)))
    }

    func testAnEpisodeThatAiredTodayIsNotUpcomingEvenIfItsDateIsAFewHoursAhead() throws {
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-11-14T10:00:00Z"))
        let today = episode(hoursAhead: 9, now: now)
        XCTAssertFalse(today.comingSoon(now: now), "A midnight UTC date can sit hours ahead of the phone's clock")
        XCTAssertTrue(today.available)
    }

    func testOnlyADateMoreThanADayAwayIsLabelledUpcoming() throws {
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-11-14T10:00:00Z"))
        XCTAssertFalse(episode(hoursAhead: 23, now: now).comingSoon(now: now))
        XCTAssertTrue(episode(hoursAhead: 49, now: now).comingSoon(now: now))
        XCTAssertFalse(Episode(id: "x", season: 1, episode: 1).comingSoon(now: now), "No date means nothing to wait for")
    }

    func testTheStartingEpisodeIncludesOneThatAiredTodayAndSkipsOneWeeksAway() throws {
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-11-14T10:00:00Z"))
        let videos = [Episode(id: "show:2:2", season: 2, episode: 2, released: "2026-11-07T00:00:00Z"), episode(hoursAhead: 9, now: now),
                      Episode(id: "show:2:4", season: 2, episode: 4, released: "2026-12-01T00:00:00Z")]
        let target = ResumeTarget(id: "show", season: 2, episode: 2, videoId: "show:2:2")
        XCTAssertEqual(EpisodeSequence.adjacent(videos, current: target, now: now).next?.id, "show:2:3")
        let after = ResumeTarget(id: "show", season: 2, episode: 3, videoId: "show:2:3")
        XCTAssertNil(EpisodeSequence.adjacent(videos, current: after, now: now).next, "An episode weeks away is still not queued automatically")
    }
}

private actor RecordingSessionStore: MusicSessionPersisting {
    private(set) var cleared: [String] = []
    func read(owner: String) async throws -> MusicSessionSnapshot? { nil }
    func write(_ value: MusicSessionSnapshot, owner: String) async throws { }
    func clear(owner: String) async throws { cleared.append(owner) }
}

@MainActor private final class ClosedSessionResolver: MusicPlaybackResolving {
    let scope: PluginExecutionScope
    init(owner: String) { scope = .init(owner: owner, activation: UUID()) }
    func validate() throws { }
    func localRecord(_ track: MusicTrack) -> MusicRecord? { nil }
    func resolve(_ track: MusicTrack) async throws -> MusicPlaybackResolution { throw CancellationError() }
    func scrobble(_ track: MusicTrack, startedAt: UInt64) async throws { }
}

@MainActor final class MusicSessionCloseTests: XCTestCase {
    private func track(_ id: String) -> MusicTrack {
        .init(id: id, connectorId: "subsonic", sourceId: id, playbackUrl: nil, title: "Owned " + id, artist: "Owned Artist", album: "Owned Album",
              artwork: "", durationSeconds: 8, durationLabel: "0:08")
    }
    private func snapshot(_ song: MusicTrack) -> MusicSessionSnapshot {
        MusicSessionSnapshot(revision: UUID(), queue: [song], current: song, origin: nil, position: 3, savedAt: Date())
    }
    private func wait(_ predicate: @MainActor () -> Bool) async throws {
        for _ in 0..<250 { if predicate() { return }; try await Task.sleep(for: .milliseconds(20)) }
        XCTFail("The restored session did not settle"); throw HarborError(code: "owned-close-timeout")
    }

    func testTheFileStoreForgetsASavedSession() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("owned-session-clear-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = MusicSessionFileStore(directory: directory), owner = "owned-clear-" + UUID().uuidString
        try await store.write(snapshot(track("one")), owner: owner)
        let saved = try await store.read(owner: owner)
        XCTAssertNotNil(saved)
        try await store.clear(owner: owner)
        let cleared = try await store.read(owner: owner)
        XCTAssertNil(cleared, "A cleared session does not come back")
        try await store.clear(owner: owner)
    }

    func testClosingThePlayerForgetsTheSessionButStoppingKeepsIt() async throws {
        let owner = "owned-close-" + UUID().uuidString
        let resolver = ClosedSessionResolver(owner: owner)
        let song = track("restored")

        let keeping = RecordingSessionStore()
        let stopped = MusicPlayback(engine: MusicAudioEngine(), systemIntegration: false, recordPlayed: { _, _ in }, checkpoints: keeping)
        stopped.attach(resolver, restoring: snapshot(song))
        try await wait { stopped.currentItem != nil }
        stopped.stop(); await stopped.flushCheckpoint()
        let keptCalls = await keeping.cleared
        XCTAssertTrue(keptCalls.isEmpty, "Stopping for another reason leaves the saved session alone")

        let forgetting = RecordingSessionStore()
        let closed = MusicPlayback(engine: MusicAudioEngine(), systemIntegration: false, recordPlayed: { _, _ in }, checkpoints: forgetting)
        closed.attach(resolver, restoring: snapshot(song))
        try await wait { closed.currentItem != nil }
        closed.close(); await closed.flushCheckpoint()
        XCTAssertNil(closed.currentItem, "Closing removes the mini player's track")
        let calls = await forgetting.cleared
        XCTAssertEqual(calls, [owner], "Closing forgets the saved session so the bar does not return after a restart")
    }

    func testTheMiniPlayerShowsOnlyInTheMusicSection() {
        for section in HarborSection.allCases {
            XCTAssertEqual(MusicMiniPlayerVisibility.shows(in: section), section == .music, "\(section)")
        }
    }
}

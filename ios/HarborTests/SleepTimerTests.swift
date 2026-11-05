import XCTest
@testable import Harbor

/// Desktop's sleep timer (`use-sleep-timer.ts`, speed menu presets).
@MainActor final class SleepTimerTests: XCTestCase {
    func testEndOfEpisodeStopsOnceAndClears() {
        let timer = SleepTimer()
        timer.set(.endEpisode)
        XCTAssertTrue(timer.isActive)
        XCTAssertTrue(timer.episodeEnded(), "The episode that ends under 'end of episode' stops playback")
        XCTAssertEqual(timer.mode, .off)
        XCTAssertFalse(timer.episodeEnded(), "Nothing waits afterwards")
    }

    func testEndOfNextEpisodeLetsTheFirstOneContinue() {
        let timer = SleepTimer()
        timer.set(.endNextEpisode(remaining: 2))
        XCTAssertFalse(timer.episodeEnded(), "The current episode ends and the next one starts")
        XCTAssertEqual(timer.mode, .endNextEpisode(remaining: 1))
        XCTAssertTrue(timer.episodeEnded(), "The next episode is the last")
        XCTAssertEqual(timer.mode, .off)
    }

    func testMinutesTimerCountsDownAndCancels() {
        let timer = SleepTimer()
        timer.set(.minutes(30))
        XCTAssertEqual(timer.remaining() ?? 0, 1_800, accuracy: 2)
        XCTAssertEqual(timer.remaining(at: Date().addingTimeInterval(3_600)), 0, "Past the deadline nothing is left")
        XCTAssertFalse(timer.episodeEnded(), "A minutes timer ignores episode ends")
        timer.cancel()
        XCTAssertNil(timer.remaining())
        XCTAssertFalse(timer.isActive)
        timer.set(.off)
        XCTAssertFalse(timer.isActive, "Setting Off is cancelling")
    }

    func testMinutesTimerFiresTheHandlerOnce() async throws {
        let timer = SleepTimer()
        var fired = 0
        timer.onFire = { fired += 1 }
        timer.set(.minutes(1))
        timer.cancel()
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(fired, 0, "A cancelled timer never fires")
        timer.set(.endEpisode); timer.fire()
        XCTAssertEqual(fired, 0, "Only a minutes timer fires the handler")
        timer.set(.minutes(5)); timer.fire()
        XCTAssertEqual(fired, 1)
        XCTAssertFalse(timer.isActive, "A timer that fired is spent")
        timer.fire()
        XCTAssertEqual(fired, 1, "Nothing fires twice")
    }

    func testAnotherVideoDropsOnlyTheEndOfEpisodeMode() {
        let timer = SleepTimer()
        timer.set(.endEpisode); timer.videoChanged()
        XCTAssertEqual(timer.mode, .off)
        timer.set(.endNextEpisode(remaining: 2)); timer.videoChanged()
        XCTAssertEqual(timer.mode, .endNextEpisode(remaining: 2), "The count spans the episode change")
        timer.set(.minutes(15)); timer.videoChanged()
        XCTAssertEqual(timer.mode, .minutes(15))
    }

    func testCountdownAndMinuteLabels() {
        XCTAssertEqual(SleepTimer.countdown(125), "2:05")
        XCTAssertEqual(SleepTimer.countdown(0), "0:00")
        XCTAssertEqual(SleepTimer.countdown(-4), "0:00")
        XCTAssertEqual(SleepTimer.countdown(3_599.6), "60:00")
    }

    func testCustomMinutesAreValidatedSortedAndRemovable() throws {
        let suite = "harbor.sleep-timer.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertEqual(SleepTimer.customMinutes(defaults), [])
        XCTAssertFalse(SleepTimer.addCustom(30, defaults), "30 is already a fixed preset")
        XCTAssertFalse(SleepTimer.addCustom(60, defaults), "1 hour is already a fixed preset")
        XCTAssertFalse(SleepTimer.addCustom(0, defaults)); XCTAssertFalse(SleepTimer.addCustom(1_441, defaults))
        XCTAssertTrue(SleepTimer.addCustom(90, defaults)); XCTAssertTrue(SleepTimer.addCustom(20, defaults))
        XCTAssertFalse(SleepTimer.addCustom(20, defaults), "No duplicates")
        XCTAssertEqual(SleepTimer.customMinutes(defaults), [20, 90])
        SleepTimer.removeCustom(20, defaults)
        XCTAssertEqual(SleepTimer.customMinutes(defaults), [90])
        XCTAssertEqual(SleepTimer.presets.map(\.id), ["15", "30", "45", "60", "120", "180", "240", "360", "ep", "ep2"], "Desktop's ten presets")
    }
}

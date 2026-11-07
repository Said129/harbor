import XCTest
@testable import Harbor

/// Desktop's live auto-reconnect rules (`use-auto-retry.ts` lines 135-162): schedule, give-up and reset,
/// driven by a manual clock and fake player closures.
@MainActor
final class LiveReconnectTests: XCTestCase {
    @MainActor
    private final class FakeChannel {
        var now: TimeInterval = 0
        var stalled = false
        var reopenCount = 0
    }

    private func makeController(_ channel: FakeChannel, policy: LiveReconnectPolicy = .desktop) -> LiveReconnectController {
        LiveReconnectController(
            policy: policy,
            now: { channel.now },
            isStalled: { channel.stalled },
            reopen: { channel.reopenCount += 1 }
        )
    }

    func testDecisionBeforeProgressAllowsOneReconnectAt1500Ms() {
        let policy = LiveReconnectPolicy.desktop
        XCTAssertEqual(policy.decision(attemptsMade: 0, livePlayed: false), .reconnect(attempt: 1, delayMs: 1_500))
        XCTAssertEqual(policy.decision(attemptsMade: 1, livePlayed: false), .giveUp)
    }

    func testDecisionAfterProgressAllowsTwoReconnectsAt4000Ms() {
        let policy = LiveReconnectPolicy.desktop
        XCTAssertEqual(policy.decision(attemptsMade: 0, livePlayed: true), .reconnect(attempt: 1, delayMs: 4_000))
        XCTAssertEqual(policy.decision(attemptsMade: 1, livePlayed: true), .reconnect(attempt: 2, delayMs: 4_000))
        XCTAssertEqual(policy.decision(attemptsMade: 2, livePlayed: true), .giveUp)
    }

    func testHasProgressThresholdsAreStrictlyAboveHalfASecond() {
        XCTAssertFalse(LiveReconnectPolicy.hasProgress(positionSeconds: 0.5, bufferedSeconds: 0))
        XCTAssertTrue(LiveReconnectPolicy.hasProgress(positionSeconds: 0.6, bufferedSeconds: 0))
        XCTAssertTrue(LiveReconnectPolicy.hasProgress(positionSeconds: 0, bufferedSeconds: 0.6))
        XCTAssertFalse(LiveReconnectPolicy.hasProgress(positionSeconds: 0, bufferedSeconds: 0.5))
    }

    func testDropReconnectFiresOnceAfterTheDelay() {
        let channel = FakeChannel()
        let controller = makeController(channel)
        channel.stalled = true
        controller.poll()
        XCTAssertEqual(controller.dueAt, 1.5)
        channel.now = 1.4
        controller.poll()
        XCTAssertEqual(channel.reopenCount, 0)
        channel.now = 1.5
        controller.poll()
        XCTAssertEqual(channel.reopenCount, 1)
        XCTAssertEqual(controller.attemptsMade, 1)
        XCTAssertNil(controller.dueAt)
        channel.now = 10
        controller.poll()
        XCTAssertEqual(channel.reopenCount, 1, "A persistent error must not re-trigger without a recovery first")
    }

    func testPlayedChannelWaitsFourSecondsBeforeReconnecting() {
        let channel = FakeChannel()
        let controller = makeController(channel)
        controller.noteProgress(positionSeconds: 1.0, bufferedSeconds: 0)
        XCTAssertTrue(controller.livePlayed)
        channel.stalled = true
        controller.poll()
        XCTAssertEqual(controller.dueAt, 4.0)
        channel.now = 3.9
        controller.poll()
        XCTAssertEqual(channel.reopenCount, 0)
        channel.now = 4.0
        controller.poll()
        XCTAssertEqual(channel.reopenCount, 1)
    }

    func testFailedReconnectThenAnotherDropGivesUpWithoutReopening() {
        let channel = FakeChannel()
        let controller = makeController(channel)
        channel.stalled = true
        controller.poll()
        channel.now = 1.5
        controller.poll()
        XCTAssertEqual(channel.reopenCount, 1)
        channel.stalled = false
        controller.poll()
        channel.now = 2.0
        channel.stalled = true
        controller.poll()
        XCTAssertTrue(controller.gaveUp)
        XCTAssertNil(controller.dueAt)
        channel.now = 60
        controller.poll()
        XCTAssertEqual(channel.reopenCount, 1)
    }

    func testRecoveryBeforeTheDueTimeCancelsThePendingReconnect() {
        let channel = FakeChannel()
        let controller = makeController(channel)
        channel.stalled = true
        controller.poll()
        XCTAssertNotNil(controller.dueAt)
        channel.now = 1.0
        channel.stalled = false
        controller.poll()
        XCTAssertNil(controller.dueAt)
        channel.now = 5.0
        controller.poll()
        XCTAssertEqual(channel.reopenCount, 0)
    }

    func testRecoveredStreamKeepsTheAttemptCounter() {
        let channel = FakeChannel()
        let controller = makeController(channel)
        channel.stalled = true
        controller.poll()
        channel.now = 1.5
        controller.poll()
        channel.stalled = false
        controller.poll()
        XCTAssertEqual(controller.attemptsMade, 1, "Desktop resets the counter only on a URL change, not on recovery")
    }

    func testPlayedChannelGetsASecondReconnectThenGivesUp() {
        let channel = FakeChannel()
        let controller = makeController(channel)
        controller.noteProgress(positionSeconds: 2.0, bufferedSeconds: 0)
        channel.stalled = true
        controller.poll()
        channel.now = 4.0
        controller.poll()
        XCTAssertEqual(channel.reopenCount, 1)
        channel.stalled = false
        controller.poll()
        channel.now = 5.0
        channel.stalled = true
        controller.poll()
        XCTAssertEqual(controller.dueAt, 9.0)
        channel.now = 9.0
        controller.poll()
        XCTAssertEqual(channel.reopenCount, 2)
        channel.stalled = false
        controller.poll()
        channel.now = 10.0
        channel.stalled = true
        controller.poll()
        XCTAssertTrue(controller.gaveUp)
        XCTAssertEqual(channel.reopenCount, 2)
    }

    func testResetClearsCounterPlayedFlagAndGiveUp() {
        let channel = FakeChannel()
        let controller = makeController(channel)
        controller.noteProgress(positionSeconds: 2.0, bufferedSeconds: 0)
        channel.stalled = true
        controller.poll()
        channel.now = 4.0
        controller.poll()
        channel.stalled = false
        controller.poll()
        controller.reset()
        XCTAssertEqual(controller.attemptsMade, 0)
        XCTAssertFalse(controller.livePlayed)
        XCTAssertFalse(controller.gaveUp)
        channel.now = 20.0
        channel.stalled = true
        controller.poll()
        XCTAssertEqual(controller.dueAt, 21.5, "After a reset the channel is treated as never played again")
    }
}

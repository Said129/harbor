import XCTest
@testable import Harbor

@MainActor final class SubtitleDriftMonitorTests: XCTestCase {
    func testBundledMonitorProducesStableOfferAndAppliesOnlyAfterNativeAcceptance() throws {
        let monitor = try SubtitleDriftMonitor()
        let cues = makeCues()
        let initial = snapshot(position: 100, now: 100_000, cues: cues)
        XCTAssertEqual(try monitor.reset(initial).status, "watching")

        var result = try feedSample(monitor, snapshot: snapshot(position: 100, now: 101_000))
        XCTAssertNil(result.correction)
        result = try feedSample(monitor, snapshot: snapshot(position: 120, now: 121_000))
        XCTAssertNil(result.correction)
        result = try feedSample(monitor, snapshot: snapshot(position: 140, now: 141_000))

        let offer = try XCTUnwrap(result.correction)
        XCTAssertEqual(result.status, "offer")
        XCTAssertEqual(offer.residualSec, 0.8, accuracy: 0.1)
        XCTAssertEqual(offer.stepSec, 0.68, accuracy: 0.1)
        XCTAssertGreaterThan(offer.pCorrect, 0.65)
        XCTAssertNil(result.appliedDelaySec, "The provisional calibration gate must not auto-apply drift")

        let accepted = try monitor.applyPending(snapshot(position: 144, now: 145_000))
        XCTAssertEqual(try XCTUnwrap(accepted.correction).stepSec, offer.stepSec, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(accepted.appliedDelaySec), offer.stepSec, accuracy: 0.001)
        XCTAssertEqual(accepted.correctionTotalSec, offer.stepSec, accuracy: 0.001)
    }

    func testSeekAndIdentityChangesDiscardLateSampleAndSeekPreservesAppliedCap() throws {
        let monitor = try SubtitleDriftMonitor()
        let cues = makeCues()
        _ = try monitor.reset(snapshot(position: 100, now: 100_000, cues: cues))
        _ = try feedSample(monitor, snapshot: snapshot(position: 100, now: 101_000))
        _ = try feedSample(monitor, snapshot: snapshot(position: 120, now: 121_000))
        let offered = try feedSample(monitor, snapshot: snapshot(position: 140, now: 141_000))
        let offer = try XCTUnwrap(offered.correction)
        let applied = try monitor.applyPending(snapshot(position: 144, now: 145_000))
        let delay = try XCTUnwrap(applied.appliedDelaySec)

        let pendingSnapshot = snapshot(position: 164, now: 165_000, delay: delay)
        let pendingState = try monitor.observe(pendingSnapshot)
        let pendingRequest = try XCTUnwrap(pendingState.sampleRequest)
        let seek = snapshot(position: 80, now: 166_000, delay: delay)
        let afterSeek = try monitor.reset(seek, reason: .seek)
        XCTAssertNil(afterSeek.sampleRequest)
        XCTAssertNil(afterSeek.correction)
        XCTAssertEqual(afterSeek.correctionTotalSec, offer.stepSec, accuracy: 0.001)
        XCTAssertFalse(try monitor.completeSpeech(
            requestID: pendingRequest.id,
            intervals: [SubtitleDriftInterval(startSec: 80, endSec: 81)],
            currentSnapshot: seek
        ), "A result from before the seek must be discarded")

        let nextTrack = snapshot(position: 0, now: 167_000, key: "file-2|sub-1|audio-1", cues: cues)
        let afterIdentityChange = try monitor.reset(nextTrack, reason: .identity)
        XCTAssertNil(afterIdentityChange.sampleRequest)
        XCTAssertNil(afterIdentityChange.correction)
        XCTAssertEqual(afterIdentityChange.correctionTotalSec, 0)
    }

    func testRejectedSpeechRequestIsClearedAfterDrain() throws {
        let monitor = try SubtitleDriftMonitor()
        _ = try monitor.reset(snapshot(position: 100, now: 100_000, cues: makeCues()))
        let observed = try monitor.observe(snapshot(position: 100, now: 101_000))
        let request = try XCTUnwrap(observed.sampleRequest)
        XCTAssertTrue(try monitor.rejectSpeech(requestID: request.id))
        let drained = try monitor.drain(snapshot(position: 100, now: 101_000))
        XCTAssertNil(drained.sampleRequest)
        XCTAssertNil(drained.correction)
        XCTAssertNotEqual(drained.status, "sampling")
    }

    private func feedSample(
        _ monitor: SubtitleDriftMonitor,
        snapshot: SubtitleDriftSnapshot
    ) throws -> SubtitleDriftMonitorState {
        let observed = try monitor.observe(snapshot)
        let request = try XCTUnwrap(observed.sampleRequest)
        let end = request.startSec + request.lenSec
        let intervals = makeCues()
            .filter { $0.endSec >= request.startSec - 2.5 && $0.startSec <= end + 2.5 }
            .map { SubtitleDriftInterval(startSec: $0.startSec + 0.8, endSec: $0.endSec + 0.8) }
        XCTAssertTrue(try monitor.completeSpeech(requestID: request.id, intervals: intervals, currentSnapshot: snapshot))
        return try monitor.drain(snapshot)
    }

    private func snapshot(
        position: Double,
        now: Double,
        key: String = "file-1|sub-1|audio-1",
        delay: Double = 0,
        cues: [SubtitleDriftCue]? = nil
    ) -> SubtitleDriftSnapshot {
        SubtitleDriftSnapshot(
            trackKey: key,
            positionSec: position,
            durationSec: 600,
            subDelaySec: delay,
            playing: true,
            buffering: false,
            rate: 1,
            cues: cues,
            nowMs: now
        )
    }

    private func makeCues() -> [SubtitleDriftCue] {
        let gaps = [4.3, 6.1, 3.2, 7.4, 5.0, 3.9, 8.2, 4.7, 6.6, 3.5, 5.8, 7.1]
        var time = 5.0
        return (0..<80).map { index in
            let start = time
            let duration = 1 + Double(index % 4) * 0.3
            time += duration + gaps[index % gaps.count]
            return SubtitleDriftCue(startSec: start, endSec: start + duration)
        }
    }
}

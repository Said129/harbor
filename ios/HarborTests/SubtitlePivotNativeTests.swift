import XCTest
@testable import Harbor

final class SubtitlePivotNativeTests: XCTestCase {
    func testBundledPivotRequestsNativeEvidenceAndOffersInsteadOfApplying() async throws {
        let workflow = try SubtitlePivotWorkflow()
        let offsets = [0.0, 0.6, 1.2, 0.1, 0.8, 1.5, 0.2, 0.9]
        let target = (0..<40).map { index -> SubtitlePivotCue in
            let start = 30 + Double(index * 14) + offsets[index % offsets.count]
            return .init(start: start, end: start + 1.2 + Double(index % 4) * 0.15, text: "Owned example of a caption \(index)")
        }
        let pivot = target.enumerated().map { index, cue in
            SubtitlePivotCue(start: cue.start + 1.5, end: cue.end + 1.5, text: "Reference dialogue sample \(index)")
        }
        let input = SubtitlePivotWorkflowInput(audioLanguage: "en", subtitleLanguage: "es", targetCues: target,
            targetHealthy: true, targetFormatSafe: true, calibrationReady: false, maxCandidates: 1)
        let candidate: JSONValue = .object(["id": .string("owned"), "language": .string("en"), "exactRelease": .bool(true),
                                            "releaseScore": .number(1), "source": .string("owned")])

        let first = try await workflow.start(input)
        let retired = try XCTUnwrap(first.request)
        _ = try await workflow.cancel()
        let acceptedRetired = try await workflow.complete(requestID: retired.id, result: .array([candidate]))
        XCTAssertFalse(acceptedRetired)

        var state = try await workflow.start(input)
        state = try await complete(workflow, state, operation: "searchPivotCandidates", result: .array([candidate]))
        state = try await complete(workflow, state, operation: "preparePivotCandidate",
                                   result: .object(["cues": try .encoded(pivot), "healthy": .bool(true), "formatSafe": .bool(true)]))
        let nativePivot: JSONValue = .object(["validated": .bool(true), "transform": SubtitlePivotTransform.affine(offset: 0, ratio: 1),
                                             "score": .number(0.9), "coverage": .number(0.9)])
        state = try await complete(workflow, state, operation: "validatePivotAgainstAudio", result: nativePivot)
        XCTAssertGreaterThanOrEqual(state.request?.payload["heldOutWindows"].array.count ?? 0, 3)
        let nativeTarget: JSONValue = .object(["qualityBefore": .number(0.4), "qualityAfter": .number(0.92), "coverage": .number(0.9),
                                               "heldOutAudioMeasured": .bool(true)])
        state = try await complete(workflow, state, operation: "validateTargetAgainstAudio", result: nativeTarget)
        XCTAssertEqual(state.status, "completed")
        let result = try XCTUnwrap(state.result)
        XCTAssertEqual(result["decision"]["decision"].string, "offer")
        XCTAssertEqual(try XCTUnwrap(result["transform"]["offsetSec"].numericValue), 1.5, accuracy: 0.05)
    }

    func testBundledReleaseMatcherDistinguishesTheSameReleaseFromTheWrongEpisode() async throws {
        let workflow = try SubtitlePivotWorkflow()
        let release = "Owned.Show.S01E02.1080p.WEB-DL.DDP5.1.H.264-Example"
        let hints: JSONValue = .object(["release": .string(release), "season": .integer(1), "episode": .integer(2)])
        let result = try await workflow.releaseConfidences(hints: hints, subtitleTexts: [
            release, "Owned.Show.S01E03.1080p.BluRay-Other", "",
        ])
        XCTAssertEqual(result, ["high", "incompatible", "low"])
    }

    private func complete(_ workflow: SubtitlePivotWorkflow, _ state: SubtitlePivotWorkflowState, operation: String,
                          result: JSONValue) async throws -> SubtitlePivotWorkflowState {
        let request = try XCTUnwrap(state.request)
        XCTAssertEqual(request.operation, operation)
        let accepted = try await workflow.complete(requestID: request.id, result: result)
        XCTAssertTrue(accepted)
        return try await workflow.drain()
    }

    func testFitAndHeldOutWindowsStayIndependentAndRejectInvalidRequests() {
        let fit = SubtitlePivotAudio.fitWindows(duration: 1_200)
        XCTAssertEqual(fit.map(\.id), ["fit-early", "fit-late"])
        let heldOut = SubtitlePivotAudio.middleWindows(duration: 1_200, excluding: fit)
        XCTAssertEqual(heldOut.map(\.id), ["validation-middle-a", "validation-middle-b"])
        XCTAssertFalse(heldOut.contains { window in fit.contains(where: window.overlaps) })
        XCTAssertTrue(SubtitlePivotAudio.middleWindows(duration: 299, excluding: []).isEmpty)
        XCTAssertNil(SubtitlePivotAudio.verified([heldOut[0], heldOut[0]], duration: 1_200))
        let overlapping = SubtitlePivotAudio.Window(id: "overlap", start: fit[0].start, end: fit[0].end)
        XCTAssertNil(SubtitlePivotAudio.verified([overlapping], duration: 1_200, excluding: fit))
    }

    func testHeldOutScoringComparesBothHypothesesOnTheSameWindows() throws {
        let windows = [
            SubtitlePivotAudio.Window(id: "owned-a", start: 50, end: 70),
            SubtitlePivotAudio.Window(id: "owned-b", start: 90, end: 110),
        ]
        let cues: [SubtitlePivotAudio.Interval] = [(52, 53), (58, 60), (93, 94), (102, 104)]
        let speech = cues + [(start: 74, end: 85)]
        let aligned = try XCTUnwrap(SubtitlePivotAudio.quality(speech: speech, cues: cues, windows: windows))
        let shifted = cues.map { (start: $0.start + 3, end: $0.end + 3) }
        let misaligned = try XCTUnwrap(SubtitlePivotAudio.quality(speech: speech, cues: shifted, windows: windows))
        XCTAssertEqual(aligned.ncc, 1, accuracy: 0.00001)
        XCTAssertEqual(aligned.coverage, 1, accuracy: 0.00001)
        XCTAssertEqual(misaligned.ncc, 0)
        XCTAssertNil(try SubtitlePivotAudio.quality(speech: [(74, 85)], cues: cues, windows: windows))
    }

    func testPiecewiseRewriteKeepsMarkupAndUsesOneSegmentForEachCue() throws {
        let raw = [
            "WEBVTT", "", "opening", "00:01.000 --> 00:03.000 line:20%", "<i>Owned</i> &amp; text", "Second line",
            "", "00:04.000 --> 00:05.000", "Second cue", "", "00:06.000 --> 00:07.000", "Third cue",
            "", "00:08.000 --> 00:09.000", "Fourth cue",
        ].joined(separator: "\r\n")
        let document = try SubtitleDocument(raw)
        let cues = try document.structuralCues()
        XCTAssertEqual(cues.count, 4)
        XCTAssertEqual(cues[0].text, "Owned & text\nSecond line")
        let input: JSONValue = .object(["kind": .string("piecewise"), "segments": .array([
            .object(["fromSec": .number(0), "toSec": .number(2), "offsetSec": .number(1), "ratio": .number(1)]),
            .object(["fromSec": .number(2), "toSec": .number(20), "offsetSec": .number(5), "ratio": .number(1)]),
        ])])
        let transform = try XCTUnwrap(SubtitlePivotTransform(input))
        let rewritten = document.applying(transform)
        XCTAssertTrue(rewritten.contains("00:02.000 --> 00:04.000 line:20%"))
        XCTAssertTrue(rewritten.contains("00:09.000 --> 00:10.000"))
        XCTAssertTrue(rewritten.contains("<i>Owned</i> &amp; text"))
    }
}

import XCTest
@testable import Harbor

/// F11 B203: Desktop's manual "Live sync" by text (`text-sync.ts` and `use-text-sync.ts`).
final class F11TextSyncTests: XCTestCase {
    private typealias Sync = SubtitleTextSync
    private typealias Point = SubtitleTextSync.Point
    private typealias Timing = SubtitleTextSync.Timing

    private func session(baseOffset: Double = 0) -> SubtitleTextSyncSession {
        let cues = [Timing(start: 10, end: 12), Timing(start: 20, end: 22), Timing(start: 30, end: 32), Timing(start: 40, end: 42)]
        return SubtitleTextSyncSession(cues: cues, texts: ["Hello there", "Goodbye", "hello again", "The end"], baseOffset: baseOffset)
    }

    func testDeltaWithoutPointsIsTheNudge() {
        XCTAssertEqual(Sync.delta(at: 50, points: [], nudge: 0.5), 0.5, accuracy: 1e-9)
    }

    func testDeltaWithOnePointIsAConstantOffset() {
        XCTAssertEqual(Sync.delta(at: 50, points: [Point(t: 10, at: 12)], nudge: 0.5), 2.5, accuracy: 1e-9)
    }

    func testTwoFarPointsFixDriftLinearly() {
        let points = [Point(t: 10, at: 12), Point(t: 110, at: 114)]
        XCTAssertEqual(Sync.delta(at: 10, points: points, nudge: 0), 2, accuracy: 1e-9)
        XCTAssertEqual(Sync.delta(at: 60, points: points, nudge: 0), 3, accuracy: 1e-9)
        XCTAssertEqual(Sync.delta(at: 110, points: points, nudge: 0), 4, accuracy: 1e-9)
        let reversed = [points[1], points[0]]
        XCTAssertEqual(Sync.delta(at: 60, points: reversed, nudge: 0), 3, accuracy: 1e-9)
    }

    func testPointsCloserThanThreeSecondsAreNotDrift() {
        let points = [Point(t: 10, at: 12), Point(t: 11, at: 14)]
        XCTAssertEqual(Sync.delta(at: 500, points: points, nudge: 0), 3, accuracy: 1e-9)
    }

    func testASlopeOverFivePercentKeepsTheLatestOffset() {
        let points = [Point(t: 10, at: 12), Point(t: 110, at: 130)]
        XCTAssertEqual(Sync.delta(at: 60, points: points, nudge: 0.25), 20.25, accuracy: 1e-9)
    }

    func testPointsAtTheSameTimeDoNotDivideByZero() {
        let points = [Point(t: 10, at: 12), Point(t: 10, at: 13)]
        XCTAssertEqual(Sync.delta(at: 60, points: points, nudge: 0), 3, accuracy: 1e-9)
    }

    func testApplyMovesSectionsAndKeepsTimesValid() {
        let cues = [Timing(start: 1, end: 3), Timing(start: 5, end: 7), Timing(start: 9, end: 11)]
        let moved = Sync.apply(cues, points: [], nudge: 0.5, segments: [SubtitleTextSync.Segment(startIndex: 1, endIndex: 1, offset: 2)])
        XCTAssertEqual(moved, [Timing(start: 1.5, end: 3.5), Timing(start: 7.5, end: 9.5), Timing(start: 9.5, end: 11.5)])
        let early = Sync.apply([Timing(start: 0.2, end: 0.5)], points: [], nudge: -1, segments: [])
        XCTAssertEqual(early[0].start, 0, accuracy: 1e-9)
        XCTAssertEqual(early[0].end, 0.001, accuracy: 1e-9)
    }

    func testAThirdPointReplacesTheSecond() {
        let first = Point(t: 1, at: 2)
        let second = Point(t: 50, at: 52)
        let third = Point(t: 90, at: 93)
        XCTAssertEqual(Sync.adding(second, to: [first]), [first, second])
        XCTAssertEqual(Sync.adding(third, to: [first, second]), [first, third])
    }

    func testOnlySubRipAndWebVTTFilesAreOffered() {
        XCTAssertTrue(Sync.supportsFile(named: "/tmp/a.SRT"))
        XCTAssertTrue(Sync.supportsFile(named: "https://example.test/x/a.vtt?token=1"))
        XCTAssertFalse(Sync.supportsFile(named: "/tmp/a.ass"))
        XCTAssertFalse(Sync.supportsFile(named: ""))
    }

    func testActiveIndexAndClock() {
        let cues = [Timing(start: 10, end: 12), Timing(start: 20, end: 22)]
        XCTAssertNil(Sync.activeIndex(in: cues, position: 5))
        XCTAssertEqual(Sync.activeIndex(in: cues, position: 20), 1)
        XCTAssertNil(Sync.activeIndex(in: cues, position: 22))
        XCTAssertEqual(Sync.clock(65.9), "01:05")
        XCTAssertEqual(Sync.clock(-4), "00:00")
    }

    func testAlignToNowAddsAPointAndDropsTheNudge() {
        var value = session(baseOffset: 0.5)
        XCTAssertFalse(value.dirty)
        value.syncFromHere(cueIndex: 1, position: 25)
        XCTAssertEqual(value.points, [Point(t: 20, at: 25)])
        XCTAssertEqual(value.nudge, 0, accuracy: 1e-9)
        XCTAssertTrue(value.dirty)
        XCTAssertEqual(value.corrected[0].start, 15, accuracy: 1e-9)
    }

    func testASectionShiftsOnlyItsLinesAndTheSameSectionIsReplaced() {
        var value = session()
        value.chooseRangeStart(3)
        value.chooseRangeEnd(1)
        XCTAssertEqual(value.range?.low, 1)
        XCTAssertEqual(value.range?.high, 3)
        value.syncFromHere(cueIndex: 2, position: 36)
        XCTAssertEqual(value.segments, [SubtitleTextSync.Segment(startIndex: 1, endIndex: 3, offset: 6)])
        XCTAssertNil(value.rangeStart)
        XCTAssertEqual(value.corrected[0].start, 10, accuracy: 1e-9)
        XCTAssertEqual(value.corrected[1].start, 26, accuracy: 1e-9)
        value.chooseRangeStart(1)
        value.chooseRangeEnd(3)
        value.syncFromHere(cueIndex: 2, position: 37)
        XCTAssertEqual(value.segments, [SubtitleTextSync.Segment(startIndex: 1, endIndex: 3, offset: 7)])
    }

    func testNudgeRoundsToMilliseconds() {
        var value = session()
        value.adjustNudge(by: 0.1)
        value.adjustNudge(by: 0.1)
        value.adjustNudge(by: 0.1)
        XCTAssertEqual(value.nudge, 0.3, accuracy: 1e-9)
        XCTAssertTrue(value.dirty)
    }

    func testResetDropsPointsNudgeAndSections() {
        var value = session()
        value.syncFromHere(cueIndex: 0, position: 11)
        value.chooseRangeStart(1)
        value.chooseRangeEnd(2)
        value.syncFromHere(cueIndex: 1, position: 25)
        value.reset()
        XCTAssertTrue(value.points.isEmpty)
        XCTAssertTrue(value.segments.isEmpty)
        XCTAssertNil(value.rangeStart)
        XCTAssertEqual(value.nudge, 0, accuracy: 1e-9)
    }

    func testSearchFindsLinesByTheirWordsIgnoringCase() {
        let value = session()
        XCTAssertEqual(value.matches(" HELLO "), [0, 2])
        XCTAssertEqual(value.matches(""), [])
        XCTAssertEqual(value.matches("zebra"), [])
    }

    func testTheSubtitleFileTakesTheCorrectedTimesInFileOrder() throws {
        let srt = """
        1
        00:00:01,000 --> 00:00:02,000
        First

        2
        00:00:03,000 --> 00:00:04,000
        Second

        3
        00:00:05,000 --> 00:00:06,000
        Third

        4
        00:00:07,000 --> 00:00:08,000
        Fourth
        """
        let document = try SubtitleDocument(srt)
        let lines = try document.cuesInFileOrder()
        XCTAssertEqual(lines.map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }, ["First", "Second", "Third", "Fourth"])
        let times: [(start: Double, end: Double)] = [(2, 3), (4, 5), (6, 7), (8, 9)]
        let rewritten = try XCTUnwrap(document.applying(cueTimes: times))
        XCTAssertTrue(rewritten.contains("00:00:02,000 --> 00:00:03,000"))
        XCTAssertTrue(rewritten.contains("00:00:08,000 --> 00:00:09,000"))
        XCTAssertTrue(rewritten.contains("Second"))
        let reparsed = try SubtitleDocument(rewritten)
        XCTAssertEqual(reparsed.cues.map { $0.start }, [2, 4, 6, 8])
        let tooFew: [(start: Double, end: Double)] = [(2, 3)]
        XCTAssertNil(document.applying(cueTimes: tooFew))
    }
}

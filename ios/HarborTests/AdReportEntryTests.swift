import XCTest
@testable import Harbor

/// Desktop's `range-row.tsx` (`fmt`, `parse`) and `ad-report-modal.tsx` (adding and checking ranges).
final class AdReportEntryTests: XCTestCase {
    func testTimesShowAsMinutesAndSecondsOrHours() {
        XCTAssertEqual(AdReportEntry.format(0), "0:00")
        XCTAssertEqual(AdReportEntry.format(65), "1:05")
        XCTAssertEqual(AdReportEntry.format(3_599.6), "1:00:00")
        XCTAssertEqual(AdReportEntry.format(3_725), "1:02:05")
        XCTAssertEqual(AdReportEntry.format(-5), "0:00")
        XCTAssertEqual(AdReportEntry.format(.nan), "0:00")
    }

    func testTypedTimesAreDigitsSeparatedByColons() {
        XCTAssertEqual(AdReportEntry.parse("90"), 90)
        XCTAssertEqual(AdReportEntry.parse("1:30"), 90)
        XCTAssertEqual(AdReportEntry.parse(" 1 : 02 : 05 "), 3_725)
        XCTAssertEqual(AdReportEntry.parse("0:00"), 0)
    }

    func testTypedTimesThatAreNotTimesAreRefused() {
        for text in ["", "  ", "abc", "1:", ":30", "1::30", "1:2:3:4", "-5", "1.5", "1:3x", "١٢"] {
            XCTAssertNil(AdReportEntry.parse(text), text)
        }
    }

    func testANewRangeStartsAtTheRoundedPositionAndRunsThirtySeconds() {
        XCTAssertEqual(AdReportEntry.newRange(at: 12.6), AdReportRange(startSec: 13, endSec: 43))
        XCTAssertEqual(AdReportEntry.newRange(at: -3), AdReportRange(startSec: 0, endSec: 30))
        XCTAssertEqual(AdReportEntry.newRange(at: .infinity), AdReportRange(startSec: 0, endSec: 30))
    }

    func testAReportNeedsARangeAndEveryRangeMustEndAfterItStarts() {
        XCTAssertFalse(AdReportEntry.canSubmit([]))
        XCTAssertTrue(AdReportEntry.canSubmit([AdReportRange(startSec: 10, endSec: 40)]))
        XCTAssertFalse(AdReportEntry.canSubmit([AdReportRange(startSec: 10, endSec: 40), AdReportRange(startSec: 50, endSec: 50)]))
        XCTAssertFalse(AdReportEntry.canSubmit([AdReportRange(startSec: 60, endSec: 50)]))
    }

    func testTheReportSettingsAreStoredPerProfile() {
        XCTAssertTrue(ProfileSettingsStore.keys.contains("adReportAlwaysShow"))
        XCTAssertTrue(ProfileSettingsStore.keys.contains("adReportFirstSeen"))
    }
}

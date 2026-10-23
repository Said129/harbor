import XCTest
@testable import Harbor

@MainActor final class EBookReaderChromeTests: XCTestCase {
    func testIdleHidesControlsAndInteractionRestartsTheTimerWithoutAStaleHide() async throws {
        let chrome = EBookReaderChrome(delay: .seconds(1))
        chrome.reveal(focus: true)
        try await Task.sleep(for: .milliseconds(600)); XCTAssertTrue(chrome.visible)
        chrome.reveal(focus: true)
        try await Task.sleep(for: .milliseconds(600)); XCTAssertTrue(chrome.visible, "The cancelled first timer must not hide recently revealed controls")
        for _ in 0..<100 { if !chrome.visible { break }; try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertFalse(chrome.visible)
        chrome.reveal(focus: false)
        try await Task.sleep(for: .milliseconds(1100)); XCTAssertTrue(chrome.visible)
    }
    func testPresentedPanelAccessibilityAndLeavingTheReaderCancelThePendingHideAndReleaseIt() async throws {
        var chrome: EBookReaderChrome? = EBookReaderChrome(delay: .milliseconds(30))
        chrome?.reveal(focus: true); chrome?.reveal(focus: true, suspended: true)
        try await Task.sleep(for: .milliseconds(80)); XCTAssertEqual(chrome?.visible, true)
        chrome?.reveal(focus: true); chrome?.stop()
        try await Task.sleep(for: .milliseconds(80)); XCTAssertEqual(chrome?.visible, true)
        chrome?.reveal(focus: true)
        weak var released = chrome; chrome = nil
        XCTAssertNil(released, "The delayed callback must not keep a dismissed reader alive")
        try await Task.sleep(for: .milliseconds(80)); XCTAssertNil(released)
    }
}

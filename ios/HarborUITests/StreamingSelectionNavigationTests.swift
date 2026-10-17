import XCTest

@MainActor final class StreamingSelectionNavigationTests: XCTestCase {
    func testOrdinaryIPhoneServiceSelectionSurvivesRelaunch() { verifySelection(device: "iphone") }
    func testOrdinaryIPadServiceSelectionSurvivesRelaunch() { verifySelection(device: "ipad") }

    private func verifySelection(device: String) {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-uiLanguage", "es", "-nativeGuide.initialized.v1", "YES", "-nativeGuide.completed.v1", "YES"]
        app.launch(); defer { app.terminate() }
        openSettings(app)
        let netflix = app.buttons["streaming-netflix"]
        XCTAssertTrue(netflix.waitForExistence(timeout: 10)); XCTAssertTrue(netflix.isHittable)
        let previous = netflix.value as? String
        XCTAssertNotNil(previous)
        netflix.tap()
        let selected = netflix.value as? String
        XCTAssertNotEqual(selected, previous)
        capture(app, name: "streaming-selection-\(device)-changed")
        app.terminate(); app.launch()
        openSettings(app)
        XCTAssertTrue(netflix.waitForExistence(timeout: 10)); XCTAssertEqual(netflix.value as? String, selected)
        capture(app, name: "streaming-selection-\(device)-reopened")
        netflix.tap(); XCTAssertEqual(netflix.value as? String, previous)
    }
    private func openSettings(_ app: XCUIApplication) {
        XCTAssertTrue(app.buttons["main-menu"].waitForExistence(timeout: 45)); app.buttons["main-menu"].tap()
        let menu = app.descendants(matching: .any).matching(identifier: "navigation-scroll").firstMatch
        XCTAssertTrue(menu.waitForExistence(timeout: 10))
        let settings = app.buttons["nav-settings"]
        for _ in 0..<10 { if settings.isHittable { break }; menu.swipeUp() }
        XCTAssertTrue(settings.isHittable); settings.tap()
        let search = app.textFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 10)); search.tap(); search.typeText("Streaming")
        let entry = app.buttons["settings-streaming"]
        XCTAssertTrue(entry.waitForExistence(timeout: 5)); entry.tap()
    }
    private func capture(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}

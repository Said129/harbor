import XCTest

@MainActor final class SystemMaintenanceNavigationTests: XCTestCase {
    func testStorageAndAboutWorkInTheOrdinaryIPhoneInterface() { verifySystem(device: "iphone") }
    func testStorageAndAboutWorkInTheOrdinaryIPadInterface() { verifySystem(device: "ipad") }

    private func verifySystem(device: String) {
        continueAfterFailure = false
        // Ordinary saved preferences represent an installation whose welcome
        // guide was completed. Replay below opens the real guide from About.
        let app = XCUIApplication(); app.launchArguments = ["-uiLanguage", "es", "-nativeGuide.initialized.v1", "YES", "-nativeGuide.completed.v1", "YES"]; app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.buttons["main-menu"].waitForExistence(timeout: 45))
        app.buttons["main-menu"].tap()
        let navigation = app.descendants(matching: .any).matching(identifier: "navigation-scroll").firstMatch
        let settings = app.buttons["nav-settings"]
        XCTAssertTrue(navigation.waitForExistence(timeout: 10))
        for _ in 0..<10 { if settings.isHittable { break }; navigation.swipeUp() }
        XCTAssertTrue(settings.isHittable); settings.press(forDuration: 0.6)
        let search = app.textFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 10)); search.tap(); search.typeText("Storage")
        let storage = app.buttons["settings-storage"]
        XCTAssertTrue(storage.waitForExistence(timeout: 5)); storage.tap()
        let clear = app.buttons["storage-clear-images"]
        XCTAssertTrue(clear.waitForExistence(timeout: 10))
        for _ in 0..<6 { if clear.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(clear.isHittable); clear.tap()
        XCTAssertTrue(app.staticTexts["storage-feedback"].waitForExistence(timeout: 10))
        capture(app, name: "system-storage-" + device)
        let dismissHint = app.buttons["hint-dismiss-imageCache"]
        if dismissHint.exists { dismissHint.tap() }
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(search.waitForExistence(timeout: 10)); search.tap()
        if let value = search.value as? String { search.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: value.count)) }
        search.typeText("About")
        let about = app.buttons["settings-about"]
        XCTAssertTrue(about.waitForExistence(timeout: 5)); about.tap()
        let restore = app.buttons["about-restore-hints"]
        XCTAssertTrue(restore.waitForExistence(timeout: 10)); restore.tap()
        XCTAssertTrue(restore.label.contains("Restaurad"))
        capture(app, name: "system-about-" + device)
        app.buttons["about-replay"].tap()
        let next = app.buttons["guide-next"]
        XCTAssertTrue(next.waitForExistence(timeout: 10))
        let headings = ["Te damos la bienvenida a Harbor", "A tu gusto", "Lee en iPhone y iPad", "Continúa viendo"]
        for (index, heading) in headings.enumerated() {
            XCTAssertTrue(app.staticTexts[heading].waitForExistence(timeout: 5))
            capture(app, name: "system-walkthrough-\(device)-\(index + 1)")
            XCTAssertTrue(next.isHittable); next.tap()
        }
        XCTAssertTrue(app.buttons["about-replay"].waitForExistence(timeout: 10))
    }
    private func capture(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}

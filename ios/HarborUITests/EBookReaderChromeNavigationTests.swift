import XCTest

@MainActor final class EBookReaderChromeNavigationTests: XCTestCase {
    func testFocusHidesAndRevealsControlsKeepsPanelsUsableAndRestoresAfterRelaunchOnIPhone() { verify("iphone") }
    func testFocusHidesAndRevealsControlsKeepsPanelsUsableAndRestoresAfterRelaunchOnIPad() { verify("ipad") }
    private func verify(_ device: String) {
        continueAfterFailure = false; XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication(); app.launchArguments = ["-uiLanguage", "en", "-nativeGuide.initialized.v1", "YES", "-nativeGuide.completed.v1", "YES"]
        app.launch(); defer { app.terminate(); XCUIDevice.shared.orientation = .portrait }; openBook(app)
        let paragraph = app.staticTexts.matching(identifier: "ebook-reader-text").firstMatch
        XCTAssertTrue(paragraph.waitForExistence(timeout: 30)); XCTAssertEqual(paragraph.label, "Actual original:3 paragraph.")
        let menu = app.buttons["ebook-reader-menu"], next = app.buttons["ebook-next-section"]
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in menu.exists && next.exists && menu.isHittable && next.isEnabled }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 20), .completed)
        capture(app, "reader-focus-initial-" + device)
        openSettings(app)
        let form = app.descendants(matching: .any).matching(identifier: "ebook-reader-settings-form").firstMatch
        XCTAssertTrue(form.waitForExistence(timeout: 15))
        let setting = app.switches["ebook-focus-setting"]; ReadingUIInteraction.reveal(setting, in: app, container: form)
        XCTAssertEqual(setting.value as? String, "0")
        setting.coordinate(withNormalizedOffset: .init(dx: 0.93, dy: 0.5)).tap(); XCTAssertEqual(setting.value as? String, "1")
        let done = app.buttons["ebook-reader-settings-done"]
        // A native sheet remains interactive beyond the Desktop inactivity delay.
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 3))
        XCTAssertTrue(done.isHittable); capture(app, "reader-focus-panel-" + device); ReadingUIInteraction.tapVisible(done, in: app)
        hidden(menu, next: next, app: app); ReadingUIInteraction.assertReaderViewport(app)
        XCTAssertEqual(paragraph.label, "Actual original:3 paragraph."); capture(app, "reader-focus-hidden-" + device)
        ReadingUIInteraction.tapVisible(paragraph, in: app)
        XCTAssertTrue(menu.waitForExistence(timeout: 10)); capture(app, "reader-focus-revealed-" + device)
        app.terminate(); app.launch(); openBook(app)
        XCTAssertTrue(paragraph.waitForExistence(timeout: 30)); hidden(menu, next: next, app: app)
        XCUIDevice.shared.orientation = .landscapeLeft
        ReadingUIInteraction.waitForLandscape(app)
        ReadingUIInteraction.assertReaderViewport(app); XCTAssertEqual(paragraph.label, "Actual original:3 paragraph.")
        capture(app, "reader-focus-restored-" + device)
        ReadingUIInteraction.tapVisible(paragraph, in: app); openSettings(app)
        ReadingUIInteraction.reveal(setting, in: app, container: form); XCTAssertEqual(setting.value as? String, "1")
        setting.coordinate(withNormalizedOffset: .init(dx: 0.93, dy: 0.5)).tap(); XCTAssertEqual(setting.value as? String, "0")
        ReadingUIInteraction.tapVisible(done, in: app)
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 3))
        XCTAssertTrue(menu.isHittable); XCTAssertTrue(next.isEnabled); XCTAssertEqual(paragraph.label, "Actual original:3 paragraph.")
        capture(app, "reader-focus-disabled-" + device)
    }
    private func hidden(_ menu: XCUIElement, next: XCUIElement, app: XCUIApplication) {
        let absent = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in !menu.exists && !next.exists && !app.buttons["main-menu"].exists }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [absent], timeout: 15), .completed)
    }
    private func openSettings(_ app: XCUIApplication) {
        let menu = app.buttons["ebook-reader-menu"]; XCTAssertTrue(menu.waitForExistence(timeout: 15)); ReadingUIInteraction.tapVisible(menu, in: app)
        let settings = app.buttons["ebook-reader-settings-action"]; XCTAssertTrue(settings.waitForExistence(timeout: 10)); settings.tap()
        XCTAssertTrue(app.buttons["ebook-reader-settings-done"].waitForExistence(timeout: 15))
    }
    private func openBook(_ app: XCUIApplication) {
        let menu = app.buttons["main-menu"]; XCTAssertTrue(menu.waitForExistence(timeout: 45)); menu.tap()
        let navigation = app.descendants(matching: .any).matching(identifier: "navigation-scroll").firstMatch
        XCTAssertTrue(navigation.waitForExistence(timeout: 10)); let target = app.buttons["nav-ebook"]
        for _ in 0..<12 { if target.isHittable { break }; navigation.swipeDown() }
        for _ in 0..<12 { if target.isHittable { break }; navigation.swipeUp() }
        XCTAssertTrue(target.isHittable); target.press(forDuration: 0.6)
        let tabs = app.segmentedControls["ebook-screen"]; XCTAssertTrue(tabs.waitForExistence(timeout: 15)); tabs.buttons.element(boundBy: 2).tap()
        let card = app.buttons["ebook-card-source:plugin%3Achapters:owned"]; ReadingUIInteraction.reveal(card, in: app); card.tap()
        let read = app.buttons["ebook-detail-read"]; XCTAssertTrue(read.waitForExistence(timeout: 20)); ReadingUIInteraction.reveal(read, in: app); ReadingUIInteraction.tapVisible(read, in: app)
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}

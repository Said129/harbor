import XCTest

@MainActor final class ReadingWebFontNavigationTests: XCTestCase {
    func testActualConvertedWebFontChoicesAndReaderOnIPhone() { verify("iphone") }
    func testActualConvertedWebFontChoicesAndReaderOnIPad() { verify("ipad") }
    private func verify(_ device: String) {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchArguments = ["-uiLanguage", "en", "-nativeGuide.initialized.v1", "YES", "-nativeGuide.completed.v1", "YES"]
        app.launch(); defer { app.terminate() }
        let menu = app.buttons["main-menu"]; XCTAssertTrue(menu.waitForExistence(timeout: 45)); menu.tap()
        let navigation = app.descendants(matching: .any).matching(identifier: "navigation-scroll").firstMatch
        XCTAssertTrue(navigation.waitForExistence(timeout: 10)); let target = app.buttons["nav-ebook"]
        for _ in 0..<12 { if target.isHittable { break }; navigation.swipeDown() }
        for _ in 0..<12 { if target.isHittable { break }; navigation.swipeUp() }
        XCTAssertTrue(target.isHittable); target.press(forDuration: 0.6)
        ReadingUIInteraction.chooseBookSource("Owned volumes", in: app)
        let card = app.buttons["ebook-card-source:plugin%3Achapters:owned"]
        XCTAssertTrue(card.waitForExistence(timeout: 45)); reveal(card, app); card.tap()
        let read = app.buttons["ebook-detail-read"]; XCTAssertTrue(read.waitForExistence(timeout: 20)); reveal(read, app); read.tap()
        let paragraph = app.staticTexts.matching(identifier: "ebook-reader-text").firstMatch
        XCTAssertTrue(paragraph.waitForExistence(timeout: 30))
        ReadingUIInteraction.assertReaderViewport(app)
        for format in ["woff", "woff2"] {
            let options = app.buttons["ebook-reader-menu"]; XCTAssertTrue(options.waitForExistence(timeout: 15)); ReadingUIInteraction.tapVisible(options, in: app)
            app.buttons["ebook-reader-settings-action"].tap()
            let fonts = app.buttons["ebook-custom-fonts"]; XCTAssertTrue(fonts.waitForExistence(timeout: 15)); reveal(fonts, app); fonts.tap()
            let row = app.buttons["owned reader " + format]; XCTAssertTrue(row.waitForExistence(timeout: 15)); row.tap()
            XCTAssertTrue(app.staticTexts["reading-font-preview"].waitForExistence(timeout: 15))
            capture(app, "web-font-choices-" + format + "-" + device)
            ReadingUIInteraction.back(from: "Custom font", in: app); app.buttons["ebook-reader-settings-done"].tap()
            XCTAssertTrue(paragraph.waitForExistence(timeout: 15))
            let loading = app.descendants(matching: .any).matching(identifier: "ebook-font-loading").firstMatch
            XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: loading)], timeout: 15), .completed)
            XCTAssertFalse(app.staticTexts["ebook-font-error"].exists)
            capture(app, "web-font-reader-" + format + "-" + device)
        }
    }
    private func reveal(_ element: XCUIElement, _ app: XCUIApplication) {
        ReadingUIInteraction.reveal(element, in: app)
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}

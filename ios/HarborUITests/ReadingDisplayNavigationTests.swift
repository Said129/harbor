import XCTest

@MainActor final class ReadingDisplayNavigationTests: XCTestCase {
    func testActualReadingBrightnessAndImportedFontRestoreOnIPhone() { verify("iphone") }
    func testActualReadingBrightnessAndImportedFontRestoreOnIPad() { verify("ipad") }
    private func verify(_ device: String) {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchArguments = ["-uiLanguage", "en", "-nativeGuide.initialized.v1", "YES", "-nativeGuide.completed.v1", "YES"]
        app.launch(); defer { app.terminate() }
        reader(app)
        capture(app, "reading-display-baseline-" + device)
        settings(app)
        let brightness = app.sliders["ebook-brightness"]; reveal(brightness, app); XCTAssertTrue(brightness.exists)
        XCTAssertEqual(brightness.value as? String, "100 %")
        capture(app, "reading-display-options-" + device)
        brightness.adjust(toNormalizedSliderPosition: 0)
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "55 %"), object: brightness)], timeout: 10), .completed)
        app.buttons["ebook-reader-settings-done"].tap()
        XCTAssertTrue(app.staticTexts.matching(identifier: "ebook-reader-text").firstMatch.waitForExistence(timeout: 15))
        capture(app, "reading-display-dim-reader-" + device)
        settings(app)
        let fonts = app.buttons["ebook-custom-fonts"]; XCTAssertTrue(fonts.waitForExistence(timeout: 10)); reveal(fonts, app, up: false); fonts.tap()
        let font = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'reading-font-' AND label == 'Inter'")).firstMatch
        XCTAssertTrue(font.waitForExistence(timeout: 15)); font.tap()
        XCTAssertTrue(app.staticTexts["reading-font-preview"].waitForExistence(timeout: 15))
        capture(app, "reading-display-fonts-" + device)
        ReadingUIInteraction.back(from: "Custom font", in: app)
        app.buttons["ebook-reader-settings-done"].tap()
        let paragraph = app.staticTexts.matching(identifier: "ebook-reader-text").firstMatch
        XCTAssertTrue(paragraph.waitForExistence(timeout: 15))
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.otherElements["ebook-font-loading"])], timeout: 15), .completed)
        XCTAssertFalse(app.staticTexts["ebook-font-error"].exists)
        capture(app, "reading-display-custom-reader-" + device)
        app.terminate(); app.launch(); reader(app); settings(app)
        XCTAssertTrue(brightness.waitForExistence(timeout: 15)); reveal(brightness, app); XCTAssertEqual(brightness.value as? String, "55 %")
        capture(app, "reading-display-restored-" + device)
        reveal(fonts, app, up: false); fonts.tap(); XCTAssertTrue(font.waitForExistence(timeout: 15)); XCTAssertTrue(font.isSelected)
    }
    private func reader(_ app: XCUIApplication) {
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
        XCTAssertTrue(app.staticTexts.matching(identifier: "ebook-reader-text").firstMatch.waitForExistence(timeout: 30))
        ReadingUIInteraction.assertReaderViewport(app)
    }
    private func settings(_ app: XCUIApplication) {
        let menu = app.buttons["ebook-reader-menu"]; XCTAssertTrue(menu.waitForExistence(timeout: 10)); ReadingUIInteraction.tapVisible(menu, in: app)
        let action = app.buttons["ebook-reader-settings-action"]; XCTAssertTrue(action.waitForExistence(timeout: 10)); action.tap()
    }
    private func reveal(_ element: XCUIElement, _ app: XCUIApplication, up: Bool = true) {
        ReadingUIInteraction.reveal(element, in: app, up: up)
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}

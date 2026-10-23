import XCTest

@MainActor final class EBookSearchNavigationTests: XCTestCase {
    func testOriginalSealedChapterSearchJumpsInBothReadingModesOnIPhone() { verify("iphone") }
    func testOriginalSealedChapterSearchJumpsInBothReadingModesOnIPad() { verify("ipad") }
    private func verify(_ device: String) {
        continueAfterFailure = false; XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication(); app.launchArguments = ["-uiLanguage", "en", "-nativeGuide.initialized.v1", "YES", "-nativeGuide.completed.v1", "YES"]
        app.launch(); defer { app.terminate() }
        let menu = app.buttons["main-menu"]; XCTAssertTrue(menu.waitForExistence(timeout: 45)); menu.tap()
        let navigation = app.descendants(matching: .any).matching(identifier: "navigation-scroll").firstMatch
        XCTAssertTrue(navigation.waitForExistence(timeout: 10)); let target = app.buttons["nav-ebook"]
        for _ in 0..<12 { if target.isHittable { break }; navigation.swipeDown() }
        for _ in 0..<12 { if target.isHittable { break }; navigation.swipeUp() }
        XCTAssertTrue(target.isHittable); target.press(forDuration: 0.6)
        ReadingUIInteraction.chooseBookSource("Owned pagination", in: app)
        let card = app.buttons["ebook-card-source:plugin%3Aowned.pages:owned"]
        XCTAssertTrue(card.waitForExistence(timeout: 45)); ReadingUIInteraction.reveal(card, in: app); card.tap()
        let read = app.buttons["ebook-detail-read"]; XCTAssertTrue(read.waitForExistence(timeout: 20)); ReadingUIInteraction.reveal(read, in: app); read.tap()
        XCTAssertTrue(app.staticTexts.matching(identifier: "ebook-reader-text").firstMatch.waitForExistence(timeout: 30))
        ReadingUIInteraction.assertReaderViewport(app)
        openSearch(app); let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 15)); field.tap(); field.typeText("rEaDaBlE")
        let reveal = app.buttons["ebook-passage-reveal"]
        XCTAssertTrue(app.buttons["ebook-passage-result-0"].waitForExistence(timeout: 20))
        XCTAssertFalse(app.buttons["ebook-passage-result-14"].exists)
        ReadingUIInteraction.reveal(reveal, in: app)
        capture(app, "book-search-sealed-" + device)
        reveal.tap()
        let result = app.buttons["ebook-passage-result-14"]
        ReadingUIInteraction.reveal(result, in: app)
        capture(app, "book-search-revealed-" + device); result.tap()
        let paragraph = app.staticTexts.matching(NSPredicate(format: "identifier == %@ AND label BEGINSWITH %@", "ebook-reader-text", "Paragraph 14.")).firstMatch
        waitForJump(paragraph, in: app)
        capture(app, "book-search-continuous-jump-" + device)
        let options = app.buttons["ebook-reader-menu"]; ReadingUIInteraction.tapVisible(options, in: app); app.buttons["ebook-reader-settings-action"].tap()
        let mode = app.segmentedControls["ebook-reading-mode"]; XCTAssertTrue(mode.waitForExistence(timeout: 15)); mode.buttons["Book"].tap(); app.buttons["ebook-reader-settings-done"].tap()
        XCTAssertTrue(app.staticTexts["ebook-print-position"].waitForExistence(timeout: 30))
        openSearch(app)
        XCTAssertTrue(field.waitForExistence(timeout: 15)); XCTAssertEqual(field.value as? String, "rEaDaBlE")
        ReadingUIInteraction.replace(field, with: "PARAGRAPH 30.", in: app)
        XCTAssertTrue(reveal.waitForExistence(timeout: 20)); XCTAssertFalse(app.buttons["ebook-passage-result-30"].exists)
        capture(app, "book-search-resealed-" + device)
        reveal.tap(); let future = app.buttons["ebook-passage-result-30"]
        XCTAssertTrue(future.waitForExistence(timeout: 20)); future.tap()
        let printed = app.descendants(matching: .any).matching(NSPredicate(format: "identifier == %@ AND label CONTAINS %@", "ebook-print-page", "Paragraph 30.")).firstMatch
        waitForJump(printed, in: app)
        capture(app, "book-search-book-jump-" + device)
        openSearch(app); XCTAssertTrue(field.waitForExistence(timeout: 15)); XCTAssertEqual(field.value as? String, "PARAGRAPH 30.")
        XCTAssertTrue(future.waitForExistence(timeout: 20)); XCTAssertFalse(reveal.exists)
        capture(app, "book-search-remembered-" + device)
        app.buttons["ebook-passage-close"].tap()
    }
    private func openSearch(_ app: XCUIApplication) {
        let menu = app.buttons["ebook-reader-menu"]; XCTAssertTrue(menu.waitForExistence(timeout: 15)); ReadingUIInteraction.tapVisible(menu, in: app)
        app.buttons["ebook-passage-search-action"].tap()
    }
    private func waitForJump(_ element: XCUIElement, in app: XCUIApplication) {
        let closed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.buttons["ebook-passage-close"])
        XCTAssertEqual(XCTWaiter.wait(for: [closed], timeout: 20), .completed)
        let visible = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in ReadingUIInteraction.visibleFrame(element, in: app) != nil }, object: element)
        let outcome = XCTWaiter.wait(for: [visible], timeout: 30)
        if outcome != .completed {
            let hierarchy = XCTAttachment(string: app.debugDescription); hierarchy.name = "book-search-jump-hierarchy"; hierarchy.lifetime = .keepAlways; add(hierarchy)
            capture(app, "book-search-jump-failure")
        }
        XCTAssertEqual(outcome, .completed)
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}

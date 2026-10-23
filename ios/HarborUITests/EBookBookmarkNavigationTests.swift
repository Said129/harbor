import XCTest

@MainActor final class EBookBookmarkNavigationTests: XCTestCase {
    func testOriginalBookmarkPanelDeduplicationChapterJumpsRemovalAndRelaunchOnIPhone() { verify("iphone") }
    func testOriginalBookmarkPanelDeduplicationChapterJumpsRemovalAndRelaunchOnIPad() { verify("ipad") }
    private func verify(_ device: String) {
        continueAfterFailure = false; XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication(); app.launchArguments = ["-uiLanguage", "en", "-nativeGuide.initialized.v1", "YES", "-nativeGuide.completed.v1", "YES"]
        app.launch(); defer { app.terminate() }; openBook(app)
        let paragraph = app.staticTexts.matching(identifier: "ebook-reader-text").firstMatch
        expect("3", paragraph: paragraph)
        action("ebook-bookmark-add-action", in: app)
        let cards = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "ebook-bookmark-card-"))
        XCTAssertTrue(cards.firstMatch.waitForExistence(timeout: 15)); XCTAssertEqual(cards.count, 2)
        XCTAssertTrue(cards.element(boundBy: 0).label.contains("Actual original:3 paragraph."))
        XCTAssertTrue(cards.element(boundBy: 1).label.contains("Actual original:1 paragraph."))
        capture(app, "reader-bookmarks-newest-" + device)
        cards.element(boundBy: 0).tap(); expect("3", paragraph: paragraph)
        let closed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.buttons["ebook-bookmarks-close"])
        XCTAssertEqual(XCTWaiter.wait(for: [closed], timeout: 15), .completed)
        ReadingUIInteraction.assertReaderViewport(app); capture(app, "reader-bookmarks-local-jump-" + device)
        action("ebook-bookmarks-action", in: app)
        let firstChapter = cards.matching(NSPredicate(format: "label CONTAINS %@", "Actual original:1 paragraph.")).firstMatch
        XCTAssertTrue(firstChapter.waitForExistence(timeout: 15)); firstChapter.tap(); expect("1", paragraph: paragraph)
        capture(app, "reader-bookmarks-chapter-jump-" + device)
        action("ebook-bookmark-add-action", in: app)
        XCTAssertTrue(cards.firstMatch.waitForExistence(timeout: 15)); XCTAssertEqual(cards.count, 2)
        XCTAssertTrue(cards.element(boundBy: 0).label.contains("Actual original:1 paragraph."))
        app.buttons["ebook-bookmarks-close"].tap()
        app.terminate(); app.launch(); openBook(app); expect("1", paragraph: paragraph)
        action("ebook-bookmarks-action", in: app)
        XCTAssertTrue(cards.firstMatch.waitForExistence(timeout: 15)); XCTAssertEqual(cards.count, 2)
        XCTAssertTrue(cards.element(boundBy: 0).label.contains("Actual original:1 paragraph."))
        capture(app, "reader-bookmarks-restored-" + device)
        let firstID = cards.element(boundBy: 0).identifier.replacingOccurrences(of: "ebook-bookmark-card-", with: "")
        app.buttons["ebook-bookmark-delete-" + firstID].tap()
        let one = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in cards.count == 1 }, object: cards)
        XCTAssertEqual(XCTWaiter.wait(for: [one], timeout: 10), .completed)
        XCTAssertTrue(cards.firstMatch.label.contains("Actual original:3 paragraph."))
        capture(app, "reader-bookmarks-deleted-" + device)
        cards.firstMatch.tap(); expect("3", paragraph: paragraph)
        action("ebook-bookmarks-action", in: app)
        XCTAssertTrue(cards.firstMatch.waitForExistence(timeout: 15))
        let lastID = cards.firstMatch.identifier.replacingOccurrences(of: "ebook-bookmark-card-", with: "")
        app.buttons["ebook-bookmark-delete-" + lastID].tap()
        XCTAssertTrue(app.staticTexts["ebook-bookmarks-empty"].waitForExistence(timeout: 15)); XCTAssertEqual(cards.count, 0)
        capture(app, "reader-bookmarks-empty-" + device)
    }
    private func openBook(_ app: XCUIApplication) {
        let menu = app.buttons["main-menu"]; XCTAssertTrue(menu.waitForExistence(timeout: 45)); menu.tap()
        let navigation = app.descendants(matching: .any).matching(identifier: "navigation-scroll").firstMatch
        XCTAssertTrue(navigation.waitForExistence(timeout: 10)); let target = app.buttons["nav-ebook"]
        for _ in 0..<12 { if target.isHittable { break }; navigation.swipeDown() }
        for _ in 0..<12 { if target.isHittable { break }; navigation.swipeUp() }
        XCTAssertTrue(target.isHittable); target.press(forDuration: 0.6)
        let tabs = app.segmentedControls["ebook-screen"]; XCTAssertTrue(tabs.waitForExistence(timeout: 15)); tabs.buttons.element(boundBy: 2).tap()
        let card = app.buttons["ebook-card-source:plugin%3Achapters:owned"]
        ReadingUIInteraction.reveal(card, in: app); card.tap()
        let read = app.buttons["ebook-detail-read"]; XCTAssertTrue(read.waitForExistence(timeout: 20)); ReadingUIInteraction.reveal(read, in: app); read.tap()
    }
    private func expect(_ chapter: String, paragraph: XCUIElement) {
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "Actual original:" + chapter + " paragraph."), object: paragraph)], timeout: 30), .completed)
    }
    private func action(_ id: String, in app: XCUIApplication) {
        let menu = app.buttons["ebook-reader-menu"]; XCTAssertTrue(menu.waitForExistence(timeout: 15)); ReadingUIInteraction.tapVisible(menu, in: app)
        let action = app.buttons[id]; XCTAssertTrue(action.waitForExistence(timeout: 10)); ReadingUIInteraction.tapVisible(action, in: app)
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}

import XCTest

@MainActor final class EBookReaderHeadingNavigationTests: XCTestCase {
    func testEmbeddedCoverAndChapterHeadingKeepTheRealChapterWhenReopeningAndRotatingOnIPhone() { verify("iphone") }
    func testEmbeddedCoverAndChapterHeadingKeepTheRealChapterWhenReopeningAndRotatingOnIPad() { verify("ipad") }
    private func verify(_ device: String) {
        continueAfterFailure = false; XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication(); app.launchArguments = ["-uiLanguage", "en", "-nativeGuide.initialized.v1", "YES", "-nativeGuide.completed.v1", "YES"]
        app.launch(); defer { app.terminate(); XCUIDevice.shared.orientation = .portrait }; openBook(app)
        let scroll = app.scrollViews["ebook-reader-scroll"]
        let cover = app.descendants(matching: .any).matching(identifier: "ebook-reader-cover").firstMatch
        XCTAssertTrue(cover.waitForExistence(timeout: 30)); ReadingUIInteraction.reveal(cover, in: app, up: false, container: scroll)
        XCTAssertEqual(cover.label, "Owned cover book internal cover"); capture(app, "reader-heading-cover-" + device)
        let title = app.staticTexts["ebook-heading-title"]
        ReadingUIInteraction.reveal(title, in: app, container: scroll); XCTAssertEqual(title.label, "First section")
        capture(app, "reader-heading-first-" + device)
        let next = app.buttons["ebook-next-section"]; XCTAssertTrue(next.isEnabled); ReadingUIInteraction.tapVisible(next, in: app)
        expect("Second section", title: title)
        ReadingUIInteraction.reveal(title, in: app, up: false, container: scroll); XCTAssertFalse(cover.exists)
        XCTAssertFalse(next.isEnabled); XCTAssertTrue(app.buttons["ebook-previous-section"].isEnabled)
        capture(app, "reader-heading-second-" + device)
        let menu = app.buttons["ebook-reader-menu"]; XCTAssertTrue(menu.waitForExistence(timeout: 15)); ReadingUIInteraction.tapVisible(menu, in: app)
        app.buttons["ebook-reader-settings-action"].tap()
        let form = app.descendants(matching: .any).matching(identifier: "ebook-reader-settings-form").firstMatch
        XCTAssertTrue(form.waitForExistence(timeout: 15))
        let paper = app.buttons["ebook-paper"]; ReadingUIInteraction.reveal(paper, in: app, container: form); paper.tap()
        let light = app.buttons["Light"].firstMatch; XCTAssertTrue(light.waitForExistence(timeout: 10)); light.tap()
        ReadingUIInteraction.tapVisible(app.buttons["ebook-reader-settings-done"], in: app)
        ReadingUIInteraction.reveal(title, in: app, up: false, container: scroll); capture(app, "reader-heading-light-" + device)
        app.terminate(); app.launch(); openBook(app); expect("Second section", title: title)
        XCUIDevice.shared.orientation = .landscapeLeft; ReadingUIInteraction.waitForLandscape(app)
        ReadingUIInteraction.reveal(title, in: app, up: false, container: scroll)
        ReadingUIInteraction.assertReaderViewport(app); XCTAssertFalse(cover.exists); XCTAssertEqual(title.label, "Second section")
        capture(app, "reader-heading-restored-" + device)
    }
    private func expect(_ text: String, title: XCUIElement) {
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", text), object: title)], timeout: 30), .completed)
    }
    private func openBook(_ app: XCUIApplication) {
        let menu = app.buttons["main-menu"]; XCTAssertTrue(menu.waitForExistence(timeout: 45)); menu.tap()
        let navigation = app.descendants(matching: .any).matching(identifier: "navigation-scroll").firstMatch
        XCTAssertTrue(navigation.waitForExistence(timeout: 10)); let target = app.buttons["nav-ebook"]
        for _ in 0..<12 { if target.isHittable { break }; navigation.swipeDown() }
        for _ in 0..<12 { if target.isHittable { break }; navigation.swipeUp() }
        XCTAssertTrue(target.isHittable); target.press(forDuration: 0.6)
        let tabs = app.segmentedControls["ebook-screen"]; XCTAssertTrue(tabs.waitForExistence(timeout: 15)); tabs.buttons.element(boundBy: 2).tap()
        let card = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'ebook-card-local:' AND label CONTAINS 'Owned cover book'")).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 30)); ReadingUIInteraction.reveal(card, in: app); card.tap()
        let read = app.buttons["ebook-detail-read"]; XCTAssertTrue(read.waitForExistence(timeout: 20)); ReadingUIInteraction.reveal(read, in: app); ReadingUIInteraction.tapVisible(read, in: app)
        XCTAssertTrue(app.staticTexts.matching(identifier: "ebook-reader-text").firstMatch.waitForExistence(timeout: 30))
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}

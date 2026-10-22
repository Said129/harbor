import XCTest

@MainActor final class EBookPaginationNavigationTests: XCTestCase {
    func testActualBookPagesTurnsZoomAndReadingPositionRestoreOnIPhone() { verify("iphone") }
    func testActualBookPagesTurnsZoomAndReadingPositionRestoreOnIPad() { verify("ipad") }

    private func verify(_ device: String) {
        continueAfterFailure = false; XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["-uiLanguage", "en", "-nativeGuide.initialized.v1", "YES", "-nativeGuide.completed.v1", "YES"]
        app.launch(); defer { app.terminate(); XCUIDevice.shared.orientation = .portrait }
        openBook(app)
        let text = app.staticTexts.matching(identifier: "ebook-reader-text").firstMatch
        XCTAssertTrue(text.waitForExistence(timeout: 30)); ReadingUIInteraction.assertReaderViewport(app)
        capture(app, "book-pagination-continuous-" + device)
        changeMode("Book", app: app)
        let position = app.staticTexts["ebook-print-position"]
        XCTAssertTrue(position.waitForExistence(timeout: 30)); XCTAssertNotNil(waitForPrintedPage(app))
        capture(app, "book-pagination-book-" + device)
        for _ in 0..<2 {
            let previous = position.label, next = app.buttons["ebook-print-next"]
            XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: next)], timeout: 15), .completed); next.tap()
            XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "label != %@", previous), object: position)], timeout: 15), .completed)
            XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: next)], timeout: 15), .completed)
        }
        XCTAssertNotNil(waitForPrintedPage(app)); capture(app, "book-pagination-turned-" + device)
        if device == "ipad" {
            XCUIDevice.shared.orientation = .landscapeLeft
            let spread = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                let pages = app.descendants(matching: .any).matching(identifier: "ebook-print-page").allElementsBoundByIndex
                    .filter { ReadingUIInteraction.visibleFrame($0, in: app) != nil }
                return Set(pages.map(\.label)).count >= 2
            }, object: app)
            XCTAssertEqual(XCTWaiter.wait(for: [spread], timeout: 20), .completed)
            capture(app, "book-pagination-spread-ipad")
        }
        guard let page = printedPage(app) else { XCTFail("The page must contain actual text within the visible reader"); return }
        XCTAssertGreaterThan(page.frame.width, 150); XCTAssertGreaterThan(page.frame.height, 200)
        page.doubleTap()
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "200 %"), object: page)], timeout: 15), .completed)
        capture(app, "book-pagination-zoom-" + device)
        page.doubleTap()
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "100 %"), object: page)], timeout: 15), .completed)
        let savedPosition = position.label
        app.terminate(); app.launch(); openBook(app)
        XCTAssertTrue(position.waitForExistence(timeout: 30))
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", savedPosition), object: position)], timeout: 20), .completed)
        XCTAssertNotNil(waitForPrintedPage(app)); capture(app, "book-pagination-restored-" + device)
        changeMode("Harbor", app: app)
        XCTAssertTrue(text.waitForExistence(timeout: 20)); ReadingUIInteraction.assertReaderViewport(app)
        let visibleText = app.staticTexts.matching(identifier: "ebook-reader-text").allElementsBoundByIndex.first { ReadingUIInteraction.visibleFrame($0, in: app) != nil }
        XCTAssertNotNil(visibleText)
        XCTAssertFalse(visibleText?.label.hasPrefix("Paragraph 0.") ?? true, "Changing reading mode must retain the actual saved paragraph")
        capture(app, "book-pagination-continuous-resume-" + device)
    }
    private func openBook(_ app: XCUIApplication) {
        let menu = app.buttons["main-menu"]; XCTAssertTrue(menu.waitForExistence(timeout: 45)); menu.tap()
        let navigation = app.descendants(matching: .any).matching(identifier: "navigation-scroll").firstMatch
        XCTAssertTrue(navigation.waitForExistence(timeout: 10)); let target = app.buttons["nav-ebook"]
        for _ in 0..<12 { if target.isHittable { break }; navigation.swipeDown() }
        for _ in 0..<12 { if target.isHittable { break }; navigation.swipeUp() }
        XCTAssertTrue(target.isHittable); target.press(forDuration: 0.6)
        ReadingUIInteraction.chooseBookSource("Owned pagination", in: app)
        let card = app.buttons["ebook-card-source:plugin%3Aowned.pages:owned"]
        XCTAssertTrue(card.waitForExistence(timeout: 45)); ReadingUIInteraction.reveal(card, in: app); card.tap()
        let read = app.buttons["ebook-detail-read"]; XCTAssertTrue(read.waitForExistence(timeout: 20))
        ReadingUIInteraction.reveal(read, in: app); read.tap()
    }
    private func changeMode(_ name: String, app: XCUIApplication) {
        let menu = app.buttons["ebook-reader-menu"]; XCTAssertTrue(menu.waitForExistence(timeout: 15)); ReadingUIInteraction.tapVisible(menu, in: app)
        app.buttons["ebook-reader-settings-action"].tap()
        let control = app.segmentedControls["ebook-reading-mode"]
        XCTAssertTrue(control.waitForExistence(timeout: 15)); control.buttons[name].tap()
        app.buttons["ebook-reader-settings-done"].tap()
    }
    private func printedPage(_ app: XCUIApplication) -> XCUIElement? {
        app.descendants(matching: .any).matching(identifier: "ebook-print-page").allElementsBoundByIndex.first {
            ReadingUIInteraction.visibleFrame($0, in: app) != nil && !$0.label.isEmpty
        }
    }
    private func waitForPrintedPage(_ app: XCUIApplication) -> XCUIElement? {
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in self.printedPage(app) != nil }, object: app)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 30), .completed)
        return printedPage(app)
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}

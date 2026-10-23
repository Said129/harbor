import XCTest

@MainActor final class EBookReaderContentsNavigationTests: XCTestCase {
    func testOriginalReaderVolumePickerCurrentChapterAndRealChapterChangeOnIPhone() { verify("iphone") }
    func testOriginalReaderVolumePickerCurrentChapterAndRealChapterChangeOnIPad() { verify("ipad") }
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
        let tabs = app.segmentedControls["ebook-screen"]; XCTAssertTrue(tabs.waitForExistence(timeout: 15)); tabs.buttons.element(boundBy: 2).tap()
        let card = app.buttons["ebook-card-source:plugin%3Achapters:owned"]
        ReadingUIInteraction.reveal(card, in: app); card.tap()
        let read = app.buttons["ebook-detail-read"]; XCTAssertTrue(read.waitForExistence(timeout: 20)); ReadingUIInteraction.reveal(read, in: app); read.tap()
        let paragraph = app.staticTexts.matching(identifier: "ebook-reader-text").firstMatch
        XCTAssertTrue(paragraph.waitForExistence(timeout: 30)); XCTAssertEqual(paragraph.label, "Actual original:3 paragraph.")
        XCTAssertFalse(app.buttons["ebook-next-section"].isEnabled)
        openContents(app)
        let active = app.buttons["ebook-reader-chapter-original:3"]
        XCTAssertTrue(active.waitForExistence(timeout: 15)); XCTAssertTrue(active.isSelected)
        XCTAssertFalse(app.buttons["ebook-reader-chapter-original:1"].exists)
        capture(app, "reader-contents-current-" + device)
        let volume = app.buttons["ebook-reader-volume"]; XCTAssertTrue(volume.waitForExistence(timeout: 15)); ReadingUIInteraction.tapVisible(volume, in: app)
        let firstVolume = app.buttons["ebook-reader-volume-choice-1"]; XCTAssertTrue(firstVolume.waitForExistence(timeout: 10)); firstVolume.tap()
        let first = app.buttons["ebook-reader-chapter-original:1"]; XCTAssertTrue(first.waitForExistence(timeout: 15)); XCTAssertFalse(first.isSelected)
        XCTAssertFalse(active.exists); capture(app, "reader-contents-volume-" + device)
        app.buttons["ebook-reader-contents-close"].tap(); openContents(app)
        XCTAssertTrue(first.waitForExistence(timeout: 15)); XCTAssertFalse(active.exists)
        first.tap()
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "Actual original:1 paragraph."), object: paragraph)], timeout: 30), .completed)
        ReadingUIInteraction.assertReaderViewport(app); capture(app, "reader-contents-changed-" + device)
        openContents(app); XCTAssertTrue(first.waitForExistence(timeout: 15)); XCTAssertTrue(first.isSelected)
        app.buttons["ebook-reader-contents-close"].tap()
        XCTAssertFalse(app.buttons["ebook-previous-section"].isEnabled)
        app.buttons["ebook-next-section"].tap()
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "Actual original:2 paragraph."), object: paragraph)], timeout: 30), .completed)
        capture(app, "reader-contents-next-" + device)
    }
    private func openContents(_ app: XCUIApplication) {
        let menu = app.buttons["ebook-reader-menu"]; XCTAssertTrue(menu.waitForExistence(timeout: 15)); ReadingUIInteraction.tapVisible(menu, in: app)
        app.buttons["ebook-reader-contents-action"].tap()
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}

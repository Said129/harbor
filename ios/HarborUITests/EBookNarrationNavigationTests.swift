import XCTest

@MainActor final class EBookNarrationNavigationTests: XCTestCase {
    func testVoiceSearchSelectionRestorationAndRotatedPanelOnIPhone() { verify("iphone") }
    func testVoiceSearchSelectionRestorationAndRotatedPanelOnIPad() { verify("ipad") }
    private func verify(_ device: String) {
        continueAfterFailure = false; XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication(); app.launchArguments = ["-uiLanguage", "en", "-nativeGuide.initialized.v1", "YES", "-nativeGuide.completed.v1", "YES"]
        app.launch(); defer { app.terminate(); XCUIDevice.shared.orientation = .portrait }; openBook(app)
        let options = app.buttons["ebook-narration-options"]; XCTAssertTrue(options.waitForExistence(timeout: 20)); options.tap()
        let ava = app.buttons["ebook-narration-voice-en-US-AvaNeural"]; XCTAssertTrue(ava.waitForExistence(timeout: 15))
        capture(app, "reader-narration-voices-" + device)
        let search = app.searchFields.firstMatch; XCTAssertTrue(search.waitForExistence(timeout: 10)); search.tap(); search.typeText("Aria")
        let aria = app.buttons["ebook-narration-voice-en-US-AriaNeural"]; XCTAssertTrue(aria.waitForExistence(timeout: 15)); XCTAssertFalse(ava.exists)
        capture(app, "reader-narration-search-" + device); aria.tap()
        XCTAssertEqual(aria.value as? String, "Selected"); capture(app, "reader-narration-selected-" + device)
        let done = app.buttons["ebook-narration-done"]; XCTAssertTrue(done.isHittable); done.tap()
        app.terminate(); app.launch(); openBook(app); XCTAssertTrue(options.waitForExistence(timeout: 20)); options.tap()
        let restoredSearch = app.searchFields.firstMatch; XCTAssertTrue(restoredSearch.waitForExistence(timeout: 15)); restoredSearch.tap(); restoredSearch.typeText("Aria")
        XCTAssertTrue(aria.waitForExistence(timeout: 15)); ReadingUIInteraction.reveal(aria, in: app); XCTAssertEqual(aria.value as? String, "Selected")
        capture(app, "reader-narration-restored-" + device)
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(done.waitForExistence(timeout: 15)); XCTAssertTrue(done.isHittable)
        capture(app, "reader-narration-rotated-" + device); done.tap()
        XCTAssertTrue(app.buttons["ebook-narration-play"].waitForExistence(timeout: 15))
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
        let read = app.buttons["ebook-detail-read"]; XCTAssertTrue(read.waitForExistence(timeout: 20)); ReadingUIInteraction.reveal(read, in: app); read.tap()
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}

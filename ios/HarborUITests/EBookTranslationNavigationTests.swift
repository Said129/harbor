import XCTest

@MainActor final class EBookTranslationNavigationTests: XCTestCase {
    func testCachedChapterOriginalToggleAndProfileTranslationSettingsOnIPhone() { verify("iphone") }
    func testCachedChapterOriginalToggleAndProfileTranslationSettingsOnIPad() { verify("ipad") }
    private func verify(_ device: String) {
        continueAfterFailure = false; XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication(); app.launchArguments = ["-uiLanguage", "en", "-nativeGuide.initialized.v1", "YES", "-nativeGuide.completed.v1", "YES"]
        app.launch(); defer { app.terminate() }; openBook(app)
        expect("Capítulo traducido original:3.", in: app)
        let translation = app.buttons["ebook-translate-chapter"]
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: translation)], timeout: 15), .completed)
        XCTAssertEqual(translation.label, "Show original language"); capture(app, "reader-translation-cached-" + device)
        translation.tap(); expect("Actual original:3 paragraph.", in: app)
        XCTAssertEqual(translation.label, "Show translation"); capture(app, "reader-translation-original-" + device)
        translation.tap(); expect("Capítulo traducido original:3.", in: app)
        openSettings(app); capture(app, "reader-translation-settings-" + device)
        let language = app.buttons["ebook-translation-language"]; XCTAssertTrue(language.waitForExistence(timeout: 15)); ReadingUIInteraction.reveal(language, in: app); language.tap()
        let french = app.buttons["Français"]; XCTAssertTrue(french.waitForExistence(timeout: 10)); french.tap()
        let model = app.buttons["ebook-translation-model"]; ReadingUIInteraction.reveal(model, in: app); model.tap()
        let pro = app.buttons["DeepSeek V4 Pro"]; XCTAssertTrue(pro.waitForExistence(timeout: 10)); pro.tap()
        let enabled = app.switches["ebook-translation-enabled"]; ReadingUIInteraction.reveal(enabled, in: app); enabled.tap()
        capture(app, "reader-translation-choices-" + device)
        let test = app.buttons["ebook-translation-test"]; ReadingUIInteraction.reveal(test, in: app); XCTAssertFalse(test.isEnabled, "The fresh guest has no API key; this UI test must not send a paid request")
        let save = app.buttons["ebook-translation-save"]; ReadingUIInteraction.reveal(save, in: app); save.tap()
        let message = app.staticTexts["ebook-translation-message"]; XCTAssertTrue(message.waitForExistence(timeout: 15)); XCTAssertEqual(message.label, "Saved")
        capture(app, "reader-translation-saved-" + device)
        app.terminate(); app.launch(); openBook(app)
        expect("Actual original:3 paragraph.", in: app)
        openSettings(app)
        XCTAssertTrue(language.waitForExistence(timeout: 15)); XCTAssertTrue((language.label + " " + (language.value as? String ?? "")).contains("Français"))
        XCTAssertTrue(model.waitForExistence(timeout: 15)); XCTAssertTrue((model.label + " " + (model.value as? String ?? "")).contains("DeepSeek V4 Pro")); XCTAssertEqual(enabled.value as? String, "1")
        ReadingUIInteraction.reveal(test, in: app); XCTAssertFalse(test.isEnabled); capture(app, "reader-translation-restored-" + device)
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
    private func openSettings(_ app: XCUIApplication) {
        let menu = app.buttons["ebook-reader-menu"]; XCTAssertTrue(menu.waitForExistence(timeout: 15)); ReadingUIInteraction.tapVisible(menu, in: app)
        app.buttons["ebook-reader-settings-action"].tap()
        let link = app.buttons["ebook-reader-translation-settings"]; XCTAssertTrue(link.waitForExistence(timeout: 15)); ReadingUIInteraction.reveal(link, in: app); link.tap()
    }
    private func expect(_ text: String, in app: XCUIApplication) {
        let paragraph = app.staticTexts.matching(identifier: "ebook-reader-text").firstMatch
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", text), object: paragraph)], timeout: 30), .completed)
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}

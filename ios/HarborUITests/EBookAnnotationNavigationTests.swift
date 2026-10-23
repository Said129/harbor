import XCTest

@MainActor final class EBookAnnotationNavigationTests: XCTestCase {
    func testOwnedNativeSelectionNoteStylingReferencesEditingAndDeletionOnIPhone() { verify("iphone") }
    func testOwnedNativeSelectionNoteStylingReferencesEditingAndDeletionOnIPad() { verify("ipad") }
    private func verify(_ device: String) {
        continueAfterFailure = false; XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication(); app.launchArguments = ["-uiLanguage", "en", "-nativeGuide.initialized.v1", "YES", "-nativeGuide.completed.v1", "YES"]
        app.launch(); defer { app.terminate() }; openBook(app)
        let paragraph = app.staticTexts.matching(identifier: "ebook-reader-text").firstMatch
        expect("Actual original:3 paragraph.", paragraph)
        let open = app.buttons["ebook-note-open-selection"]
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: open)], timeout: 20), .completed)
        open.tap()
        let selection = app.textViews["ebook-note-selection-text"]; XCTAssertTrue(selection.waitForExistence(timeout: 15))
        XCTAssertTrue((selection.value as? String ?? "").contains("Actual original:3 paragraph.")); capture(app, "reader-notes-selection-" + device)
        app.buttons["ebook-note-create-action"].tap()
        let title = app.textFields["ebook-note-title"]; XCTAssertTrue(title.waitForExistence(timeout: 15)); title.tap(); title.typeText("Owned note")
        let body = app.textViews["ebook-note-body"]; ReadingUIInteraction.reveal(body, in: app); body.tap(); body.typeText("Reader note")
        let blue = app.buttons["ebook-note-ink-#9fc8dd"]; ReadingUIInteraction.reveal(blue, in: app); blue.tap()
        let density = app.sliders["ebook-note-density"]; ReadingUIInteraction.reveal(density, in: app); density.adjust(toNormalizedSliderPosition: 0.5)
        let tags = app.textFields["ebook-note-tags"]; ReadingUIInteraction.reveal(tags, in: app); tags.tap(); tags.typeText("study, quote")
        capture(app, "reader-notes-editor-" + device)
        let save = app.buttons["ebook-note-save"]; ReadingUIInteraction.reveal(save, in: app); save.tap()
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: save)], timeout: 20), .completed)
        expect("Actual original:3 paragraph.", paragraph); ReadingUIInteraction.assertReaderViewport(app)
        value("Owned note", paragraph)
        capture(app, "reader-notes-highlighted-" + device)
        app.buttons["ebook-next-section"].tap(); expect("Actual original:2 paragraph.", paragraph)
        value("Owned reference", paragraph)
        capture(app, "reader-notes-reference-" + device)
        app.terminate(); app.launch(); openBook(app); expect("Actual original:2 paragraph.", paragraph)
        openList(app)
        let owned = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "ebook-note-card-", "Owned note")).firstMatch
        XCTAssertTrue(owned.waitForExistence(timeout: 15)); owned.tap()
        XCTAssertTrue(title.waitForExistence(timeout: 15)); XCTAssertEqual(title.value as? String, "Owned note")
        ReadingUIInteraction.reveal(body, in: app); XCTAssertEqual(body.value as? String, "Reader note")
        ReadingUIInteraction.reveal(tags, in: app); XCTAssertEqual(tags.value as? String, "study, quote")
        capture(app, "reader-notes-restored-" + device)
        let jump = app.buttons["ebook-note-jump"]; ReadingUIInteraction.reveal(jump, in: app); jump.tap()
        expect("Actual original:3 paragraph.", paragraph)
        openList(app); XCTAssertTrue(owned.waitForExistence(timeout: 15)); owned.tap(); XCTAssertTrue(title.waitForExistence(timeout: 15))
        let remove = app.buttons["ebook-note-delete"]; ReadingUIInteraction.reveal(remove, in: app); remove.tap()
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: remove)], timeout: 20), .completed)
        openList(app); XCTAssertFalse(owned.exists)
        XCTAssertTrue(app.buttons["ebook-note-card-owned-reference"].waitForExistence(timeout: 15))
        capture(app, "reader-notes-deleted-" + device)
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
    private func openList(_ app: XCUIApplication) {
        let menu = app.buttons["ebook-reader-menu"]; XCTAssertTrue(menu.waitForExistence(timeout: 15)); ReadingUIInteraction.tapVisible(menu, in: app)
        let action = app.buttons["ebook-notes-action"]; XCTAssertTrue(action.waitForExistence(timeout: 10)); action.tap()
    }
    private func expect(_ text: String, _ paragraph: XCUIElement) {
        let outcome = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", text), object: paragraph)], timeout: 30)
        if outcome != .completed {
            let hierarchy = XCTAttachment(string: XCUIApplication().debugDescription); hierarchy.name = "reader-notes-visible-text-hierarchy"; hierarchy.lifetime = .keepAlways; add(hierarchy)
            capture(XCUIApplication(), "reader-notes-visible-text-failure")
        }
        XCTAssertEqual(outcome, .completed)
    }
    private func value(_ text: String, _ paragraph: XCUIElement) {
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", text), object: paragraph)], timeout: 20), .completed)
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}

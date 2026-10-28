import XCTest

@MainActor final class CustomListNavigationTests: XCTestCase {
    func testOwnedListsCreateEditOrderMembershipRemoveAndRestoreOnIPhone() { verify("iphone") }
    func testOwnedListsCreateEditOrderMembershipRemoveAndRestoreOnIPad() { verify("ipad") }
    private func verify(_ device: String) {
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "site.harbor.iphone")
        app.launchArguments = ["-uiLanguage", "en", "-homeMode", "classic", "-nativeGuide.initialized.v1", "YES", "-nativeGuide.completed.v1", "YES"]
        ReadingUIInteraction.launchPreparedApplication(app)
        defer { if (testRun?.failureCount ?? 0) > 0 { ReadingUIInteraction.recordFailureContext(app) }; app.terminate() }
        openLists(app)
        XCTAssertEqual(app.staticTexts["custom-lists-count"].label, "2 / 24 lists")
        capture(app, "custom-lists-cards-" + device)
        let weekend = card("Owned weekend", in: app)
        ReadingUIInteraction.tapVisible(weekend, in: app)
        XCTAssertTrue(app.staticTexts["custom-list-title"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["custom-list-title"].label, "Owned weekend")
        XCTAssertTrue(app.staticTexts["custom-list-item-count"].label.hasPrefix("2 / 100 items"))
        capture(app, "custom-list-detail-" + device)
        let remove = app.buttons.matching(NSPredicate(format: "identifier == %@ AND label == %@", "custom-list-item-remove", "Remove from list: Owned film A")).firstMatch
        ReadingUIInteraction.tapVisible(remove, in: app)
        waitLabel(app.staticTexts["custom-list-item-count"], prefix: "1 / 100 items")
        ReadingUIInteraction.tapVisible(app.buttons["custom-list-back"], in: app)
        ReadingUIInteraction.tapVisible(app.buttons["custom-list-create"], in: app)
        let name = app.textFields["custom-list-name"]; XCTAssertTrue(name.waitForExistence(timeout: 10)); name.tap(); name.typeText("Owned mobile list")
        let description = app.textFields["custom-list-description"].exists ? app.textFields["custom-list-description"] : app.textViews["custom-list-description"]
        ReadingUIInteraction.tapVisible(description, in: app); description.typeText("Owned description")
        ReadingUIInteraction.tapVisible(app.buttons["custom-list-editor-save"], in: app)
        waitLabel(app.staticTexts["custom-list-title"], prefix: "Owned mobile list")
        XCTAssertTrue(app.staticTexts["custom-list-empty"].exists || app.staticTexts["Nothing here yet"].exists)
        capture(app, "custom-list-created-" + device)
        ReadingUIInteraction.tapVisible(app.buttons["custom-list-settings"], in: app)
        ReadingUIInteraction.tapVisible(app.buttons["Rename list"], in: app)
        let rename = app.textFields["custom-list-name"]; XCTAssertTrue(rename.waitForExistence(timeout: 5))
        rename.tap(); rename.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: "Owned mobile list".count) + "Owned renamed")
        ReadingUIInteraction.tapVisible(app.buttons["custom-list-editor-save"], in: app)
        waitLabel(app.staticTexts["custom-list-title"], prefix: "Owned renamed")
        ReadingUIInteraction.tapVisible(app.buttons["custom-list-back"], in: app)
        let renamed = card("Owned renamed", in: app); XCTAssertTrue(renamed.waitForExistence(timeout: 5)); renamed.press(forDuration: 1)
        ReadingUIInteraction.tapVisible(app.buttons["Move down"], in: app)
        ReadingUIInteraction.tapVisible(renamed, in: app)
        ReadingUIInteraction.tapVisible(app.buttons["custom-list-settings"], in: app)
        ReadingUIInteraction.tapVisible(app.buttons["Delete list"], in: app)
        ReadingUIInteraction.tapVisible(app.buttons["custom-list-delete-confirm"], in: app)
        XCTAssertTrue(card("Owned weekend", in: app).waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["custom-lists-count"].label, "2 / 24 lists")
        ReadingUIInteraction.tapVisible(card("Owned weekend", in: app), in: app)
        let film = app.buttons.matching(NSPredicate(format: "identifier == %@ AND label == %@", "custom-list-item", "Owned film B")).firstMatch
        ReadingUIInteraction.tapVisible(film, in: app)
        ReadingUIInteraction.tapVisible(app.buttons["detail-custom-lists"], in: app)
        let membership = app.buttons.matching(NSPredicate(format: "identifier == %@ AND label BEGINSWITH %@", "custom-list-membership", "Owned rewatches")).firstMatch
        XCTAssertTrue(membership.waitForExistence(timeout: 10)); ReadingUIInteraction.tapVisible(membership, in: app)
        let added = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "Added"), object: membership)
        XCTAssertEqual(XCTWaiter.wait(for: [added], timeout: 10), .completed)
        capture(app, "custom-list-membership-" + device)
        ReadingUIInteraction.tapVisible(app.buttons["Done"], in: app)
        app.terminate(); ReadingUIInteraction.launchPreparedApplication(app); openLists(app)
        ReadingUIInteraction.tapVisible(card("Owned rewatches", in: app), in: app)
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier == %@ AND label == %@", "custom-list-item", "Owned film B")).firstMatch.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["custom-list-item-count"].label.hasPrefix("1 / 100 items"))
    }
    private func openLists(_ app: XCUIApplication) {
        let menu = app.buttons["main-menu"]; XCTAssertTrue(menu.waitForExistence(timeout: 45)); ReadingUIInteraction.tapVisible(menu, in: app)
        let navigation = app.descendants(matching: .any).matching(identifier: "navigation-scroll").firstMatch
        let library = app.buttons["nav-library"]; ReadingUIInteraction.reveal(library, in: app, container: navigation); ReadingUIInteraction.tapVisible(library, in: app)
        let bar = app.scrollViews["library-filter"]; XCTAssertTrue(bar.waitForExistence(timeout: 15))
        let lists = app.buttons["library-tab-custom-lists"]
        ReadingUIInteraction.revealHorizontally(lists, in: app, container: bar); ReadingUIInteraction.tapVisible(lists, in: app)
        XCTAssertTrue(app.buttons["custom-list-create"].waitForExistence(timeout: 10))
    }
    private func card(_ name: String, in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "identifier == %@ AND label == %@", "custom-list-card", name)).firstMatch
    }
    private func waitLabel(_ element: XCUIElement, prefix: String) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label BEGINSWITH %@", prefix), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 10), .completed)
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        Thread.sleep(forTimeInterval: 0.55)
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}

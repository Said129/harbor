import XCTest

@MainActor final class CustomListLocalizationNavigationTests: XCTestCase {
    func testFreshListTimestampAndDetailActionsUseTheSelectedEnglishLanguageOnIPhone() { verify("iphone") }
    func testFreshListTimestampAndDetailActionsUseTheSelectedEnglishLanguageOnIPad() { verify("ipad") }
    private func verify(_ device: String) {
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "site.harbor.iphone")
        app.launchArguments = ["-uiLanguage", "en", "-homeMode", "classic", "-nativeGuide.initialized.v1", "YES", "-nativeGuide.completed.v1", "YES"]
        ReadingUIInteraction.launchPreparedApplication(app)
        defer { if (testRun?.failureCount ?? 0) > 0 { ReadingUIInteraction.recordFailureContext(app) }; app.terminate() }
        XCTAssertTrue(app.buttons["main-menu"].waitForExistence(timeout: 45)); ReadingUIInteraction.tapVisible(app.buttons["main-menu"], in: app)
        let navigation = app.scrollViews["navigation-scroll"]
        XCTAssertTrue(navigation.waitForExistence(timeout: 15))
        let library = navigation.buttons["nav-library"]
        let visible = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            guard library.exists else { return false }
            let frame = library.frame
            return !frame.isNull && !frame.isInfinite && frame.width > 1 && frame.height > 1
                && app.frame.contains(CGPoint(x: frame.midX, y: frame.midY))
        }, object: nil)
        let hierarchy = XCTAttachment(string: app.debugDescription); hierarchy.name = "localization-open-navigation-hierarchy"; hierarchy.lifetime = .keepAlways; add(hierarchy)
        XCTAssertEqual(XCTWaiter.wait(for: [visible], timeout: 15), .completed, "Wait for the real sidebar destination inside the application viewport")
        library.coordinate(withNormalizedOffset: .init(dx: 0.5, dy: 0.5)).tap()
        let bar = app.scrollViews["library-filter"]; XCTAssertTrue(bar.waitForExistence(timeout: 15))
        let lists = app.buttons["library-tab-custom-lists"]; ReadingUIInteraction.revealHorizontally(lists, in: app, container: bar); ReadingUIInteraction.tapVisible(lists, in: app)
        ReadingUIInteraction.tapVisible(app.buttons["custom-list-create"], in: app)
        let name = app.textFields["custom-list-name"]; XCTAssertTrue(name.waitForExistence(timeout: 10)); name.tap(); name.typeText("Owned localized list")
        ReadingUIInteraction.tapVisible(app.buttons["custom-list-editor-save"], in: app)
        let count = app.staticTexts["custom-list-item-count"]; XCTAssertTrue(count.waitForExistence(timeout: 10))
        XCTAssertTrue(count.label.hasPrefix("0 / 100 items")); XCTAssertTrue(count.label.contains("Updated")); XCTAssertFalse(count.label.contains("in 0s"))
        capture(app, "custom-list-recent-localized-" + device)
        ReadingUIInteraction.tapVisible(app.buttons["custom-list-back"], in: app)
        let weekend = app.buttons.matching(NSPredicate(format: "identifier == %@ AND label == %@", "custom-list-card", "Owned weekend")).firstMatch
        ReadingUIInteraction.reveal(weekend, in: app); ReadingUIInteraction.tapVisible(weekend, in: app)
        let film = app.buttons.matching(NSPredicate(format: "identifier == %@ AND label == %@", "custom-list-item", "Owned film B")).firstMatch
        ReadingUIInteraction.tapVisible(film, in: app)
        let bookmark = app.buttons["detail-bookmark"]; XCTAssertTrue(bookmark.waitForExistence(timeout: 10)); ReadingUIInteraction.reveal(bookmark, in: app)
        XCTAssertEqual(bookmark.label, "Add to Watchlist")
        let error = app.staticTexts["detail-metadata-error"]; XCTAssertTrue(error.waitForExistence(timeout: 10))
        ReadingUIInteraction.reveal(error, in: app)
        XCTAssertEqual(error.label, "The addons did not return metadata for this title.")
        capture(app, "custom-list-detail-localized-" + device)
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        Thread.sleep(forTimeInterval: 0.55)
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}

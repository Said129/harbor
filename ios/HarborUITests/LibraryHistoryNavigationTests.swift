import XCTest

@MainActor final class LibraryHistoryNavigationTests: XCTestCase {
    func testIndependentHistorySwitchesModesSearchesConfirmsRemovalAndRestoresOnIPhone() { verify("iphone") }
    func testIndependentHistorySwitchesModesSearchesConfirmsRemovalAndRestoresOnIPad() { verify("ipad") }
    func testEpisodeCaptionUsesTheEnglishCatalogOnIPhone() { verifyCaption("iphone") }
    func testEpisodeCaptionUsesTheEnglishCatalogOnIPad() { verifyCaption("ipad") }
    private func verifyCaption(_ device: String) {
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "site.harbor.iphone")
        app.launchArguments = ["-uiLanguage", "en", "-homeMode", "classic", "-nativeGuide.initialized.v1", "YES", "-nativeGuide.completed.v1", "YES"]
        ReadingUIInteraction.launchPreparedApplication(app)
        defer { if (testRun?.failureCount ?? 0) > 0 { ReadingUIInteraction.recordFailureContext(app) }; app.terminate() }
        openHistory(app)
        ReadingUIInteraction.tapVisible(app.buttons["library-history-view-episodes"], in: app)
        let card = app.buttons.matching(NSPredicate(format: "identifier == %@ AND label == %@", "library-history-media", "Owned episode")).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        let localized = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "S5 E23"), object: card)
        XCTAssertEqual(XCTWaiter.wait(for: [localized], timeout: 10), .completed)
        capture(app, "library-history-episode-caption-" + device)
    }
    private func verify(_ device: String) {
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "site.harbor.iphone")
        app.launchArguments = ["-uiLanguage", "en", "-homeMode", "classic", "-nativeGuide.initialized.v1", "YES", "-nativeGuide.completed.v1", "YES"]
        ReadingUIInteraction.launchPreparedApplication(app)
        defer { if (testRun?.failureCount ?? 0) > 0 { ReadingUIInteraction.recordFailureContext(app) }; app.terminate() }
        openHistory(app)
        XCTAssertTrue(app.buttons["library-history-view-posters"].isSelected)
        capture(app, "library-history-posters-" + device)
        ReadingUIInteraction.tapVisible(app.buttons["library-history-view-episodes"], in: app)
        let episodes = XCTNSPredicateExpectation(predicate: NSPredicate(format: "selected == true"), object: app.buttons["library-history-view-episodes"])
        XCTAssertEqual(XCTWaiter.wait(for: [episodes], timeout: 5), .completed)
        capture(app, "library-history-episodes-" + device)
        let search = app.textFields.firstMatch; XCTAssertTrue(search.isHittable); search.tap(); search.typeText("Nothing matches\n")
        XCTAssertTrue(app.staticTexts["library-history-no-matches"].waitForExistence(timeout: 10))
        ReadingUIInteraction.tapVisible(app.buttons["Clear search"], in: app)
        XCTAssertTrue(app.buttons["Owned episode"].waitForExistence(timeout: 10))
        let remove = app.buttons.matching(identifier: "library-history-remove").firstMatch
        ReadingUIInteraction.tapVisible(remove, in: app)
        let confirmation = app.buttons["Remove"]; XCTAssertTrue(confirmation.waitForExistence(timeout: 5)); ReadingUIInteraction.tapVisible(confirmation, in: app)
        let count = app.staticTexts["library-history-count"]
        let changed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "2 items"), object: count)
        XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 10), .completed)
        capture(app, "library-history-removed-" + device)
        app.terminate(); ReadingUIInteraction.launchPreparedApplication(app); openHistory(app)
        XCTAssertTrue(app.buttons["library-history-view-episodes"].isSelected)
        XCTAssertEqual(app.staticTexts["library-history-count"].label, "2 items")
    }
    private func openHistory(_ app: XCUIApplication) {
        let menu = app.buttons["main-menu"]; XCTAssertTrue(menu.waitForExistence(timeout: 45)); ReadingUIInteraction.tapVisible(menu, in: app)
        let navigation = app.descendants(matching: .any).matching(identifier: "navigation-scroll").firstMatch
        let library = app.buttons["nav-library"]; ReadingUIInteraction.reveal(library, in: app, container: navigation); ReadingUIInteraction.tapVisible(library, in: app)
        let bar = app.scrollViews["library-filter"]; XCTAssertTrue(bar.waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["Your collection."].exists)
        let history = app.buttons["library-tab-watched"]
        XCTAssertEqual(history.label, "History")
        ReadingUIInteraction.revealHorizontally(history, in: app, container: bar)
        ReadingUIInteraction.tapVisible(history, in: app)
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "library-history-content").firstMatch.waitForExistence(timeout: 15))
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        Thread.sleep(forTimeInterval: 0.55)
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}

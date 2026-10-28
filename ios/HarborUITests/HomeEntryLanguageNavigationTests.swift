import XCTest

@MainActor final class HomeEntryLanguageNavigationTests: XCTestCase {
    func testHeroLabelsAndCollapsedSeasonalEntryStayEnglishAndReopenOnIPhone() { verify("iphone") }
    func testHeroLabelsAndCollapsedSeasonalEntryStayEnglishAndReopenOnIPad() { verify("ipad") }
    private func verify(_ device: String) {
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "site.harbor.iphone")
        app.launchArguments = ["-uiLanguage", "en", "-homeMode", "harbor", "-nativeGuide.initialized.v1", "YES", "-nativeGuide.completed.v1", "YES"]
        ReadingUIInteraction.launchPreparedApplication(app)
        defer { if (testRun?.failureCount ?? 0) > 0 { ReadingUIInteraction.recordFailureContext(app) }; app.terminate() }
        let scroll = app.scrollViews["home-scroll"]; XCTAssertTrue(scroll.waitForExistence(timeout: 45))
        XCTAssertTrue(app.staticTexts["Owned hero film"].waitForExistence(timeout: 30), "Wait for the owned saved hero, rather than testing a default public title")
        let bookmark = app.buttons["hero-bookmark"]; XCTAssertTrue(bookmark.waitForExistence(timeout: 20))
        ReadingUIInteraction.reveal(bookmark, in: app, up: false, container: scroll)
        XCTAssertEqual(bookmark.label, "Add to Watchlist")
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: bookmark)
        XCTAssertEqual(XCTWaiter.wait(for: [enabled], timeout: 20), .completed)
        ReadingUIInteraction.tapVisible(bookmark, in: app)
        let saved = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "In Watchlist"), object: bookmark)
        XCTAssertEqual(XCTWaiter.wait(for: [saved], timeout: 15), .completed)
        XCTAssertEqual(app.buttons["hero-play"].label, "Play")
        XCTAssertEqual(app.staticTexts["hero-eyebrow"].label, "FEATURED TONIGHT")
        capture(app, "home-labels-movie-" + device)
        let customize = app.buttons["page-customize"]
        ReadingUIInteraction.reveal(customize, in: app, container: scroll); ReadingUIInteraction.tapVisible(customize, in: app)
        let controls = app.descendants(matching: .any).matching(identifier: "page-row-controls-list-owned-hero-manga").firstMatch
        ReadingUIInteraction.revealWithinViewport(controls, in: app, container: scroll)
        ReadingUIInteraction.tapVisible(controls.buttons["Feature this catalog in the hero carousel"], in: app)
        ReadingUIInteraction.tapVisible(app.buttons["page-customize-done"], in: app)
        let information = app.buttons["hero-more-info"]
        ReadingUIInteraction.reveal(information, in: app, up: false, container: scroll)
        XCTAssertTrue(information.waitForExistence(timeout: 10)); XCTAssertEqual(information.label, "More info")
        XCTAssertEqual(app.buttons["hero-play"].label, "Read")
        let invitation = app.buttons["spooktober-open"]
        ReadingUIInteraction.revealWithinViewport(invitation, in: app, container: scroll)
        XCTAssertTrue(invitation.label.contains("Films, music & midnight discoveries."))
        let dismiss = app.buttons["spooktober-dismiss"]; XCTAssertEqual(dismiss.label, "Dismiss Spooktober")
        capture(app, "home-labels-expanded-" + device)
        ReadingUIInteraction.tapVisible(dismiss, in: app)
        let collapsed = app.buttons["spooktober-open-collapsed"]
        XCTAssertTrue(collapsed.waitForExistence(timeout: 10)); XCTAssertFalse(invitation.exists)
        XCTAssertGreaterThanOrEqual(collapsed.frame.height, 44)
        capture(app, "home-labels-collapsed-" + device)
        app.terminate(); ReadingUIInteraction.launchPreparedApplication(app)
        XCTAssertTrue(scroll.waitForExistence(timeout: 45))
        ReadingUIInteraction.reveal(collapsed, in: app, container: scroll)
        XCTAssertTrue(collapsed.waitForExistence(timeout: 10)); XCTAssertFalse(app.buttons["spooktober-dismiss"].exists)
        ReadingUIInteraction.tapVisible(collapsed, in: app)
        XCTAssertTrue(app.scrollViews["spooktober-scroll"].waitForExistence(timeout: 20))
        capture(app, "home-labels-reopened-" + device)
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        Thread.sleep(forTimeInterval: 0.55)
        let capture = XCTAttachment(screenshot: app.screenshot()); capture.name = name; capture.lifetime = .keepAlways; add(capture)
    }
}

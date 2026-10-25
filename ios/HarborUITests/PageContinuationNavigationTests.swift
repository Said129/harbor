import XCTest

@MainActor final class PageContinuationNavigationTests: XCTestCase {
    func testAnimeContinueRowMovesRenamesHidesAndRestoresAfterRelaunchOnIPhone() { verify("iphone") }
    func testAnimeContinueRowMovesRenamesHidesAndRestoresAfterRelaunchOnIPad() { verify("ipad") }
    func testOtherWatcherBadgeCoexistsWithAnimeCustomizationOnIPhone() { verify("iphone", watcher: true) }
    func testOtherWatcherBadgeCoexistsWithAnimeCustomizationOnIPad() { verify("ipad", watcher: true) }
    private func verify(_ device: String, watcher: Bool = false) {
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "site.harbor.iphone")
        app.launchArguments = ["-uiLanguage", "en", "-nativeGuide.initialized.v1", "YES", "-nativeGuide.completed.v1", "YES"]
        ReadingUIInteraction.launchPreparedApplication(app)
        defer {
            if (testRun?.failureCount ?? 0) > 0 { ReadingUIInteraction.recordFailureContext(app) }
            app.terminate()
        }
        navigate(app)
        let scroll = app.scrollViews["content-anime"], row = app.staticTexts["anime-continue-watching-title"]
        ReadingUIInteraction.reveal(row, in: app, container: scroll)
        XCTAssertTrue(row.waitForExistence(timeout: 30)); ReadingUIInteraction.revealWithinViewport(row, in: app, container: scroll)
        if watcher { verifyWatcher(app) }
        XCTAssertEqual(row.label, "Continue Watching"); capture(app, "anime-continue-initial-" + device)
        let customize = app.buttons["page-customize"]
        ReadingUIInteraction.reveal(customize, in: app, up: false, container: scroll); ReadingUIInteraction.tapVisible(customize, in: app)
        let controls = element("page-row-controls-continueWatching", app)
        ReadingUIInteraction.reveal(controls, in: app, container: scroll)
        XCTAssertTrue(controls.waitForExistence(timeout: 15)); ReadingUIInteraction.revealWithinViewport(controls, in: app, container: scroll)
        XCTAssertFalse(controls.buttons["Move up"].isEnabled)
        XCTAssertFalse(controls.buttons["Needs at least 10 titles for the Top 10 look"].exists)
        XCTAssertFalse(controls.buttons["Needs artwork-rich titles to feed the hero"].exists)
        capture(app, "anime-continue-editing-" + device)
        let down = controls.buttons["Move down"]; XCTAssertTrue(down.isEnabled); ReadingUIInteraction.tapVisible(down, in: app)
        ReadingUIInteraction.revealWithinViewport(controls, in: app, container: scroll)
        XCTAssertTrue(controls.buttons["Move up"].isEnabled)
        capture(app, "anime-continue-moved-" + device)
        ReadingUIInteraction.tapVisible(controls.buttons["Rename row"], in: app)
        let name = app.textFields["page-row-name-continueWatching"]
        XCTAssertTrue(name.waitForExistence(timeout: 10)); ReadingUIInteraction.replace(name, with: "Owned anime row", in: app); name.typeText("\n")
        XCTAssertTrue(controls.staticTexts["Owned anime row"].waitForExistence(timeout: 10))
        ReadingUIInteraction.revealWithinViewport(controls, in: app, container: scroll); capture(app, "anime-continue-renamed-" + device)
        ReadingUIInteraction.tapVisible(controls.buttons["Hide row"], in: app)
        let hidden = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in !row.exists }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [hidden], timeout: 10), .completed)
        capture(app, "anime-continue-hidden-" + device)
        ReadingUIInteraction.tapVisible(controls.buttons["Show row"], in: app)
        ReadingUIInteraction.reveal(customize, in: app, up: false, container: scroll); ReadingUIInteraction.tapVisible(customize, in: app)
        app.terminate(); ReadingUIInteraction.launchPreparedApplication(app); navigate(app)
        let preceding = app.staticTexts["Trending on AniList"]
        ReadingUIInteraction.reveal(preceding, in: app, container: scroll)
        XCTAssertTrue(preceding.waitForExistence(timeout: 30)); ReadingUIInteraction.revealWithinViewport(preceding, in: app, container: scroll)
        XCTAssertTrue(row.waitForExistence(timeout: 10)); XCTAssertLessThan(preceding.frame.minY, row.frame.minY)
        ReadingUIInteraction.revealWithinViewport(row, in: app, container: scroll)
        XCTAssertEqual(row.label, "Owned anime row")
        if watcher { verifyWatcher(app) }
        XCTAssertFalse(controls.exists); capture(app, "anime-continue-restored-" + device)
    }
    private func verifyWatcher(_ app: XCUIApplication) {
        let badge = element("continue-watching-watcher", app)
        XCTAssertTrue(badge.waitForExistence(timeout: 10)); XCTAssertEqual(badge.label, "Watched by Owned watcher")
        XCTAssertGreaterThanOrEqual(badge.frame.width, 28)
        let remove = app.buttons["continue-watching-remove"]
        XCTAssertTrue(remove.exists); XCTAssertGreaterThanOrEqual(remove.frame.width, 44)
        XCTAssertFalse(badge.frame.intersects(remove.frame), "Watcher and remove controls have separate visible positions")
    }
    private func navigate(_ app: XCUIApplication) {
        let menu = app.buttons["main-menu"]; XCTAssertTrue(menu.waitForExistence(timeout: 45)); ReadingUIInteraction.tapVisible(menu, in: app)
        let navigation = element("navigation-scroll", app); XCTAssertTrue(navigation.waitForExistence(timeout: 10))
        let anime = app.buttons["nav-anime"]
        for _ in 0..<12 { if anime.isHittable { break }; navigation.swipeDown() }
        for _ in 0..<12 { if anime.isHittable { break }; navigation.swipeUp() }
        ReadingUIInteraction.tapVisible(anime, in: app)
        XCTAssertTrue(app.scrollViews["content-anime"].waitForExistence(timeout: 30))
    }
    private func element(_ id: String, _ app: XCUIApplication) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let image = XCTAttachment(screenshot: app.screenshot()); image.name = name; image.lifetime = .keepAlways; add(image)
    }
}

import XCTest

@MainActor final class CustomListHomeNavigationTests: XCTestCase {
    func testHomeListsCustomizeRestoreAndReadTheirOwnedPDFOnIPhone() { verify("iphone") }
    func testHomeListsCustomizeRestoreAndReadTheirOwnedPDFOnIPad() { verify("ipad") }
    private func verify(_ device: String) {
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "site.harbor.iphone")
        app.launchArguments = ["-uiLanguage", "en", "-homeMode", "harbor", "-nativeGuide.initialized.v1", "YES", "-nativeGuide.completed.v1", "YES"]
        ReadingUIInteraction.launchPreparedApplication(app)
        defer { if (testRun?.failureCount ?? 0) > 0 { ReadingUIInteraction.recordFailureContext(app) }; app.terminate() }
        let scroll = app.scrollViews["home-scroll"]
        XCTAssertTrue(scroll.waitForExistence(timeout: 45))
        customize(app, scroll)
        add("Owned movie picks", app: app, scroll: scroll)
        add("Owned manga picks", app: app, scroll: scroll)
        let movies = app.staticTexts["home-list-title-owned-movies"], manga = app.staticTexts["home-list-title-owned-manga"]
        ReadingUIInteraction.revealWithinViewport(manga, in: app, container: scroll)
        XCTAssertEqual(manga.label, "Owned manga picks")
        capture(app, "home-lists-added-" + device)
        let mangaControls = element("page-row-controls-list-owned-manga", app)
        ReadingUIInteraction.revealWithinViewport(mangaControls, in: app, container: scroll)
        ReadingUIInteraction.tapVisible(app.buttons["home-list-remove-owned-manga"], in: app)
        let removed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in !manga.exists }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [removed], timeout: 10), .completed)
        add("Owned manga picks", app: app, scroll: scroll)
        let controls = element("page-row-controls-list-owned-movies", app)
        ReadingUIInteraction.revealWithinViewport(controls, in: app, container: scroll)
        ReadingUIInteraction.tapVisible(controls.buttons["Rename row"], in: app)
        let name = app.textFields["page-row-name-list-owned-movies"]
        XCTAssertTrue(name.waitForExistence(timeout: 10)); ReadingUIInteraction.replace(name, with: "Owned home picks", in: app); name.typeText("\n")
        XCTAssertTrue(controls.staticTexts["Owned home picks"].waitForExistence(timeout: 10))
        ReadingUIInteraction.revealWithinViewport(controls, in: app, container: scroll)
        ReadingUIInteraction.tapVisible(controls.buttons["Hide row"], in: app)
        let hidden = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in !movies.exists }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [hidden], timeout: 10), .completed)
        ReadingUIInteraction.tapVisible(controls.buttons["Show row"], in: app)
        ReadingUIInteraction.tapVisible(controls.buttons["Show as a Top 10 with big numerals"], in: app)
        ReadingUIInteraction.tapVisible(controls.buttons["Move down"], in: app)
        ReadingUIInteraction.tapVisible(app.buttons["page-customize-done"], in: app)
        app.terminate(); ReadingUIInteraction.launchPreparedApplication(app)
        XCTAssertTrue(scroll.waitForExistence(timeout: 45))
        ReadingUIInteraction.revealWithinViewport(manga, in: app, container: scroll)
        ReadingUIInteraction.revealWithinViewport(movies, in: app, container: scroll)
        XCTAssertEqual(movies.label, "Owned home picks")
        XCTAssertLessThan(manga.frame.minY, movies.frame.minY)
        capture(app, "home-lists-restored-" + device)
        customize(app, scroll)
        ReadingUIInteraction.revealWithinViewport(mangaControls, in: app, container: scroll)
        let hero = mangaControls.buttons["Feature this catalog in the hero carousel"]
        XCTAssertTrue(hero.isEnabled); ReadingUIInteraction.tapVisible(hero, in: app)
        ReadingUIInteraction.tapVisible(app.buttons["page-customize-done"], in: app)
        let read = app.buttons["hero-play"]
        ReadingUIInteraction.reveal(read, in: app, up: false, container: scroll)
        XCTAssertTrue(read.waitForExistence(timeout: 15)); XCTAssertEqual(read.label, "Read")
        capture(app, "home-list-manga-hero-" + device)
        ReadingUIInteraction.tapVisible(read, in: app)
        let page = element("manga-page-0", app)
        XCTAssertTrue(page.waitForExistence(timeout: 20))
        XCTAssertFalse(app.staticTexts["This title would not open"].exists)
        capture(app, "home-list-manga-reader-" + device)
    }
    private func customize(_ app: XCUIApplication, _ scroll: XCUIElement) {
        let button = app.buttons["page-customize"]
        ReadingUIInteraction.reveal(button, in: app, up: false, container: scroll); ReadingUIInteraction.tapVisible(button, in: app)
        XCTAssertTrue(app.buttons["page-customize-done"].waitForExistence(timeout: 10))
    }
    private func add(_ name: String, app: XCUIApplication, scroll: XCUIElement) {
        let button = app.buttons["home-add-list"]
        ReadingUIInteraction.reveal(button, in: app, up: false, container: scroll); ReadingUIInteraction.tapVisible(button, in: app)
        let choices = app.buttons.matching(identifier: "home-add-list-choice")
        XCTAssertFalse(choices.matching(NSPredicate(format: "label == %@", "Owned empty list")).firstMatch.exists)
        let choice = choices.matching(NSPredicate(format: "label == %@", name)).firstMatch
        XCTAssertTrue(choice.waitForExistence(timeout: 10)); ReadingUIInteraction.tapVisible(choice, in: app)
    }
    private func element(_ id: String, _ app: XCUIApplication) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }
    private func capture(_ app: XCUIApplication, _ name: String) {
        Thread.sleep(forTimeInterval: 0.65)
        let capture = XCTAttachment(screenshot: app.screenshot()); capture.name = name; capture.lifetime = .keepAlways; add(capture)
    }
}

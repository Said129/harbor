import XCTest

@MainActor final class MusicExploreNavigationTests: XCTestCase {
    func testOriginalGenresFiltersLibraryIndependenceAndPublicGenreNavigationOnIPhone() { verify("iphone") }
    func testOriginalGenresFiltersLibraryIndependenceAndPublicGenreNavigationOnIPad() { verify("ipad") }
    private func verify(_ device: String) {
        continueAfterFailure = false; XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication(); app.launchArguments = ["-uiLanguage", "en", "-nativeGuide.initialized.v1", "YES", "-nativeGuide.completed.v1", "YES"]
        app.launch(); defer { app.terminate(); XCUIDevice.shared.orientation = .portrait }; navigate(app)
        let screen = app.segmentedControls["music-screen"]
        XCTAssertTrue(screen.waitForExistence(timeout: 20)); XCTAssertTrue(screen.buttons.element(boundBy: 1).isSelected)
        let scroll = app.scrollViews["music-explore-scroll"], count = app.staticTexts["music-genre-count"]
        XCTAssertTrue(scroll.waitForExistence(timeout: 15)); ReadingUIInteraction.reveal(count, in: app, container: scroll)
        XCTAssertEqual(count.label, "158 genres"); capture("music-explore-genres-" + device)
        let search = app.searchFields.firstMatch
        ReadingUIInteraction.reveal(search, in: app, up: false, container: scroll); search.tap(); search.typeText("Rock\n")
        let styles = app.buttons["music-genre-style"]
        ReadingUIInteraction.reveal(styles, in: app, container: scroll); ReadingUIInteraction.tapVisible(styles, in: app)
        let guitars = app.buttons["Rock & metal"].firstMatch; XCTAssertTrue(guitars.waitForExistence(timeout: 10)); guitars.tap()
        chooseCountry("United States", app: app, scroll: scroll); chooseCountry("United Kingdom", app: app, scroll: scroll)
        let rock = app.buttons["music-genre-152"]
        ReadingUIInteraction.reveal(rock, in: app, container: scroll)
        XCTAssertFalse(app.buttons["music-genre-116"].exists); capture("music-explore-filtered-" + device)
        ReadingUIInteraction.reveal(screen, in: app, up: false, container: scroll); ReadingUIInteraction.tapVisible(screen.buttons.element(boundBy: 2), in: app)
        XCTAssertTrue(app.segmentedControls["music-library-category"].waitForExistence(timeout: 15))
        XCTAssertNotEqual(search.value as? String, "Rock"); capture("music-explore-library-" + device)
        ReadingUIInteraction.tapVisible(screen.buttons.element(boundBy: 1), in: app)
        ReadingUIInteraction.reveal(rock, in: app, container: scroll); ReadingUIInteraction.tapVisible(rock, in: app)
        XCTAssertTrue(app.staticTexts["music-genre-detail-title"].waitForExistence(timeout: 15))
        XCTAssertEqual(app.staticTexts["music-genre-detail-title"].label, "Rock")
        let track = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'music-genre-track-deezer:track:'")).firstMatch
        ReadingUIInteraction.reveal(track, in: app, container: app.scrollViews["music-genre-detail-scroll"])
        capture("music-explore-genre-" + device)
        app.terminate(); app.launch(); navigate(app)
        XCTAssertTrue(screen.waitForExistence(timeout: 20)); XCTAssertTrue(screen.buttons.element(boundBy: 1).isSelected)
        ReadingUIInteraction.reveal(search, in: app, up: false, container: scroll); XCTAssertEqual(search.value as? String, "Rock")
        ReadingUIInteraction.reveal(app.buttons["music-genre-country-US"], in: app, container: scroll)
        XCTAssertTrue(app.buttons["music-genre-country-GB"].exists); capture("music-explore-restored-" + device)
        let reset = app.buttons["music-genre-reset"]; ReadingUIInteraction.reveal(reset, in: app, up: false, container: scroll); ReadingUIInteraction.tapVisible(reset, in: app)
        let restored = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == '158 genres'"), object: count)
        XCTAssertEqual(XCTWaiter.wait(for: [restored], timeout: 15), .completed)
        ReadingUIInteraction.reveal(app.buttons["music-genre-132"], in: app, container: scroll)
        XCTAssertFalse(app.buttons["music-genre-country-US"].exists); capture("music-explore-reset-" + device)
    }
    private func chooseCountry(_ country: String, app: XCUIApplication, scroll: XCUIElement) {
        let picker = app.buttons["music-genre-countries"]
        ReadingUIInteraction.reveal(picker, in: app, up: false, container: scroll); ReadingUIInteraction.tapVisible(picker, in: app)
        ReadingUIInteraction.chooseNativeMenuItem(country, in: app)
    }
    private func navigate(_ app: XCUIApplication) {
        let menu = app.buttons["main-menu"]; XCTAssertTrue(menu.waitForExistence(timeout: 45)); menu.tap()
        let navigation = app.descendants(matching: .any).matching(identifier: "navigation-scroll").firstMatch
        XCTAssertTrue(navigation.waitForExistence(timeout: 10)); let music = app.buttons["nav-music"]
        for _ in 0..<12 { if music.isHittable { break }; navigation.swipeDown() }
        for _ in 0..<12 { if music.isHittable { break }; navigation.swipeUp() }
        XCTAssertTrue(music.isHittable); music.press(forDuration: 0.6)
    }
    private func capture(_ name: String) {
        let image = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); image.name = name; image.lifetime = .keepAlways; add(image)
    }
}

import XCTest

@MainActor final class MusicBillboardNavigationTests: XCTestCase {
    func testPublicRanksAlbumChartLocalSearchCountrySelectionAndReturnToGenresOnIPhone() { verify("iphone") }
    func testPublicRanksAlbumChartLocalSearchCountrySelectionAndReturnToGenresOnIPad() { verify("ipad") }
    private func verify(_ device: String) {
        continueAfterFailure = false; XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication(); app.launchArguments = ["-uiLanguage", "en", "-nativeGuide.initialized.v1", "YES", "-nativeGuide.completed.v1", "YES"]
        app.launch(); defer { app.terminate(); XCUIDevice.shared.orientation = .portrait }
        let menu = app.buttons["main-menu"]; XCTAssertTrue(menu.waitForExistence(timeout: 45)); menu.tap()
        let navigation = app.descendants(matching: .any).matching(identifier: "navigation-scroll").firstMatch
        XCTAssertTrue(navigation.waitForExistence(timeout: 10)); let music = app.buttons["nav-music"]
        for _ in 0..<12 { if music.isHittable { break }; navigation.swipeDown() }
        for _ in 0..<12 { if music.isHittable { break }; navigation.swipeUp() }
        XCTAssertTrue(music.isHittable); ReadingUIInteraction.tapVisible(music, in: app)
        let explore = app.scrollViews["music-explore-scroll"]
        XCTAssertTrue(explore.waitForExistence(timeout: 20))
        let entry = app.buttons["music-explore-billboard"]; ReadingUIInteraction.revealWithinViewport(entry, in: app, container: explore); ReadingUIInteraction.tapVisible(entry, in: app)
        let scroll = app.scrollViews["music-billboard-scroll"], first = app.buttons["music-billboard-entry-1"]
        XCTAssertTrue(scroll.waitForExistence(timeout: 15)); XCTAssertTrue(first.waitForExistence(timeout: 60))
        ReadingUIInteraction.revealWithinViewport(first, in: app, container: scroll)
        XCTAssertTrue(app.staticTexts["music-billboard-date"].exists); capture("music-billboard-ranks-" + device)
        ReadingUIInteraction.tapVisible(first, in: app)
        let detail = app.staticTexts["music-catalog-detail-title"]; XCTAssertTrue(detail.waitForExistence(timeout: 20)); XCTAssertFalse(detail.label.isEmpty)
        capture("music-billboard-detail-" + device); ReadingUIInteraction.back(from: detail.label, in: app)
        let picker = app.buttons["music-billboard-chart"]
        ReadingUIInteraction.revealWithinViewport(picker, in: app, container: scroll); ReadingUIInteraction.tapVisible(picker, in: app)
        let albums = app.buttons["Billboard 200"].firstMatch; XCTAssertTrue(albums.waitForExistence(timeout: 10)); albums.tap()
        let title = app.staticTexts["music-billboard-title"]
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == 'Billboard 200'"), object: title)], timeout: 15), .completed)
        XCTAssertTrue(first.waitForExistence(timeout: 60)); ReadingUIInteraction.revealWithinViewport(first, in: app, container: scroll)
        capture("music-billboard-albums-" + device)
        let search = app.textFields["music-billboard-search"]
        ReadingUIInteraction.revealWithinViewport(search, in: app, container: scroll); search.tap(); search.typeText("Owned impossible search 9f25\n")
        XCTAssertTrue(app.staticTexts["music-billboard-empty"].waitForExistence(timeout: 15)); XCTAssertFalse(first.exists)
        capture("music-billboard-search-" + device)
        let clear = app.buttons["music-billboard-clear-search"]; ReadingUIInteraction.revealWithinViewport(clear, in: app, container: scroll); ReadingUIInteraction.tapVisible(clear, in: app)
        let country = app.buttons["music-billboard-country"]; ReadingUIInteraction.revealWithinViewport(country, in: app, container: scroll); ReadingUIInteraction.tapVisible(country, in: app)
        ReadingUIInteraction.chooseNativeMenuItem("United Kingdom", in: app)
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "label != 'Billboard 200'"), object: title)], timeout: 15), .completed)
        XCTAssertTrue(first.waitForExistence(timeout: 60)); ReadingUIInteraction.revealWithinViewport(first, in: app, container: scroll)
        capture("music-billboard-country-" + device)
        ReadingUIInteraction.back(from: "Billboard", in: app)
        let count = app.staticTexts["music-genre-count"]; ReadingUIInteraction.revealWithinViewport(count, in: app, container: explore)
        XCTAssertEqual(count.label, "158 genres"); capture("music-billboard-genres-" + device)
    }
    private func capture(_ name: String) {
        let image = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); image.name = name; image.lifetime = .keepAlways; add(image)
    }
}

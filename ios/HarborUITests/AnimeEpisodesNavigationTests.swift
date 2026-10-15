import XCTest

@MainActor final class AnimeEpisodesNavigationTests: XCTestCase {
    func testSuperShowsContinuousEpisodesAndArtworkAfterFourteen() throws {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchArguments = ["-uiLanguage", "es"]; app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.buttons["main-menu"].waitForExistence(timeout: 45)); app.buttons["main-menu"].tap()
        let searchNavigation = app.buttons["nav-search"]
        XCTAssertTrue(searchNavigation.waitForExistence(timeout: 10)); searchNavigation.tap()
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 15)); field.tap(); field.typeText("Dragon Ball Super\n")
        let card = app.buttons.matching(NSPredicate(format: "identifier == 'catalog-series' AND label == 'Dragon Ball Super'")).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 90))
        for _ in 0..<8 { if card.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(card.isHittable); card.tap()
        let summary = app.staticTexts["detail-episode-summary"]
        for _ in 0..<8 { if summary.exists { break }; app.swipeUp() }
        XCTAssertTrue(summary.waitForExistence(timeout: 30))
        let grouped = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value CONTAINS '131 episodios' AND value CONTAINS '1 temporada'"), object: summary)
        XCTAssertEqual(XCTWaiter.wait(for: [grouped], timeout: 90), .completed)
        capture("super-one-season")
        let fifteen = app.buttons["detail-episode-tt4644488:2:1"]
        for _ in 0..<30 { if fifteen.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(fifteen.isHittable); XCTAssertEqual(fifteen.label, "Reproducir episodio 15")
        if fifteen.frame.maxY > app.frame.maxY - 120 { app.swipeUp() }
        Thread.sleep(forTimeInterval: 2)
        // Captures the real loaded public episode list, without entering a player.
        capture("super-continuous-episode-15")
    }
    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}

import XCTest

@MainActor final class AnimeEpisodesNavigationTests: XCTestCase {
    func testSuperShowsContinuousEpisodesAndArtworkAfterFourteen() throws {
        try verifyBothPresentations(device: "iphone")
    }
    func testSuperRestoresProviderSeasonsAndContinuousEpisodesOnIPad() throws {
        try verifyBothPresentations(device: "ipad")
    }
    private func verifyBothPresentations(device: String) throws {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchArguments = ["-uiLanguage", "es"]; app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.buttons["main-menu"].waitForExistence(timeout: 45)); app.buttons["main-menu"].tap()
        let searchNavigation = app.buttons["nav-search"]
        XCTAssertTrue(searchNavigation.waitForExistence(timeout: 10)); searchNavigation.tap()
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 15)); field.tap(); field.typeText("Dragon Ball Super\n")
        let card = app.buttons.matching(NSPredicate(format: "identifier == 'catalog-media' AND label == 'Dragon Ball Super'")).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 90))
        for _ in 0..<8 { if card.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(card.isHittable); card.tap()
        let summary = app.staticTexts["detail-episode-summary"]
        for _ in 0..<8 { if summary.exists { break }; app.swipeUp() }
        XCTAssertTrue(summary.waitForExistence(timeout: 30))
        let grouping = app.segmentedControls["anime-episode-grouping"]
        XCTAssertTrue(grouping.waitForExistence(timeout: 90))
        for _ in 0..<8 { if grouping.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(grouping.isHittable)
        XCTAssertTrue(app.buttons["episode-season"].exists, "Provider seasons remain available by default")
        capture("super-\(device)-provider-seasons")
        grouping.buttons["Todo"].tap()
        let grouped = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value CONTAINS '131 episodios' AND value CONTAINS '1 temporada'"), object: summary)
        XCTAssertEqual(XCTWaiter.wait(for: [grouped], timeout: 90), .completed)
        capture("super-\(device)-continuous")
        let fifteen = app.buttons["detail-episode-tt4644488:2:1"]
        for _ in 0..<30 { if fifteen.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(fifteen.isHittable); XCTAssertEqual(fifteen.label, "Reproducir episodio 15")
        if fifteen.frame.maxY > app.frame.maxY - 120 { app.swipeUp() }
        Thread.sleep(forTimeInterval: 2)
        // Captures the real loaded public episode list, without entering a player.
        capture("super-\(device)-continuous-episode-15")
        for _ in 0..<30 { if grouping.isHittable { break }; app.swipeDown() }
        XCTAssertTrue(grouping.isHittable); grouping.buttons["Temporadas"].tap()
        let provider = XCTNSPredicateExpectation(predicate: NSPredicate(format: "NOT (value CONTAINS '· 1 temporada')"), object: summary)
        XCTAssertEqual(XCTWaiter.wait(for: [provider], timeout: 10), .completed)
        let seasons = app.buttons["episode-season"]
        XCTAssertTrue(seasons.waitForExistence(timeout: 10)); seasons.tap()
        let fifth = app.buttons["Temporada 5"]
        XCTAssertTrue(fifth.waitForExistence(timeout: 10)); fifth.tap()
        let ninetyNine = app.buttons["detail-episode-tt4644488:5:23"]
        for _ in 0..<30 { if ninetyNine.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(ninetyNine.isHittable); XCTAssertEqual(ninetyNine.label, "Reproducir episodio 23")
        capture("super-\(device)-restored-season-five")
    }
    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}

import XCTest

@MainActor final class EpisodeOrderNavigationTests: XCTestCase {
    func testPublicSuperOrderPanelChangesActualEpisodesOnIPhone() { verify(device: "iphone") }
    func testPublicSuperOrderPanelChangesActualEpisodesOnIPad() { verify(device: "ipad") }

    private func verify(device: String) {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchArguments = ["-uiLanguage", "es"]; app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.buttons["main-menu"].waitForExistence(timeout: 45)); app.buttons["main-menu"].tap()
        let search = app.buttons["nav-search"]
        XCTAssertTrue(search.waitForExistence(timeout: 10)); search.tap()
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 15)); field.tap(); field.typeText("Dragon Ball Super\n")
        let card = app.buttons.matching(NSPredicate(format: "identifier == 'catalog-media' AND label == 'Dragon Ball Super'")).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 90)); reveal(card, in: app); card.tap()
        let summary = app.staticTexts["detail-episode-summary"]
        for _ in 0..<10 { if summary.exists { break }; app.swipeUp() }
        XCTAssertTrue(summary.waitForExistence(timeout: 30))
        let panel = app.buttons["episode-order-panel"]
        XCTAssertTrue(panel.waitForExistence(timeout: 120)); reveal(panel, in: app); panel.tap()
        let aired = app.buttons["episode-order-aired"], absolute = app.buttons["episode-order-absolute"]
        XCTAssertTrue(aired.waitForExistence(timeout: 15)); XCTAssertTrue(aired.isSelected)
        XCTAssertTrue(absolute.waitForExistence(timeout: 15))
        for _ in 0..<5 { if absolute.isHittable { break }; app.scrollViews["episode-order-tabs"].swipeLeft() }
        XCTAssertTrue(absolute.isHittable)
        capture("order-\(device)-aired-panel")
        absolute.tap(); selected(absolute)
        let all = app.buttons["episode-order-season-1"]
        XCTAssertTrue(all.waitForExistence(timeout: 15)); XCTAssertTrue(all.label.contains("131"))
        capture("order-\(device)-absolute-panel")
        all.tap()
        let continuous = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value CONTAINS '131 episodios' AND value CONTAINS '1 temporada'"), object: summary)
        XCTAssertEqual(XCTWaiter.wait(for: [continuous], timeout: 30), .completed)
        let fifteen = app.buttons["detail-episode-tt4644488:2:1"]
        reveal(fifteen, in: app)
        XCTAssertEqual(fifteen.label, "Reproducir episodio 15")
        capture("order-\(device)-absolute-episode-15")
        for _ in 0..<35 { if panel.isHittable { break }; app.swipeDown() }
        XCTAssertTrue(panel.isHittable); panel.tap()
        XCTAssertTrue(aired.waitForExistence(timeout: 15)); aired.tap(); selected(aired)
        let fifth = app.buttons["episode-order-season-5"]
        let table = app.scrollViews["episode-order-season-scroll"]
        XCTAssertTrue(table.waitForExistence(timeout: 10))
        for _ in 0..<12 { if fifth.isHittable { break }; table.swipeUp() }
        XCTAssertTrue(fifth.isHittable); fifth.tap()
        let ninetyNine = app.buttons["detail-episode-tt4644488:5:23"]
        reveal(ninetyNine, in: app)
        XCTAssertEqual(ninetyNine.label, "Reproducir episodio 23")
        capture("order-\(device)-aired-episode-99")
    }

    private func selected(_ element: XCUIElement) {
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "selected == true AND enabled == true"), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 120), .completed)
    }
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<35 {
            if element.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(element.isHittable)
        if element.frame.maxY > app.frame.maxY - 100 { app.swipeUp() }
    }
    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}

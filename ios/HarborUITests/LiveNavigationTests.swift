import XCTest

/// Uses the normal app UI and public addon services. Only this test bundle knows
/// the example addon URL; the product has no UI-test launch mode or seeded data.
@MainActor
final class LiveNavigationTests: XCTestCase {
    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func reveal(_ element: XCUIElement, in scroll: XCUIElement, attempts: Int = 10) {
        for _ in 0..<attempts {
            if element.isHittable { return }
            scroll.swipeUp()
        }
    }

    func testRealHomeSearchAddonPickerAndPlayerPresentation() throws {
        guard ProcessInfo.processInfo.environment["HARBOR_LIVE_INTEGRATION"] == "1" else {
            throw XCTSkip("Live UI integration requires explicit opt-in")
        }
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()
        let movie = app.buttons.matching(identifier: "catalog-movie").firstMatch
        let homeLoaded = movie.waitForExistence(timeout: 45)
        capture(app, "home-real-catalogs")
        let homeError = app.staticTexts["home-error"]
        XCTAssertTrue(homeLoaded, "Home must load a real movie catalog; startup=\(homeError.exists ? homeError.label : "no error text")")
        // SwiftUI exposes the identified accessibility container as Other,
        // with the actual NavigationLink button inside it.
        let hero = app.descendants(matching: .any).matching(identifier: "home-hero").firstMatch
        XCTAssertTrue(hero.waitForExistence(timeout: 5))
        // Layout failures still fail the gate, while collecting the independent
        // navigation/render evidence in this same opt-in run.
        continueAfterFailure = true
        XCTAssertGreaterThanOrEqual(hero.frame.minX, app.frame.minX - 1, "Hero bounds=\(hero.frame); app bounds=\(app.frame)")
        XCTAssertLessThanOrEqual(hero.frame.maxX, app.frame.maxX + 1, "The hero must fit the iPhone viewport")
        let catalogTitle = app.staticTexts.matching(identifier: "catalog-title").firstMatch
        XCTAssertTrue(catalogTitle.exists)
        XCTAssertGreaterThanOrEqual(catalogTitle.frame.minX, app.frame.minX, "Catalog titles must not be cropped off the left edge")
        continueAfterFailure = false

        app.tabBars.buttons["Buscar"].tap()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("Interstellar\n")
        let completedQuery = app.staticTexts["search-results-query"]
        let completed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true AND label == %@", "Resultados para «Interstellar»"), object: completedQuery)
        XCTAssertEqual(XCTWaiter.wait(for: [completed], timeout: 30), .completed, "Wait for the complete query, not an earlier result")
        let result = app.buttons.matching(NSPredicate(format: "identifier == 'catalog-movie' AND label == 'Interstellar'")).firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 30), "Search must return real addon results")
        capture(app, "search-real-results")
        result.tap()
        XCTAssertTrue(app.staticTexts["detail-title"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["detail-streams"].waitForExistence(timeout: 10))
        capture(app, "real-detail")

        app.tabBars.buttons["Addons"].tap()
        let field = app.secureTextFields["addon-manifest-url"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("https://raw.githubusercontent.com/Stremio/stremio-static-addon-example/master/manifest.json")
        app.buttons["addon-install"].tap()
        // Installation and subsequent catalog fetching use the real app model.
        let installed = app.switches["Now.sh Example"]
        XCTAssertTrue(installed.waitForExistence(timeout: 30), "The public addon must install through Keychain-backed UI")
        let finished = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.progressIndicators["addon-install-progress"])
        XCTAssertEqual(XCTWaiter.wait(for: [finished], timeout: 30), .completed, "Catalog fetching must finish after installation")

        // Catalog resources are discovered from the installed example's
        // manifest, without injecting app state.
        app.tabBars.buttons["Home"].tap()
        capture(app, "home-after-addon-install")
        // SwiftUI can expose a scroll container as Other rather than ScrollView.
        // The identifier selects the same product view independent of AX role.
        let scroll = app.descendants(matching: .any).matching(identifier: "home-scroll").firstMatch
        XCTAssertTrue(scroll.waitForExistence(timeout: 5))
        let example = app.buttons.matching(NSPredicate(format: "identifier == 'catalog-movie' AND label == 'Big Buck Bunny'")).firstMatch
        reveal(example, in: scroll)
        capture(app, "installed-addon-catalog")
        XCTAssertTrue(example.waitForExistence(timeout: 15), "The real installed addon must appear in Home's vertical catalog list")
        XCTAssertTrue(example.isHittable)
        example.tap()
        let streams = app.buttons["detail-streams"]
        XCTAssertTrue(streams.waitForExistence(timeout: 10))
        reveal(streams, in: app.scrollViews.firstMatch, attempts: 5)
        streams.tap()
        let offer = app.buttons.matching(identifier: "stream-offer").firstMatch
        XCTAssertTrue(offer.waitForExistence(timeout: 30), "A real addon must populate the stream picker")
        capture(app, "real-stream-picker")
        offer.tap()
        let close = app.buttons["player-close"]
        XCTAssertTrue(close.waitForExistence(timeout: 20), "The resolved source must open the native player")
        let surface = app.descendants(matching: .any).matching(identifier: "player-surface").firstMatch
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true AND value == 'Preparado'"), object: surface)
        let readiness = XCTWaiter.wait(for: [ready], timeout: 20)
        capture(app, "native-player-presentation")
        XCTAssertEqual(readiness, .completed, "The real mpv engine and renderer must initialize before this navigation gate passes")
        // Opening the player is not proof that this public example's old video
        // host delivers media. Physical playback remains a separate gate.
        close.tap()
        XCTAssertTrue(offer.waitForExistence(timeout: 15), "Closing must return to the stream picker")
    }
}

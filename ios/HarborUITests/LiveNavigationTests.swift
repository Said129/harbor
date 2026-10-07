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

    private func navigate(_ app: XCUIApplication, _ section: String) {
        app.buttons["main-menu"].tap()
        let destination = app.buttons["nav-\(section)"]
        XCTAssertTrue(destination.waitForExistence(timeout: 5))
        let scroll = app.descendants(matching: .any).matching(identifier: "navigation-scroll").firstMatch
        XCTAssertTrue(scroll.waitForExistence(timeout: 5))
        reveal(destination, in: scroll, attempts: 4)
        destination.tap()
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
        app.buttons["home-signin"].tap()
        XCTAssertTrue(app.textFields["account-email"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["account-browser-login"].exists)
        capture(app, "account-native-login")
        app.buttons["account-tab-profile"].tap()
        XCTAssertTrue(app.textFields["profile-name"].exists, "The account screen must expose the original profile editor")
        capture(app, "account-original-profile")
        app.navigationBars.buttons["Cerrar"].tap()
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

        navigate(app, "catalogs")
        let catalog = app.buttons.matching(identifier: "catalog-browser-link").firstMatch
        XCTAssertTrue(catalog.waitForExistence(timeout: 5))
        capture(app, "native-catalogs-original-layout")
        catalog.tap()
        XCTAssertTrue(app.buttons.matching(identifier: "catalog-browser-media").firstMatch.waitForExistence(timeout: 20))
        capture(app, "native-catalog-browser")

        navigate(app, "settings")
        capture(app, "native-settings-original-layout")
        app.buttons["settings-video"].tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "settings-hwdec").firstMatch.waitForExistence(timeout: 5))
        capture(app, "native-video-settings")
        let settingsBack = app.navigationBars["Vídeo"].buttons["Ajustes"]
        XCTAssertTrue(settingsBack.waitForExistence(timeout: 5))
        XCTAssertTrue(settingsBack.isHittable, "The Harbor header must not cover the native back button")
        settingsBack.tap()
        let subtitles = app.buttons["settings-subtitles"]
        let settingsScroll = app.descendants(matching: .any).matching(identifier: "settings-scroll").firstMatch
        XCTAssertTrue(settingsScroll.waitForExistence(timeout: 5))
        reveal(subtitles, in: settingsScroll, attempts: 3)
        XCTAssertTrue(subtitles.isHittable)
        subtitles.tap()
        XCTAssertTrue(app.staticTexts["settings-subtitle-preview"].waitForExistence(timeout: 5))
        capture(app, "native-subtitle-settings")

        navigate(app, "movies")
        XCTAssertTrue(app.buttons.matching(identifier: "catalog-movie").firstMatch.waitForExistence(timeout: 30), "Movies must load its content directly")
        capture(app, "native-movies-direct")
        navigate(app, "shows")
        XCTAssertTrue(app.buttons.matching(identifier: "catalog-media").firstMatch.waitForExistence(timeout: 30), "Shows must load its content directly")
        capture(app, "native-shows-direct")
        navigate(app, "search")
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
        result.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25)).tap()
        XCTAssertTrue(app.staticTexts["detail-title"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["detail-streams"].waitForExistence(timeout: 10))
        capture(app, "real-detail")
        app.buttons["detail-bookmark"].tap()
        let saved = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true AND label == 'En mi lista'"), object: app.buttons["detail-bookmark"])
        XCTAssertEqual(XCTWaiter.wait(for: [saved], timeout: 10), .completed)
        app.buttons["detail-favorite"].tap()
        XCTAssertEqual(app.buttons["detail-favorite"].label, "Quitar de favoritos")
        let detailScroll = app.scrollViews.firstMatch
        let trailer = app.buttons.matching(identifier: "detail-trailer").firstMatch
        reveal(trailer, in: detailScroll, attempts: 5)
        XCTAssertTrue(trailer.waitForExistence(timeout: 15), "The real detail must show addon trailers without a metadata key")
        XCTAssertTrue(trailer.isHittable)
        capture(app, "real-detail-addon-trailers")
        let writers = app.staticTexts["detail-information-Guion"]
        reveal(writers, in: detailScroll, attempts: 3)
        XCTAssertTrue(writers.waitForExistence(timeout: 5))
        XCTAssertTrue(writers.label.contains("Nolan"), "The detail must display real writer names from Cinemeta")
        capture(app, "real-detail-addon-information")
        navigate(app, "library")
        let savedMovie = app.buttons.matching(NSPredicate(format: "identifier == 'library-media' AND label == 'Interstellar'")).firstMatch
        XCTAssertTrue(savedMovie.waitForExistence(timeout: 10), "Saving from the real detail must populate the actual library")
        capture(app, "native-library-original-layout")
        let favorites = app.buttons["library-tab-favorites"]
        let filterBar = app.descendants(matching: .any).matching(identifier: "library-filter").firstMatch
        XCTAssertTrue(filterBar.waitForExistence(timeout: 5))
        // XCTest can throw while asking hittability of a button outside a
        // horizontal scroll viewport. Reveal its frame before querying it.
        for _ in 0..<3 {
            if filterBar.frame.contains(favorites.frame) { break }
            filterBar.swipeLeft()
        }
        XCTAssertTrue(filterBar.frame.contains(favorites.frame), "The Favorites tab must scroll into the iPhone viewport")
        XCTAssertTrue(favorites.isHittable)
        favorites.tap()
        XCTAssertTrue(savedMovie.waitForExistence(timeout: 5), "Favorites must show the actual detail selection")
        capture(app, "native-library-favorites")
        savedMovie.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25)).tap()
        XCTAssertTrue(app.staticTexts["detail-title"].waitForExistence(timeout: 10), "The image area of a library poster must open its detail")
        navigate(app, "calendar")
        capture(app, "native-calendar-original-layout")
        navigate(app, "manga")
        capture(app, "native-manga-original-layout")

        navigate(app, "addons")
        XCTAssertTrue(app.buttons["addon-tab-discover"].waitForExistence(timeout: 5))
        capture(app, "native-addon-store")
        let field = app.secureTextFields["addon-manifest-url"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("https://raw.githubusercontent.com/Stremio/stremio-static-addon-example/master/manifest.json")
        app.buttons["addon-install"].tap()
        // Installation and subsequent catalog fetching use the real app model.
        let addonSearch = app.textFields.matching(NSPredicate(format: "placeholderValue == 'Buscar addons'")).firstMatch
        XCTAssertTrue(addonSearch.waitForExistence(timeout: 5))
        addonSearch.tap()
        addonSearch.typeText("Now.sh")
        app.buttons["addon-tab-installed"].tap()
        let installed = app.switches["Now.sh Example"]
        XCTAssertTrue(installed.waitForExistence(timeout: 30), "The public addon must install through Keychain-backed UI")
        let finished = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.progressIndicators["addon-install-progress"])
        XCTAssertEqual(XCTWaiter.wait(for: [finished], timeout: 30), .completed, "Catalog fetching must finish after installation")
        let addonDetails = app.buttons.matching(NSPredicate(format: "identifier == 'addon-details' AND label == 'Detalles de Now.sh Example'")).firstMatch
        XCTAssertTrue(addonDetails.waitForExistence(timeout: 5))
        for _ in 0..<4 { if addonDetails.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(addonDetails.isHittable)
        capture(app, "native-addon-store-installed")
        addonDetails.tap()
        XCTAssertTrue(app.staticTexts["addon-detail-title"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["addon-detail-title"].label, "Now.sh Example")
        capture(app, "native-addon-detail")
        app.navigationBars.buttons["Cerrar"].tap()

        // Catalog resources are discovered from the installed example's
        // manifest, without injecting app state.
        navigate(app, "home")
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
        let videoTap = surface.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35))
        videoTap.tap()
        let hidden = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: close)
        XCTAssertEqual(XCTWaiter.wait(for: [hidden], timeout: 3), .completed, "Tapping the video must remove the controls")
        capture(app, "native-player-controls-hidden")
        videoTap.tap()
        XCTAssertTrue(close.waitForExistence(timeout: 3), "A second video tap must restore the controls")
        app.buttons["player-options"].tap()
        XCTAssertTrue(app.navigationBars["Opciones del reproductor"].waitForExistence(timeout: 5), "Controls must open options without also toggling the video interface")
        capture(app, "native-player-options")
        app.navigationBars.buttons["Listo"].tap()
        XCTAssertTrue(close.waitForExistence(timeout: 3))
        app.buttons["player-options"].tap()
        let changeSource = app.buttons["player-change-source"]
        XCTAssertTrue(changeSource.waitForExistence(timeout: 5))
        changeSource.tap()
        XCTAssertTrue(offer.waitForExistence(timeout: 15), "Changing source must return to actual addon offers after dismissing the options and player")
        capture(app, "native-player-change-source")
        offer.tap()
        XCTAssertTrue(close.waitForExistence(timeout: 20), "An actual offer must reopen the native player after switching source")
        if app.staticTexts["player-error"].waitForExistence(timeout: 5) {
            let recovery = app.buttons["player-error-change-source"]
            XCTAssertTrue(recovery.waitForExistence(timeout: 3), "A failed source must provide a direct route to actual addon offers")
            capture(app, "native-player-error-recovery")
            recovery.tap()
            XCTAssertTrue(offer.waitForExistence(timeout: 15))
            offer.tap()
            XCTAssertTrue(close.waitForExistence(timeout: 20))
        }
        // Opening the player is not proof that this public example's old video
        // host delivers media. Physical playback remains a separate gate.
        close.tap()
        XCTAssertTrue(offer.waitForExistence(timeout: 15), "Closing must return to the stream picker")
    }
}

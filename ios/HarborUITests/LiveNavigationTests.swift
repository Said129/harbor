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
        let customize = app.buttons["page-customize"]
        reveal(customize, in: app.scrollViews.firstMatch, attempts: 6)
        XCTAssertTrue(customize.isHittable)
        customize.tap()
        let doneEditing = app.buttons["page-customize-done"]
        XCTAssertTrue(doneEditing.waitForExistence(timeout: 5))
        capture(app, "native-home-original-inline-customization")
        doneEditing.tap()
        let stoppedEditing = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: doneEditing)
        XCTAssertEqual(XCTWaiter.wait(for: [stoppedEditing], timeout: 5), .completed)
        app.buttons["main-account"].firstMatch.tap()
        XCTAssertTrue(app.textFields["account-email"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["account-browser-login"].exists)
        capture(app, "account-native-login")
        app.buttons["account-tab-profile"].tap()
        XCTAssertTrue(app.textFields["profile-name"].exists, "The account screen must expose the original profile editor")
        capture(app, "account-original-profile")
        let avatarPicker = app.buttons["profile-avatar-picker"]
        reveal(avatarPicker, in: app.scrollViews.firstMatch, attempts: 3)
        avatarPicker.tap()
        let avatarSearch = app.textFields["profile-avatar-search"]
        XCTAssertTrue(avatarSearch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons.matching(identifier: "profile-avatar-choice").firstMatch.exists)
        capture(app, "account-original-avatar-gallery")
        avatarSearch.tap(); avatarSearch.typeText("Nova")
        XCTAssertEqual(app.buttons.matching(identifier: "profile-avatar-choice").count, 1, "Original avatar names must be searchable")
        let avatarClose = app.buttons["profile-avatar-close"]
        XCTAssertTrue(avatarClose.isHittable)
        avatarClose.tap()
        XCTAssertTrue(app.textFields["profile-name"].waitForExistence(timeout: 5))
        let accountClose = app.buttons["account-close"]
        XCTAssertTrue(accountClose.isHittable)
        accountClose.tap()
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
        let metadata = app.buttons["settings-metadata"]
        let metadataSettingsScroll = app.descendants(matching: .any).matching(identifier: "settings-scroll").firstMatch
        reveal(metadata, in: metadataSettingsScroll, attempts: 4)
        XCTAssertTrue(metadata.isHittable)
        metadata.tap()
        XCTAssertTrue(app.buttons["metadata-manage-key"].waitForExistence(timeout: 5))
        capture(app, "native-metadata-original-provider-row")
        app.buttons["metadata-manage-key"].tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "metadata-key-field").firstMatch.waitForExistence(timeout: 5))
        capture(app, "native-metadata-original-key-editor")
        app.buttons["metadata-key-close"].tap()
        XCTAssertTrue(app.buttons["metadata-manage-key"].waitForExistence(timeout: 5))
        navigate(app, "settings")
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "settings-scroll").firstMatch.waitForExistence(timeout: 5), "Selecting Settings from a subpage must return to the section root")
        XCTAssertFalse(app.buttons["metadata-manage-key"].exists)
        capture(app, "native-settings-root-after-reselection")
        app.buttons["settings-playback"].tap()
        let instant = app.buttons["Instantáneo"]
        let manual = app.buttons["Elige una fuente"]
        XCTAssertTrue(instant.waitForExistence(timeout: 5))
        XCTAssertTrue(manual.isHittable)
        let startedInstant = instant.isSelected
        manual.tap()
        XCTAssertTrue(manual.isSelected)
        capture(app, "native-play-mode-manual")
        instant.tap()
        XCTAssertTrue(instant.isSelected)
        capture(app, "native-play-mode-instant")
        if !startedInstant { manual.tap() }
        app.navigationBars["Reproducción"].buttons["Configuración"].tap()
        app.buttons["settings-playback"].tap()
        XCTAssertEqual(app.buttons["Instantáneo"].isSelected, startedInstant, "The real saved play mode must survive reopening settings")
        let playbackSettings = app.descendants(matching: .any).matching(identifier: "player-settings-scroll").firstMatch
        let nextPrompt = app.descendants(matching: .any).matching(identifier: "settings-next-prompt").firstMatch
        reveal(nextPrompt, in: playbackSettings, attempts: 8)
        XCTAssertTrue(nextPrompt.isHittable)
        capture(app, "native-next-prompt-original")
        app.navigationBars["Reproducción"].buttons["Configuración"].tap()
        app.buttons["settings-video"].tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "settings-hwdec").firstMatch.waitForExistence(timeout: 5))
        let videoSettings = app.descendants(matching: .any).matching(identifier: "player-settings-scroll").firstMatch
        XCTAssertTrue(videoSettings.waitForExistence(timeout: 5))
        let crisp = app.buttons["settings-picture-preset-crisp"]
        reveal(crisp, in: videoSettings, attempts: 5)
        XCTAssertTrue(crisp.isHittable)
        capture(app, "native-picture-original-presets")
        let fit = app.buttons["Relación de aspecto"]
        XCTAssertTrue(fit.waitForExistence(timeout: 5))
        reveal(fit, in: videoSettings, attempts: 3)
        XCTAssertTrue(fit.isHittable)
        let originalFit = try XCTUnwrap(fit.value as? String)
        fit.tap()
        XCTAssertTrue(app.buttons["4:3"].waitForExistence(timeout: 3))
        capture(app, "native-video-format-menu")
        app.buttons["4:3"].tap()
        XCTAssertEqual(fit.value as? String, "4:3")
        fit.tap()
        app.buttons[originalFit].tap()
        XCTAssertEqual(fit.value as? String, originalFit, "Restore the user's starting image format after checking the real menu")
        capture(app, "native-video-settings")
        let settingsBack = app.navigationBars["Vídeo"].buttons["Configuración"]
        XCTAssertTrue(settingsBack.waitForExistence(timeout: 5))
        XCTAssertTrue(settingsBack.isHittable, "The Harbor header must not cover the native back button")
        settingsBack.tap()
        let subtitles = app.buttons["settings-subtitles"]
        let settingsScroll = app.descendants(matching: .any).matching(identifier: "settings-scroll").firstMatch
        XCTAssertTrue(settingsScroll.waitForExistence(timeout: 5))
        reveal(subtitles, in: settingsScroll, attempts: 3)
        XCTAssertTrue(subtitles.isHittable)
        subtitles.tap()
        let languageOrder = app.descendants(matching: .any).matching(identifier: "settings-subtitle-languages").firstMatch
        XCTAssertTrue(languageOrder.waitForExistence(timeout: 5))
        let originalLanguages = try XCTUnwrap(languageOrder.value as? String)
        let originalCodes = originalLanguages.split(separator: ",").map(String.init)
        let newCode = originalCodes.contains("es") ? "ar" : "es"
        let newName = newCode == "es" ? "Spanish" : "Arabic"
        let expandLanguages = app.buttons["settings-subtitle-languages-toggle"]
        expandLanguages.tap()
        let languageSearch = app.textFields["settings-subtitle-languages-search"]
        XCTAssertTrue(languageSearch.waitForExistence(timeout: 3))
        languageSearch.tap(); languageSearch.typeText(newName)
        let addLanguage = app.buttons["settings-subtitle-languages-add-" + newCode]
        XCTAssertTrue(addLanguage.waitForExistence(timeout: 3))
        addLanguage.tap()
        XCTAssertEqual(languageOrder.value as? String, (originalCodes + [newCode]).joined(separator: ","))
        expandLanguages.tap()
        if !originalCodes.isEmpty {
            app.buttons["settings-subtitle-languages-earlier-" + newCode].tap()
            var reordered = originalCodes + [newCode]; reordered.swapAt(reordered.count - 1, reordered.count - 2)
            XCTAssertEqual(languageOrder.value as? String, reordered.joined(separator: ","))
        }
        capture(app, "native-subtitle-original-language-order")
        app.buttons["settings-subtitle-languages-remove-" + newCode].tap()
        XCTAssertEqual(languageOrder.value as? String, originalLanguages)
        let secondaryLanguage = app.buttons["Segundo idioma de subtítulos"]
        XCTAssertTrue(secondaryLanguage.waitForExistence(timeout: 5))
        XCTAssertNotNil(secondaryLanguage.value as? String)
        capture(app, "native-subtitle-language-settings")
        let playerSettings = app.descendants(matching: .any).matching(identifier: "player-settings-scroll").firstMatch
        XCTAssertTrue(playerSettings.waitForExistence(timeout: 5))
        let subtitlePreview = app.descendants(matching: .any).matching(identifier: "settings-subtitle-preview").firstMatch
        reveal(subtitlePreview, in: playerSettings, attempts: 4)
        XCTAssertTrue(subtitlePreview.isHittable)
        capture(app, "native-subtitle-settings")

        navigate(app, "settings")
        let interface = app.buttons["settings-interface"]
        reveal(interface, in: app.descendants(matching: .any).matching(identifier: "settings-scroll").firstMatch, attempts: 4)
        XCTAssertTrue(interface.isHittable)
        interface.tap()
        let curatedHome = app.buttons["home-style-harbor"]
        let classicHome = app.buttons["home-style-classic"]
        XCTAssertTrue(curatedHome.waitForExistence(timeout: 5))
        let originallyCurated = curatedHome.isSelected
        let interfaceScroll = app.descendants(matching: .any).matching(identifier: "interface-settings-scroll").firstMatch
        reveal(classicHome, in: interfaceScroll, attempts: 3)
        XCTAssertTrue(classicHome.isHittable)
        classicHome.tap()
        XCTAssertTrue(classicHome.isSelected)
        capture(app, "native-interface-original-home-styles")
        if originallyCurated {
            interfaceScroll.swipeDown()
            curatedHome.tap()
            XCTAssertTrue(curatedHome.isSelected)
        }
        let navigationSettings = app.buttons["settings-navigation"]
        reveal(navigationSettings, in: interfaceScroll, attempts: 3)
        XCTAssertTrue(navigationSettings.isHittable)
        navigationSettings.tap()
        XCTAssertTrue(app.buttons["navigation-visible-discover"].waitForExistence(timeout: 5))
        capture(app, "native-interface-original-navigation")

        navigate(app, "settings")
        let themeSettings = app.buttons["settings-theme"]
        reveal(themeSettings, in: app.descendants(matching: .any).matching(identifier: "settings-scroll").firstMatch, attempts: 4)
        XCTAssertTrue(themeSettings.isHittable)
        themeSettings.tap()
        let themeScroll = app.descendants(matching: .any).matching(identifier: "theme-settings-scroll").firstMatch
        XCTAssertTrue(themeScroll.waitForExistence(timeout: 5))
        let initialPalette = try XCTUnwrap(themeScroll.value as? String)
        capture(app, "native-appearance-original-palettes")
        let customPalette = app.buttons["theme-custom"]
        reveal(customPalette, in: themeScroll, attempts: 8)
        XCTAssertTrue(customPalette.isHittable)
        if app.buttons["theme-custom-edit"].exists { app.buttons["theme-custom-edit"].tap() }
        else { customPalette.tap() }
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "theme-custom-scroll").firstMatch.waitForExistence(timeout: 5))
        capture(app, "native-appearance-original-custom-colors")
        app.buttons["theme-custom-cancel"].tap()
        XCTAssertEqual(themeScroll.value as? String, initialPalette, "Cancelling live custom colors must restore the previously active palette")
        let fontSpecimen = app.buttons["theme-font-switzer"]
        reveal(fontSpecimen, in: themeScroll, attempts: 5)
        XCTAssertTrue(fontSpecimen.isHittable)
        capture(app, "native-appearance-original-fonts")

        navigate(app, "library")
        XCTAssertTrue(app.buttons["library-tab-all"].waitForExistence(timeout: 5))
        capture(app, "native-library-initial-state")
        navigate(app, "movies")
        XCTAssertTrue(app.buttons.matching(identifier: "catalog-movie").firstMatch.waitForExistence(timeout: 30), "Movies must load its content directly")
        capture(app, "native-movies-direct")
        navigate(app, "shows")
        XCTAssertTrue(app.buttons.matching(identifier: "catalog-media").firstMatch.waitForExistence(timeout: 30), "Shows must load its content directly")
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "series-original-hero").firstMatch.exists)
        capture(app, "native-shows-direct")
        navigate(app, "discover")
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "discover-original").firstMatch.waitForExistence(timeout: 5))
        capture(app, "native-discover-recommended")
        let downvote = app.buttons["discover-vote-down"]
        reveal(downvote, in: app.scrollViews.firstMatch, attempts: 3)
        XCTAssertTrue(downvote.waitForExistence(timeout: 15))
        XCTAssertTrue(downvote.isHittable)
        capture(app, "native-discover-feedback")
        downvote.tap()
        let undoVote = app.buttons["Deshacer"]
        XCTAssertTrue(undoVote.waitForExistence(timeout: 5))
        capture(app, "native-discover-feedback-saved")
        undoVote.tap()
        let surprise = app.buttons["discover-surprise"]
        reveal(surprise, in: app.scrollViews.firstMatch, attempts: 3)
        XCTAssertTrue(surprise.isHittable)
        capture(app, "native-discover-catalogs-surprise")
        surprise.tap()
        XCTAssertTrue(app.staticTexts["detail-title"].waitForExistence(timeout: 10), "Surprise me must open a real title detail")
        capture(app, "native-discover-surprise-detail")
        navigate(app, "anime")
        let animeHero = app.descendants(matching: .any).matching(identifier: "anime-original-hero").firstMatch
        XCTAssertTrue(animeHero.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["anime-start-watching"].firstMatch.waitForExistence(timeout: 60), "The anime hero must use real public anime metadata")
        capture(app, "native-anime-original-hero")
        let animeScroll = app.descendants(matching: .any).matching(identifier: "content-anime").firstMatch
        let top100 = app.staticTexts["rail-anilist-top100"]
        reveal(top100, in: animeScroll, attempts: 6)
        XCTAssertTrue(top100.waitForExistence(timeout: 30))
        capture(app, "native-anime-anilist-top100")
        let awards = app.staticTexts["rail-anime-awards"]
        reveal(awards, in: animeScroll, attempts: 4)
        XCTAssertTrue(awards.waitForExistence(timeout: 30))
        capture(app, "native-anime-award-winners")
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
        let saved = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true AND label == 'En la lista para ver'"), object: app.buttons["detail-bookmark"])
        XCTAssertEqual(XCTWaiter.wait(for: [saved], timeout: 10), .completed)
        app.buttons["detail-favorite"].tap()
        XCTAssertEqual(app.buttons["detail-favorite"].label, "Quitar de favoritos")
        let detailScroll = app.scrollViews.firstMatch
        // Crew precedes media; inspect its lazy grid before scrolling to trailers.
        let writers = app.staticTexts["detail-information-Guion"]
        reveal(writers, in: detailScroll, attempts: 3)
        XCTAssertTrue(writers.waitForExistence(timeout: 5))
        XCTAssertTrue(writers.label.contains("Nolan"), "The detail must display real writer names from Cinemeta")
        capture(app, "real-detail-addon-information")
        let trailer = app.buttons.matching(identifier: "detail-trailer").firstMatch
        reveal(trailer, in: detailScroll, attempts: 5)
        XCTAssertTrue(trailer.waitForExistence(timeout: 15), "The real detail must show addon trailers without a metadata key")
        XCTAssertTrue(trailer.isHittable)
        capture(app, "real-detail-addon-trailers")
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
        XCTAssertTrue(app.buttons["calendar-day-1"].waitForExistence(timeout: 5), "The first week of the month must remain visible alongside weekday headings")
        capture(app, "native-calendar-original-layout")
        navigate(app, "manga")
        let mangaLibrary = app.buttons["manga-library-card"]
        XCTAssertTrue(mangaLibrary.waitForExistence(timeout: 5))
        capture(app, "native-manga-original-layout")
        let mangaCollections = app.buttons["manga-collections-card"]
        XCTAssertTrue(mangaCollections.isHittable)
        mangaCollections.tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "manga-collections").firstMatch.waitForExistence(timeout: 5))
        capture(app, "native-manga-collections")
        navigate(app, "manga")
        app.buttons["manga-universes-card"].tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "manga-universes").firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "manga-universe-")).firstMatch.exists)
        capture(app, "native-manga-universes")
        navigate(app, "manga")
        mangaLibrary.tap()
        XCTAssertEqual(app.staticTexts["manga-content-heading"].label, "Biblioteca")
        capture(app, "native-manga-library")

        navigate(app, "addons")
        XCTAssertTrue(app.buttons["addon-tab-discover"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "addon-community-spotlight").firstMatch.waitForExistence(timeout: 30), "Discovery must resolve its real spotlight from the original public community index")
        capture(app, "native-addon-store")
        let streamingCategory = app.buttons["addon-category-streams"]
        for _ in 0..<4 { if streamingCategory.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(streamingCategory.isHittable)
        capture(app, "native-addon-store-categories")
        streamingCategory.tap()
        let communityDetails = app.buttons["addon-browse-details"].firstMatch
        XCTAssertTrue(communityDetails.waitForExistence(timeout: 30), "The category must open a real community catalog")
        for _ in 0..<4 { if communityDetails.isHittable { break }; app.swipeUp() }
        capture(app, "native-addon-browse")
        let field = app.secureTextFields["addon-manifest-url"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        for _ in 0..<4 { if field.isHittable { break }; app.swipeDown() }
        XCTAssertTrue(field.isHittable)
        field.tap()
        field.typeText("https://raw.githubusercontent.com/Stremio/stremio-static-addon-example/master/manifest.json")
        app.buttons["addon-install"].tap()
        // Installation and subsequent catalog fetching use the real app model.
        let addonSearch = app.textFields.matching(NSPredicate(format: "placeholderValue == 'Buscar complementos'")).firstMatch
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
        reveal(example, in: scroll, attempts: 36)
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
        let pickerScroll = app.scrollViews["stream-picker-scroll"]
        XCTAssertTrue(app.buttons["stream-picker-refresh"].exists)
        let allSources = app.buttons["stream-all-sources"]
        reveal(allSources, in: pickerScroll, attempts: 5)
        XCTAssertTrue(allSources.isHittable)
        allSources.tap()
        XCTAssertTrue(app.buttons.matching(identifier: "stream-source-row").firstMatch.waitForExistence(timeout: 5))
        capture(app, "real-stream-original-source-drawer")
        allSources.tap()
        for _ in 0..<5 { if offer.isHittable { break }; pickerScroll.swipeDown() }
        XCTAssertTrue(offer.isHittable)
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
        app.buttons["player-audio"].tap()
        XCTAssertTrue(app.staticTexts["audio-sync-offset"].waitForExistence(timeout: 5))
        capture(app, "native-player-original-audio")
        app.navigationBars.buttons["Listo"].tap()
        XCTAssertTrue(close.waitForExistence(timeout: 3))
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

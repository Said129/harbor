import XCTest

@MainActor final class MusicArtistNavigationTests: XCTestCase {
    func testPublicGenreArtistsProviderCreditsAndPrivateMetadataSettingsOnIPhone() { verify("iphone") }
    func testPublicGenreArtistsProviderCreditsAndPrivateMetadataSettingsOnIPad() { verify("ipad") }
    private func verify(_ device: String) {
        continueAfterFailure = false; XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication(bundleIdentifier: "site.harbor.iphone"); app.launchArguments = ["-uiLanguage", "en", "-nativeGuide.initialized.v1", "YES", "-nativeGuide.completed.v1", "YES"]
        app.launch(); defer { app.terminate(); XCUIDevice.shared.orientation = .portrait }
        let menu = app.buttons["main-menu"]; XCTAssertTrue(menu.waitForExistence(timeout: 45)); menu.tap()
        let navigation = app.descendants(matching: .any).matching(identifier: "navigation-scroll").firstMatch
        XCTAssertTrue(navigation.waitForExistence(timeout: 10)); let music = app.buttons["nav-music"]
        for _ in 0..<12 { if music.isHittable { break }; navigation.swipeDown() }
        for _ in 0..<12 { if music.isHittable { break }; navigation.swipeUp() }
        ReadingUIInteraction.tapVisible(music, in: app)
        let explore = app.scrollViews["music-explore-scroll"]; XCTAssertTrue(explore.waitForExistence(timeout: 20))
        let search = app.searchFields.firstMatch; ReadingUIInteraction.reveal(search, in: app, up: false, container: explore)
        search.tap(); search.typeText("Rock\n")
        let rock = app.buttons["music-genre-152"]; ReadingUIInteraction.revealWithinViewport(rock, in: app, container: explore); ReadingUIInteraction.tapVisible(rock, in: app)
        let scroll = app.scrollViews["music-genre-detail-scroll"], title = app.staticTexts["music-genre-detail-title"]
        XCTAssertTrue(title.waitForExistence(timeout: 20)); XCTAssertEqual(title.label, "Rock")
        let firstTrack = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'music-genre-track-deezer:track:'")).firstMatch
        XCTAssertTrue(firstTrack.waitForExistence(timeout: 30))
        let track = app.buttons[firstTrack.identifier]
        ReadingUIInteraction.revealWithinViewport(track, in: app, container: scroll); ReadingUIInteraction.tapVisible(track, in: app)
        let detail = app.scrollViews["music-catalog-detail"], credits = app.buttons["music-recording-credit-0"]
        XCTAssertTrue(detail.waitForExistence(timeout: 20)); XCTAssertTrue(credits.waitForExistence(timeout: 45))
        ReadingUIInteraction.revealWithinViewport(credits, in: app, container: detail); capture("music-artists-credits-" + device)
        ReadingUIInteraction.tapVisible(credits, in: app)
        let artist = app.staticTexts["music-catalog-detail-title"]; XCTAssertTrue(artist.waitForExistence(timeout: 20)); let artistName = artist.label
        XCTAssertFalse(artistName.isEmpty); capture("music-artists-credit-artist-" + device)
        ReadingUIInteraction.back(from: artistName, in: app)
        let trackTitle = app.staticTexts["music-catalog-detail-title"]; XCTAssertTrue(trackTitle.waitForExistence(timeout: 15)); ReadingUIInteraction.back(from: trackTitle.label, in: app)
        let more = app.buttons["music-genre-artists-more"]; ReadingUIInteraction.revealWithinViewport(more, in: app, container: scroll)
        let rosterArtist = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'music-catalog-item-artist|catalog|musicbrainz:artist:'")).firstMatch
        XCTAssertTrue(rosterArtist.waitForExistence(timeout: 60)); ReadingUIInteraction.revealWithinViewport(rosterArtist, in: app, container: scroll)
        capture("music-artists-roster-" + device); ReadingUIInteraction.tapVisible(rosterArtist, in: app)
        XCTAssertTrue(artist.waitForExistence(timeout: 15)); let rosterName = artist.label; XCTAssertFalse(rosterName.isEmpty)
        capture("music-artists-roster-detail-" + device); ReadingUIInteraction.back(from: rosterName, in: app)
        ReadingUIInteraction.back(from: "Rock", in: app)
        let actions = app.buttons["music-actions"]; XCTAssertTrue(actions.waitForExistence(timeout: 10)); ReadingUIInteraction.tapVisible(actions, in: app)
        let settings = app.buttons["music-metadata-open"]; XCTAssertTrue(settings.waitForExistence(timeout: 10)); ReadingUIInteraction.tapVisible(settings, in: app)
        let field = app.secureTextFields["music-lastfm-key"]; XCTAssertTrue(field.waitForExistence(timeout: 15)); XCTAssertFalse(app.buttons["music-lastfm-key-remove"].exists)
        capture("music-artists-settings-" + device)
        field.tap(); field.typeText("owned-ui-temporary-key")
        let save = app.buttons["music-lastfm-key-save"]; ReadingUIInteraction.revealWithinViewport(save, in: app, container: app.collectionViews.firstMatch); ReadingUIInteraction.tapVisible(save, in: app)
        let remove = app.buttons["music-lastfm-key-remove"]; XCTAssertTrue(remove.waitForExistence(timeout: 15)); ReadingUIInteraction.revealWithinViewport(remove, in: app, container: app.collectionViews.firstMatch); ReadingUIInteraction.tapVisible(remove, in: app)
        XCTAssertFalse(remove.exists); XCTAssertEqual(app.staticTexts["music-metadata-key-result"].label, "Removed")
        capture("music-artists-settings-removed-" + device)
    }
    private func capture(_ name: String) {
        let image = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); image.name = name; image.lifetime = .keepAlways; add(image)
    }
}

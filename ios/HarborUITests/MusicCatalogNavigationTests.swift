import XCTest

@MainActor final class MusicCatalogNavigationTests: XCTestCase {
    func testActualPublicHomeSearchAlbumTracksAndArtistAlbumsOnIPhone() { verify("iphone") }
    func testActualPublicHomeSearchAlbumTracksAndArtistAlbumsOnIPad() { verify("ipad") }
    private func verify(_ device: String) {
        continueAfterFailure = false; XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication(); app.launchArguments = ["-uiLanguage", "en", "-nativeGuide.initialized.v1", "YES", "-nativeGuide.completed.v1", "YES"]
        app.launch(); defer { app.terminate(); XCUIDevice.shared.orientation = .portrait }
        let menu = app.buttons["main-menu"]; XCTAssertTrue(menu.waitForExistence(timeout: 45)); menu.tap()
        let navigation = app.descendants(matching: .any).matching(identifier: "navigation-scroll").firstMatch
        XCTAssertTrue(navigation.waitForExistence(timeout: 10)); let music = app.buttons["nav-music"]
        for _ in 0..<12 { if music.isHittable { break }; navigation.swipeDown() }
        for _ in 0..<12 { if music.isHittable { break }; navigation.swipeUp() }
        XCTAssertTrue(music.isHittable); music.press(forDuration: 0.6)
        let screen = app.segmentedControls["music-screen"]; XCTAssertTrue(screen.waitForExistence(timeout: 20))
        XCTAssertTrue(screen.buttons.element(boundBy: 0).isSelected)
        let hero = app.buttons["music-for-you-hero"]; XCTAssertTrue(hero.waitForExistence(timeout: 45))
        capture("music-open-home-" + device)
        let scroll = app.scrollViews["music-discovery-scroll"], search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 15)); ReadingUIInteraction.reveal(search, in: app, up: false, container: scroll)
        search.tap(); search.typeText("Beethoven\n")
        XCTAssertTrue(app.staticTexts["music-catalog-search-ready"].waitForExistence(timeout: 45))
        let album = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'music-catalog-item-album|'")).firstMatch
        ReadingUIInteraction.reveal(album, in: app, container: scroll); capture("music-open-search-" + device)
        ReadingUIInteraction.tapVisible(album, in: app)
        let title = app.staticTexts["music-catalog-detail-title"]; XCTAssertTrue(title.waitForExistence(timeout: 20)); let albumTitle = title.label
        let track = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'music-detail-item-track|'")).firstMatch
        XCTAssertTrue(track.waitForExistence(timeout: 45)); ReadingUIInteraction.reveal(track, in: app)
        XCTAssertFalse(albumTitle.isEmpty); capture("music-open-album-" + device)
        ReadingUIInteraction.back(from: albumTitle, in: app)
        let artist = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'music-catalog-item-artist|'")).firstMatch
        ReadingUIInteraction.revealWithinViewport(artist, in: app, container: scroll); ReadingUIInteraction.tapVisible(artist, in: app)
        let kinds = app.segmentedControls["music-artist-catalog-kind"]; XCTAssertTrue(kinds.waitForExistence(timeout: 20))
        ReadingUIInteraction.tapVisible(kinds.buttons.element(boundBy: 1), in: app)
        let artistAlbum = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'music-detail-item-album|'")).firstMatch
        XCTAssertTrue(artistAlbum.waitForExistence(timeout: 45)); ReadingUIInteraction.reveal(artistAlbum, in: app)
        XCTAssertFalse(title.label.isEmpty); capture("music-open-artist-" + device)
    }
    private func capture(_ name: String) {
        let image = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); image.name = name; image.lifetime = .keepAlways; add(image)
    }
}

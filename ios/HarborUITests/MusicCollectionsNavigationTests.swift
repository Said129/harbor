import XCTest

@MainActor final class MusicCollectionsNavigationTests: XCTestCase {
    func testSavedTracksActualPlaybackAndRecentCollectionKeepTheirIndependentContentsOnIPhone() { verify("iphone") }
    func testSavedTracksActualPlaybackAndRecentCollectionKeepTheirIndependentContentsOnIPad() { verify("ipad") }
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
        let tabs = app.segmentedControls["music-library-category"]; XCTAssertTrue(tabs.waitForExistence(timeout: 20))
        let song = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'music-track-' AND label CONTAINS 'owned-tone'")).firstMatch
        XCTAssertTrue(song.waitForExistence(timeout: 20)); ReadingUIInteraction.reveal(song, in: app); song.press(forDuration: 1)
        let save = app.buttons["music-track-like"]; XCTAssertTrue(save.waitForExistence(timeout: 10)); save.tap()
        expect("Saved", valueOf: song)
        ReadingUIInteraction.tapVisible(tabs.buttons.element(boundBy: 3), in: app)
        let liked = app.buttons["music-collection-liked"], recent = app.buttons["music-collection-recent"]
        expect("1", valueOf: liked); expect("0", valueOf: recent); capture("music-collections-liked-" + device)
        ReadingUIInteraction.tapVisible(liked, in: app)
        let savedSong = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'music-collection-track-'")).firstMatch
        XCTAssertTrue(savedSong.waitForExistence(timeout: 15)); ReadingUIInteraction.tapVisible(savedSong, in: app)
        capture("music-collections-playing-" + device)
        ReadingUIInteraction.back(from: "Saved", in: app)
        expect("1", valueOf: recent); expect("1", valueOf: liked); ReadingUIInteraction.tapVisible(recent, in: app)
        let recentSong = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'music-collection-track-'")).firstMatch
        XCTAssertTrue(recentSong.waitForExistence(timeout: 15)); expect("Saved", valueOf: recentSong)
        capture("music-collections-recent-" + device); recentSong.press(forDuration: 1)
        XCTAssertTrue(save.waitForExistence(timeout: 10)); save.tap(); expect("", valueOf: recentSong)
        ReadingUIInteraction.back(from: "Recently played", in: app)
        expect("0", valueOf: liked); expect("1", valueOf: recent); capture("music-collections-unliked-" + device)
    }
    private func expect(_ value: String, valueOf element: XCUIElement) {
        XCTAssertTrue(element.waitForExistence(timeout: 20))
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", value), object: element)], timeout: 20), .completed)
    }
    private func capture(_ name: String) {
        let image = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); image.name = name; image.lifetime = .keepAlways; add(image)
    }
}

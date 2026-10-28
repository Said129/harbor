import XCTest

@MainActor final class LibraryTrackerTabsNavigationTests: XCTestCase {
    func testChangedLibraryTabsKeepLocalFiltersSelectableAndDisconnectedTrackersHiddenOnIPhone() { verify("iphone") }
    func testChangedLibraryTabsKeepLocalFiltersSelectableAndDisconnectedTrackersHiddenOnIPad() { verify("ipad") }
    private func verify(_ device: String) {
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "site.harbor.iphone")
        app.launchArguments = ["-uiLanguage", "en", "-homeMode", "classic", "-nativeGuide.initialized.v1", "YES", "-nativeGuide.completed.v1", "YES"]
        ReadingUIInteraction.launchPreparedApplication(app)
        defer { if (testRun?.failureCount ?? 0) > 0 { ReadingUIInteraction.recordFailureContext(app) }; app.terminate() }
        let menu = app.buttons["main-menu"]; XCTAssertTrue(menu.waitForExistence(timeout: 45)); ReadingUIInteraction.tapVisible(menu, in: app)
        let navigation = app.descendants(matching: .any).matching(identifier: "navigation-scroll").firstMatch
        let library = app.buttons["nav-library"]; ReadingUIInteraction.reveal(library, in: app, container: navigation); ReadingUIInteraction.tapVisible(library, in: app)
        let bar = app.scrollViews["library-filter"]; XCTAssertTrue(bar.waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["library-tab-trakt"].exists); XCTAssertFalse(app.buttons["library-tab-simkl"].exists)
        for name in ["all", "saved", "watchlist", "watched", "favorites", "continue"] {
            let tab = app.buttons["library-tab-" + name]
            for _ in 0..<4 { if tab.isHittable { break }; bar.swipeLeft() }
            XCTAssertTrue(tab.isEnabled); XCTAssertTrue(tab.isHittable); ReadingUIInteraction.tapVisible(tab, in: app)
            let selected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "selected == true"), object: tab)
            XCTAssertEqual(XCTWaiter.wait(for: [selected], timeout: 5), .completed)
            if ["all", "watchlist", "continue"].contains(name) {
                let image = XCTAttachment(screenshot: app.screenshot()); image.name = "library-tracker-tabs-" + name + "-" + device; image.lifetime = .keepAlways; add(image)
            }
        }
    }
}

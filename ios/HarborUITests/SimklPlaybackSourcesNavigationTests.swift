import XCTest

@MainActor final class SimklPlaybackSourcesNavigationTests: XCTestCase {
    func testActualSourceTapPersistsAfterRelaunchAndCanBeDisabledOnIPhone() { verify("iphone") }
    func testActualSourceTapPersistsAfterRelaunchAndCanBeDisabledOnIPad() { verify("ipad") }
    private func verify(_ device: String) {
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "site.harbor.iphone")
        app.launchArguments = ["-uiLanguage", "en", "-homeMode", "classic", "-nativeGuide.initialized.v1", "YES", "-nativeGuide.completed.v1", "YES"]
        ReadingUIInteraction.launchPreparedApplication(app)
        defer { if (testRun?.failureCount ?? 0) > 0 { ReadingUIInteraction.recordFailureContext(app) }; app.terminate() }
        openLibrarySettings(app)
        let toggle = app.switches["settings-cw-simkl"]
        show(toggle, app); XCTAssertEqual(toggle.value as? String, "0"); capture(app, "simkl-playback-source-off-" + device)
        ReadingUIInteraction.tapVisible(toggle, in: app)
        XCTAssertEqual(toggle.value as? String, "1"); capture(app, "simkl-playback-source-enabled-" + device)
        app.terminate(); ReadingUIInteraction.launchPreparedApplication(app); openLibrarySettings(app)
        show(toggle, app); XCTAssertEqual(toggle.value as? String, "1"); capture(app, "simkl-playback-source-restored-" + device)
        ReadingUIInteraction.tapVisible(toggle, in: app); XCTAssertEqual(toggle.value as? String, "0")
    }
    private func openLibrarySettings(_ app: XCUIApplication) {
        let menu = app.buttons["main-menu"]; XCTAssertTrue(menu.waitForExistence(timeout: 45)); ReadingUIInteraction.tapVisible(menu, in: app)
        let navigation = app.descendants(matching: .any).matching(identifier: "navigation-scroll").firstMatch
        XCTAssertTrue(navigation.waitForExistence(timeout: 10))
        let settings = app.buttons["nav-settings"]
        ReadingUIInteraction.reveal(settings, in: app, container: navigation); ReadingUIInteraction.tapVisible(settings, in: app)
        let scroll = app.scrollViews["settings-scroll"]; XCTAssertTrue(scroll.waitForExistence(timeout: 15))
        let library = app.buttons["settings-interface"]
        ReadingUIInteraction.reveal(library, in: app, container: scroll); ReadingUIInteraction.tapVisible(library, in: app)
        XCTAssertTrue(app.scrollViews["interface-settings-scroll"].waitForExistence(timeout: 15))
    }
    private func show(_ element: XCUIElement, _ app: XCUIApplication) {
        ReadingUIInteraction.reveal(element, in: app, container: app.scrollViews["interface-settings-scroll"])
        XCTAssertTrue(element.isEnabled); XCTAssertTrue(element.isHittable)
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}

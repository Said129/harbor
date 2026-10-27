import XCTest

@MainActor final class TraktSourcesNavigationTests: XCTestCase {
    func testActualTraktSourceControlPersistsAndRemainsDisconnectedWithoutProviderCredentialsOnIPhone() { verify("iphone") }
    func testActualTraktSourceControlPersistsAndRemainsDisconnectedWithoutProviderCredentialsOnIPad() { verify("ipad") }
    private func verify(_ device: String) {
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "site.harbor.iphone")
        app.launchArguments = ["-uiLanguage", "en", "-homeMode", "classic", "-nativeGuide.initialized.v1", "YES", "-nativeGuide.completed.v1", "YES"]
        ReadingUIInteraction.launchPreparedApplication(app)
        defer { if (testRun?.failureCount ?? 0) > 0 { ReadingUIInteraction.recordFailureContext(app) }; app.terminate() }
        open(app)
        let progress = app.switches["trakt-enable-progress"], state = app.staticTexts["trakt-connection-state"], connect = app.buttons["trakt-connect"]
        XCTAssertTrue(state.waitForExistence(timeout: 15)); XCTAssertEqual(state.label, "Not connected"); XCTAssertTrue(connect.isEnabled)
        show(progress, app); XCTAssertEqual(progress.value as? String, "0"); capture(app, "trakt-source-off-" + device)
        set(progress, "1", app); XCTAssertEqual(state.label, "Not connected"); capture(app, "trakt-source-enabled-" + device)
        app.terminate(); ReadingUIInteraction.launchPreparedApplication(app); open(app)
        XCTAssertTrue(state.waitForExistence(timeout: 15)); XCTAssertEqual(state.label, "Not connected"); XCTAssertTrue(connect.isEnabled)
        show(progress, app); XCTAssertEqual(progress.value as? String, "1"); capture(app, "trakt-source-restored-" + device)
        set(progress, "0", app)
    }
    private func open(_ app: XCUIApplication) {
        let menu = app.buttons["main-menu"]; XCTAssertTrue(menu.waitForExistence(timeout: 45)); ReadingUIInteraction.tapVisible(menu, in: app)
        let navigation = app.descendants(matching: .any).matching(identifier: "navigation-scroll").firstMatch
        XCTAssertTrue(navigation.waitForExistence(timeout: 10))
        let settings = app.buttons["nav-settings"]; ReadingUIInteraction.reveal(settings, in: app, container: navigation); ReadingUIInteraction.tapVisible(settings, in: app)
        let scroll = app.scrollViews["settings-scroll"]; XCTAssertTrue(scroll.waitForExistence(timeout: 15))
        let trakt = app.buttons["settings-trakt"]; ReadingUIInteraction.revealWithinViewport(trakt, in: app, container: scroll); ReadingUIInteraction.tapVisible(trakt, in: app)
        XCTAssertTrue(app.scrollViews["trakt-settings-scroll"].waitForExistence(timeout: 15))
    }
    private func show(_ element: XCUIElement, _ app: XCUIApplication) {
        ReadingUIInteraction.revealWithinViewport(element, in: app, container: app.scrollViews["trakt-settings-scroll"])
        XCTAssertTrue(element.isEnabled); XCTAssertTrue(element.isHittable)
    }
    private func set(_ element: XCUIElement, _ expected: String, _ app: XCUIApplication) {
        show(element, app); ReadingUIInteraction.tapVisible(element, in: app)
        let changed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", expected), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 10), .completed); XCTAssertEqual(element.value as? String, expected)
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}

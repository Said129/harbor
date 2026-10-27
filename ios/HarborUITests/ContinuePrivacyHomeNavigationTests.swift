import XCTest

@MainActor final class ContinuePrivacyHomeNavigationTests: XCTestCase {
    func testActualHomeSwitchesPrivateHistoriesKeepsDismissalAfterRestartAndRevealsSharedModeOnIPhone() { verify("iphone") }
    func testActualHomeSwitchesPrivateHistoriesKeepsDismissalAfterRestartAndRevealsSharedModeOnIPad() { verify("ipad") }
    private func verify(_ device: String) {
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "site.harbor.iphone")
        app.launchArguments = ["-uiLanguage", "en", "-homeMode", "classic", "-nativeGuide.initialized.v1", "YES", "-nativeGuide.completed.v1", "YES"]
        ReadingUIInteraction.launchPreparedApplication(app)
        defer { if (testRun?.failureCount ?? 0) > 0 { ReadingUIInteraction.recordFailureContext(app) }; app.terminate() }
        expectHome(app, a: true, b: false); capture(app, "private-home-primary-" + device)
        let remove = app.buttons.matching(identifier: "continue-watching-remove").firstMatch
        XCTAssertTrue(remove.waitForExistence(timeout: 10)); ReadingUIInteraction.tapVisible(remove, in: app)
        expectHome(app, a: false, b: false); capture(app, "private-home-dismissed-" + device)
        chooseProfile(app, other: true)
        expectHome(app, a: false, b: true); capture(app, "private-home-other-" + device)
        chooseProfile(app, other: false)
        expectHome(app, a: false, b: false)
        app.terminate(); ReadingUIInteraction.launchPreparedApplication(app)
        expectHome(app, a: false, b: false); capture(app, "private-home-restored-" + device)
        openLibrarySettings(app)
        let privacy = app.switches["settings-cw-private"]
        ReadingUIInteraction.reveal(privacy, in: app, container: app.scrollViews["interface-settings-scroll"])
        XCTAssertEqual(privacy.value as? String, "1"); ReadingUIInteraction.tapVisible(privacy, in: app)
        XCTAssertEqual(privacy.value as? String, "0")
        app.terminate(); ReadingUIInteraction.launchPreparedApplication(app)
        expectHome(app, a: true, b: true); capture(app, "private-home-shared-" + device)
    }
    private func card(_ title: String, _ app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(identifier: "continue-watching-resume").matching(NSPredicate(format: "label CONTAINS %@", title)).firstMatch
    }
    private func expectHome(_ app: XCUIApplication, a: Bool, b: Bool) {
        let account = app.buttons.matching(identifier: "main-account").firstMatch
        XCTAssertTrue(account.waitForExistence(timeout: 45))
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isHittable == true"), object: account)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 15), .completed)
        XCTAssertTrue(app.scrollViews["home-scroll"].waitForExistence(timeout: 20))
        let settled = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            self.card("Owned private A", app).exists == a && self.card("Owned private B", app).exists == b
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [settled], timeout: 30), .completed)
        XCTAssertEqual(card("Owned private A", app).exists, a); XCTAssertEqual(card("Owned private B", app).exists, b)
    }
    private func chooseProfile(_ app: XCUIApplication, other: Bool) {
        ReadingUIInteraction.tapVisible(app.buttons.matching(identifier: "main-account").firstMatch, in: app)
        let manage = app.buttons["account-manage-profiles"]
        XCTAssertTrue(manage.waitForExistence(timeout: 15)); ReadingUIInteraction.tapVisible(manage, in: app)
        let predicate = NSPredicate(format: other ? "identifier BEGINSWITH %@ AND label CONTAINS %@" : "identifier BEGINSWITH %@ AND NOT (label CONTAINS %@)", "household-select-", "Owned shared profile")
        let profile = app.buttons.matching(predicate).firstMatch
        XCTAssertTrue(profile.waitForExistence(timeout: 15)); ReadingUIInteraction.tapVisible(profile, in: app)
    }
    private func openLibrarySettings(_ app: XCUIApplication) {
        ReadingUIInteraction.tapVisible(app.buttons["main-menu"], in: app)
        let navigation = app.descendants(matching: .any).matching(identifier: "navigation-scroll").firstMatch
        XCTAssertTrue(navigation.waitForExistence(timeout: 10))
        let settings = app.buttons["nav-settings"]
        ReadingUIInteraction.reveal(settings, in: app, container: navigation); ReadingUIInteraction.tapVisible(settings, in: app)
        let scroll = app.scrollViews["settings-scroll"]; XCTAssertTrue(scroll.waitForExistence(timeout: 15))
        let library = app.buttons["settings-interface"]
        ReadingUIInteraction.reveal(library, in: app, container: scroll); ReadingUIInteraction.tapVisible(library, in: app)
        XCTAssertTrue(app.scrollViews["interface-settings-scroll"].waitForExistence(timeout: 15))
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}

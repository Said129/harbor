import XCTest

@MainActor final class HarborLocalAccountNavigationTests: XCTestCase {
    func testActualAccountKeepsHarborProfilesAndHarborLoginWithoutAnyStremioAccountEntryOnIPhone() { verify("iphone") }
    func testActualAccountKeepsHarborProfilesAndHarborLoginWithoutAnyStremioAccountEntryOnIPad() { verify("ipad") }
    private func verify(_ device: String) {
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "site.harbor.iphone")
        app.launchArguments = ["-uiLanguage", "en", "-homeMode", "classic", "-nativeGuide.initialized.v1", "YES", "-nativeGuide.completed.v1", "YES"]
        ReadingUIInteraction.launchPreparedApplication(app)
        defer { if (testRun?.failureCount ?? 0) > 0 { ReadingUIInteraction.recordFailureContext(app) }; app.terminate() }
        open(app)
        let scroll = app.scrollViews["account-scroll"]
        XCTAssertTrue(app.buttons["account-tab-profile"].exists); XCTAssertTrue(app.buttons["account-tab-profiles"].exists); XCTAssertTrue(app.buttons["account-tab-harbor"].exists)
        XCTAssertFalse(app.buttons["account-tab-stremio"].exists); XCTAssertFalse(app.buttons["account-browser-login"].exists); XCTAssertFalse(app.textFields["account-email"].exists)
        capture(app, "harbor-local-account-profile-" + device)
        ReadingUIInteraction.tapVisible(app.buttons["account-tab-profiles"], in: app)
        XCTAssertTrue(app.buttons["account-manage-profiles"].exists)
        capture(app, "harbor-local-account-profiles-" + device)
        ReadingUIInteraction.tapVisible(app.buttons["account-tab-harbor"], in: app)
        let username = app.textFields["harbor-username"], password = app.secureTextFields["harbor-password"], login = app.buttons["harbor-login"]
        XCTAssertTrue(username.waitForExistence(timeout: 15)); XCTAssertTrue(password.exists)
        ReadingUIInteraction.revealWithinViewport(login, in: app, container: scroll)
        XCTAssertFalse(login.isEnabled); XCTAssertFalse(app.buttons["account-login"].exists)
        capture(app, "harbor-local-account-harbor-" + device)
        ReadingUIInteraction.tapVisible(app.buttons["account-close"], in: app)
        app.terminate(); ReadingUIInteraction.launchPreparedApplication(app); open(app)
        XCTAssertTrue(app.buttons["account-tab-profile"].exists); XCTAssertFalse(app.buttons["account-tab-stremio"].exists)
        XCTAssertFalse(app.textFields["account-email"].exists)
    }
    private func open(_ app: XCUIApplication) {
        let account = app.buttons["main-account"].firstMatch
        XCTAssertTrue(account.waitForExistence(timeout: 45)); ReadingUIInteraction.tapVisible(account, in: app)
        XCTAssertTrue(app.scrollViews["account-scroll"].waitForExistence(timeout: 15))
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}

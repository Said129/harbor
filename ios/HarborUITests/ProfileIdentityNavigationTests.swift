import XCTest

@MainActor final class ProfileIdentityNavigationTests: XCTestCase {
    func testHarborIdentityRemainsPrivateAcrossProfileChangesAndExplicitLogoutSurvivesRelaunchOnIPhone() { verify("iphone") }
    func testHarborIdentityRemainsPrivateAcrossProfileChangesAndExplicitLogoutSurvivesRelaunchOnIPad() { verify("ipad") }
    private func verify(_ device: String) {
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "site.harbor.iphone")
        app.launchArguments = ["-uiLanguage", "en", "-nativeGuide.initialized.v1", "YES", "-nativeGuide.completed.v1", "YES"]
        ReadingUIInteraction.launchPreparedApplication(app)
        defer { if (testRun?.failureCount ?? 0) > 0 { ReadingUIInteraction.recordFailureContext(app) }; app.terminate() }
        openIdentity(app)
        let signout = app.buttons["harbor-signout"]
        XCTAssertTrue(signout.waitForExistence(timeout: 15)); XCTAssertFalse(app.buttons["harbor-login"].exists)
        capture(app, "profile-identity-primary-" + device)
        let tabs = app.scrollViews["account-tabs"], profile = app.buttons["account-tab-profile"]
        ReadingUIInteraction.revealWithinViewport(tabs, in: app, container: app.scrollViews["account-scroll"])
        for _ in 0..<6 { if profile.isHittable { break }; tabs.swipeRight() }
        ReadingUIInteraction.tapVisible(profile, in: app)
        let name = app.textFields["profile-name"]
        XCTAssertTrue(name.waitForExistence(timeout: 15)); XCTAssertTrue(name.isEnabled, "Cached profiles remain editable while the old account server is unavailable")
        select("Owned independent", app)
        openIdentity(app)
        XCTAssertTrue(app.buttons["harbor-login"].waitForExistence(timeout: 15)); XCTAssertFalse(signout.exists)
        XCTAssertFalse(app.staticTexts["harbor-connected-server"].exists)
        capture(app, "profile-identity-secondary-" + device)
        select("Owned primary", app)
        openIdentity(app)
        XCTAssertTrue(signout.waitForExistence(timeout: 15)); XCTAssertFalse(app.buttons["harbor-login"].exists)
        capture(app, "profile-identity-restored-" + device)
        ReadingUIInteraction.revealWithinViewport(signout, in: app, container: app.scrollViews["account-scroll"])
        ReadingUIInteraction.tapVisible(signout, in: app)
        XCTAssertTrue(app.buttons["harbor-login"].waitForExistence(timeout: 15)); XCTAssertFalse(signout.exists)
        app.terminate(); ReadingUIInteraction.launchPreparedApplication(app)
        openIdentity(app)
        XCTAssertTrue(app.buttons["harbor-login"].waitForExistence(timeout: 15)); XCTAssertFalse(signout.exists)
        XCTAssertFalse(app.staticTexts["harbor-connected-server"].exists)
        capture(app, "profile-identity-logout-reopened-" + device)
    }
    private func openIdentity(_ app: XCUIApplication) {
        let account = app.buttons["main-account"].firstMatch
        XCTAssertTrue(account.waitForExistence(timeout: 45))
        let available = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isHittable == true"), object: account)
        XCTAssertEqual(XCTWaiter.wait(for: [available], timeout: 15), .completed)
        ReadingUIInteraction.tapVisible(account, in: app)
        let tab = app.buttons["account-tab-harbor"], tabs = app.scrollViews["account-tabs"]
        XCTAssertTrue(tabs.waitForExistence(timeout: 15))
        for _ in 0..<6 { if tab.isHittable { break }; tabs.swipeLeft() }
        ReadingUIInteraction.tapVisible(tab, in: app)
    }
    private func select(_ name: String, _ app: XCUIApplication) {
        let manage = app.buttons["account-manage-profiles"]
        ReadingUIInteraction.revealWithinViewport(manage, in: app, container: app.scrollViews["account-scroll"])
        ReadingUIInteraction.tapVisible(manage, in: app)
        let choice = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label ENDSWITH %@", "household-select-", name)).firstMatch
        XCTAssertTrue(choice.waitForExistence(timeout: 20)); ReadingUIInteraction.tapVisible(choice, in: app)
        let account = app.buttons["main-account"].firstMatch
        let changed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@ AND isHittable == true", name), object: account)
        XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 30), .completed)
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}

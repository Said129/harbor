import XCTest

@MainActor final class HarborIdentityServerNavigationTests: XCTestCase {
    func testTheAccountServerIsVisibleAndChangingItClearsThePasswordOnIPhone() { verify("iphone") }
    func testTheAccountServerIsVisibleAndChangingItClearsThePasswordOnIPad() { verify("ipad") }
    private func verify(_ device: String) {
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "site.harbor.iphone")
        app.launchArguments = ["-uiLanguage", "en", "-nativeGuide.initialized.v1", "YES", "-nativeGuide.completed.v1", "YES"]
        ReadingUIInteraction.launchPreparedApplication(app)
        defer {
            if (testRun?.failureCount ?? 0) > 0 { ReadingUIInteraction.recordFailureContext(app) }
            app.terminate()
        }
        let account = app.buttons["main-account"].firstMatch
        XCTAssertTrue(account.waitForExistence(timeout: 45)); ReadingUIInteraction.tapVisible(account, in: app)
        let tab = app.buttons["account-tab-harbor"], tabs = app.scrollViews["account-tabs"]
        XCTAssertTrue(tabs.waitForExistence(timeout: 15))
        for _ in 0..<6 { if tab.isHittable { break }; tabs.swipeLeft() }
        ReadingUIInteraction.tapVisible(tab, in: app)
        let choice = app.segmentedControls["harbor-server-choice"], password = app.secureTextFields["harbor-password"]
        let scroll = app.scrollViews["account-scroll"]
        XCTAssertTrue(scroll.waitForExistence(timeout: 10))
        XCTAssertTrue(choice.waitForExistence(timeout: 15)); XCTAssertTrue(app.staticTexts["harborcommunity.site"].exists)
        XCTAssertTrue(choice.buttons["Harbor Community"].isSelected)
        capture(app, "identity-server-community-" + device)
        let username = app.textFields["harbor-username"], login = app.buttons["harbor-login"]
        ReadingUIInteraction.revealWithinViewport(username, in: app, container: scroll); ReadingUIInteraction.tapVisible(username, in: app); username.typeText("owned-ui-user")
        ReadingUIInteraction.revealWithinViewport(password, in: app, container: scroll); ReadingUIInteraction.tapVisible(password, in: app); password.typeText("owned-ui-password")
        ReadingUIInteraction.revealWithinViewport(choice, in: app, container: scroll)
        XCTAssertEqual(choice.buttons.count, 2); ReadingUIInteraction.tapVisible(choice.buttons.element(boundBy: 1), in: app)
        assertEmpty(password); XCTAssertFalse(login.isEnabled)
        let url = app.textFields["harbor-server-url"]
        ReadingUIInteraction.revealWithinViewport(url, in: app, container: scroll); ReadingUIInteraction.tapVisible(url, in: app); url.typeText("http://owned.example")
        ReadingUIInteraction.revealWithinViewport(password, in: app, container: scroll); ReadingUIInteraction.tapVisible(password, in: app); password.typeText("owned-ui-password")
        XCTAssertFalse(login.isEnabled, "An insecure origin cannot receive a password")
        ReadingUIInteraction.revealWithinViewport(url, in: app, container: scroll); ReadingUIInteraction.replace(url, with: "https://owned.example", in: app)
        assertEmpty(password)
        ReadingUIInteraction.revealWithinViewport(password, in: app, container: scroll); ReadingUIInteraction.tapVisible(password, in: app); password.typeText("owned-ui-password")
        XCTAssertTrue(login.isEnabled)
        ReadingUIInteraction.revealWithinViewport(choice, in: app, container: scroll); capture(app, "identity-server-custom-" + device)
        ReadingUIInteraction.tapVisible(choice.buttons.element(boundBy: 0), in: app)
        assertEmpty(password); XCTAssertFalse(url.exists); XCTAssertFalse(login.isEnabled)
        XCTAssertTrue(app.staticTexts["harborcommunity.site"].exists)
        capture(app, "identity-server-restored-" + device)
    }
    private func assertEmpty(_ field: XCUIElement) {
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        let cleared = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let value = field.value as? String
            return value == "" || value == field.placeholderValue
        }, object: field)
        XCTAssertEqual(XCTWaiter.wait(for: [cleared], timeout: 5), .completed)
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}

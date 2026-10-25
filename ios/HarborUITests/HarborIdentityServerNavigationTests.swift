import XCTest

@MainActor final class HarborIdentityServerNavigationTests: XCTestCase {
    func testTheAccountServerIsVisibleAndChangingItClearsThePasswordOnIPhone() { verify("iphone") }
    func testTheAccountServerIsVisibleAndChangingItClearsThePasswordOnIPad() { verify("ipad") }
    private func verify(_ device: String) {
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "site.harbor.iphone")
        app.launchArguments = ["-uiLanguage", "en", "-nativeGuide.initialized.v1", "YES", "-nativeGuide.completed.v1", "YES"]
        ReadingUIInteraction.launchPreparedApplication(app); defer { app.terminate() }
        let account = app.buttons["main-account"].firstMatch
        XCTAssertTrue(account.waitForExistence(timeout: 45)); ReadingUIInteraction.tapVisible(account, in: app)
        let tab = app.buttons["account-tab-harbor"], tabs = app.scrollViews["account-tabs"]
        XCTAssertTrue(tabs.waitForExistence(timeout: 15))
        for _ in 0..<6 { if tab.isHittable { break }; tabs.swipeLeft() }
        ReadingUIInteraction.tapVisible(tab, in: app)
        let choice = app.segmentedControls["harbor-server-choice"], password = app.secureTextFields["harbor-password"]
        XCTAssertTrue(choice.waitForExistence(timeout: 15)); XCTAssertTrue(app.staticTexts["harborcommunity.site"].exists)
        XCTAssertTrue(choice.buttons["Harbor Community"].isSelected)
        capture(app, "identity-server-community-" + device)
        let username = app.textFields["harbor-username"], login = app.buttons["harbor-login"]
        ReadingUIInteraction.reveal(username, in: app); ReadingUIInteraction.replace(username, with: "owned-ui-user", in: app)
        ReadingUIInteraction.reveal(password, in: app); ReadingUIInteraction.tapVisible(password, in: app); password.typeText("owned-ui-password")
        ReadingUIInteraction.reveal(choice, in: app, up: false); ReadingUIInteraction.tapVisible(choice.buttons["Personalizado"], in: app)
        assertEmpty(password); XCTAssertFalse(login.isEnabled)
        let url = app.textFields["harbor-server-url"]
        ReadingUIInteraction.reveal(url, in: app); ReadingUIInteraction.replace(url, with: "http://owned.example", in: app)
        ReadingUIInteraction.reveal(password, in: app); ReadingUIInteraction.tapVisible(password, in: app); password.typeText("owned-ui-password")
        XCTAssertFalse(login.isEnabled, "An insecure origin cannot receive a password")
        ReadingUIInteraction.reveal(url, in: app, up: false); ReadingUIInteraction.replace(url, with: "https://owned.example", in: app)
        assertEmpty(password)
        ReadingUIInteraction.reveal(password, in: app); ReadingUIInteraction.tapVisible(password, in: app); password.typeText("owned-ui-password")
        XCTAssertTrue(login.isEnabled)
        ReadingUIInteraction.reveal(choice, in: app, up: false); capture(app, "identity-server-custom-" + device)
        ReadingUIInteraction.tapVisible(choice.buttons["Harbor Community"], in: app)
        assertEmpty(password); XCTAssertFalse(url.exists); XCTAssertFalse(login.isEnabled)
        XCTAssertTrue(app.staticTexts["harborcommunity.site"].exists)
        capture(app, "identity-server-restored-" + device)
    }
    private func assertEmpty(_ field: XCUIElement) {
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

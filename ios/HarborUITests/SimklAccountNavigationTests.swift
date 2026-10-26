import XCTest

@MainActor final class SimklAccountNavigationTests: XCTestCase {
    func testPublicDeviceCodeCopyCancelAndReopenWithoutAuthorizingAnyPersonalAccountOnIPhone() { verify("iphone") }
    func testPublicDeviceCodeCopyCancelAndReopenWithoutAuthorizingAnyPersonalAccountOnIPad() { verify("ipad") }
    private func verify(_ device: String) {
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "site.harbor.iphone")
        app.launchArguments = ["-uiLanguage", "en", "-homeMode", "classic", "-nativeGuide.initialized.v1", "YES", "-nativeGuide.completed.v1", "YES"]
        ReadingUIInteraction.launchPreparedApplication(app)
        defer { if (testRun?.failureCount ?? 0) > 0 { ReadingUIInteraction.recordFailureContext(app) }; app.terminate() }
        openSimkl(app)
        let state = app.staticTexts["simkl-connection-state"], connect = app.buttons["simkl-connect"]
        XCTAssertTrue(state.waitForExistence(timeout: 15)); XCTAssertEqual(state.label, "Not connected")
        XCTAssertTrue(connect.isEnabled); capture(app, "simkl-disconnected-" + device)
        ReadingUIInteraction.tapVisible(connect, in: app)
        let pin = app.buttons["simkl-pin-code"], cancel = app.buttons["simkl-cancel"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 15)); XCTAssertTrue(pin.waitForExistence(timeout: 45), "The public provider must issue a code before any personal account is authorized")
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "simkl-authorize-link").firstMatch.exists)
        ReadingUIInteraction.revealWithinViewport(pin, in: app, container: app.scrollViews["simkl-authorization-scroll"])
        capture(app, "simkl-code-" + device)
        ReadingUIInteraction.tapVisible(pin, in: app)
        let copied = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", "Copied"), object: pin)
        XCTAssertEqual(XCTWaiter.wait(for: [copied], timeout: 5), .completed)
        ReadingUIInteraction.tapVisible(cancel, in: app)
        XCTAssertTrue(connect.waitForExistence(timeout: 10)); XCTAssertTrue(connect.isEnabled)
        XCTAssertEqual(state.label, "Not connected"); XCTAssertFalse(pin.exists)
        app.terminate(); ReadingUIInteraction.launchPreparedApplication(app); openSimkl(app)
        XCTAssertTrue(state.waitForExistence(timeout: 15)); XCTAssertEqual(state.label, "Not connected"); XCTAssertTrue(connect.isEnabled)
        capture(app, "simkl-cancelled-restored-" + device)
    }
    private func openSimkl(_ app: XCUIApplication) {
        let menu = app.buttons["main-menu"]; XCTAssertTrue(menu.waitForExistence(timeout: 45)); ReadingUIInteraction.tapVisible(menu, in: app)
        let navigation = app.descendants(matching: .any).matching(identifier: "navigation-scroll").firstMatch
        XCTAssertTrue(navigation.waitForExistence(timeout: 10))
        let settings = app.buttons["nav-settings"]; ReadingUIInteraction.reveal(settings, in: app, container: navigation); ReadingUIInteraction.tapVisible(settings, in: app)
        let scroll = app.scrollViews["settings-scroll"]; XCTAssertTrue(scroll.waitForExistence(timeout: 15))
        let simkl = app.buttons["settings-simkl"]; ReadingUIInteraction.reveal(simkl, in: app, container: scroll); ReadingUIInteraction.tapVisible(simkl, in: app)
        XCTAssertTrue(app.scrollViews["simkl-settings-scroll"].waitForExistence(timeout: 15))
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}

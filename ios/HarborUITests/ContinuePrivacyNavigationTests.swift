import XCTest

@MainActor final class ContinuePrivacyNavigationTests: XCTestCase {
    func testActualPrivateChoiceLocksSharedSourcesKeepsDownloadsEditableAndRestoresAllChoicesOnIPhone() { verify("iphone") }
    func testActualPrivateChoiceLocksSharedSourcesKeepsDownloadsEditableAndRestoresAllChoicesOnIPad() { verify("ipad") }
    private func verify(_ device: String) {
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "site.harbor.iphone")
        app.launchArguments = ["-uiLanguage", "en", "-homeMode", "classic", "-nativeGuide.initialized.v1", "YES", "-nativeGuide.completed.v1", "YES"]
        ReadingUIInteraction.launchPreparedApplication(app)
        defer { if (testRun?.failureCount ?? 0) > 0 { ReadingUIInteraction.recordFailureContext(app) }; app.terminate() }
        open(app)
        let privacy = app.switches["settings-cw-private"], library = app.switches["settings-cw-library"], local = app.switches["settings-cw-local"], simkl = app.switches["settings-cw-simkl"]
        show(privacy, app); XCTAssertEqual(privacy.value as? String, "0"); capture(app, "continue-private-default-" + device)
        show(library, app); XCTAssertEqual(library.value as? String, "1"); ReadingUIInteraction.tapVisible(library, in: app)
        show(simkl, app); XCTAssertEqual(simkl.value as? String, "0"); ReadingUIInteraction.tapVisible(simkl, in: app)
        show(privacy, app); tap(privacy, value: "1", app)
        reveal(library, app); XCTAssertFalse(library.isEnabled); XCTAssertEqual(library.value as? String, "0")
        reveal(simkl, app); XCTAssertFalse(simkl.isEnabled); XCTAssertEqual(simkl.value as? String, "1")
        show(local, app); ReadingUIInteraction.tapVisible(local, in: app); XCTAssertEqual(local.value as? String, "0")
        capture(app, "continue-private-locked-" + device)
        app.terminate(); ReadingUIInteraction.launchPreparedApplication(app); open(app)
        show(privacy, app); XCTAssertEqual(privacy.value as? String, "1")
        reveal(library, app); XCTAssertFalse(library.isEnabled); XCTAssertEqual(library.value as? String, "0")
        reveal(simkl, app); XCTAssertFalse(simkl.isEnabled); XCTAssertEqual(simkl.value as? String, "1")
        show(local, app); XCTAssertEqual(local.value as? String, "0"); capture(app, "continue-private-restored-" + device)
        show(privacy, app); tap(privacy, value: "0", app)
        show(library, app); XCTAssertEqual(library.value as? String, "0"); ReadingUIInteraction.tapVisible(library, in: app)
        show(local, app); XCTAssertEqual(local.value as? String, "0"); ReadingUIInteraction.tapVisible(local, in: app)
        show(simkl, app); XCTAssertEqual(simkl.value as? String, "1"); ReadingUIInteraction.tapVisible(simkl, in: app)
        capture(app, "continue-private-unlocked-" + device)
    }
    private func open(_ app: XCUIApplication) {
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
    private func reveal(_ element: XCUIElement, _ app: XCUIApplication) {
        ReadingUIInteraction.revealWithinViewport(element, in: app, container: app.scrollViews["interface-settings-scroll"])
        XCTAssertTrue(element.exists)
    }
    private func show(_ element: XCUIElement, _ app: XCUIApplication) { reveal(element, app); XCTAssertTrue(element.isEnabled); XCTAssertTrue(element.isHittable) }
    private func tap(_ element: XCUIElement, value: String, _ app: XCUIApplication) {
        ReadingUIInteraction.tapVisible(element, in: app)
        let changed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", value), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 10), .completed)
        XCTAssertEqual(element.value as? String, value)
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}

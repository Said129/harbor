import XCTest

@MainActor final class LocalContinueSourcesNavigationTests: XCTestCase {
    func testActualLibraryAndDownloadSourceChoicesPersistAndKeepSimklIndependentOnIPhone() { verify("iphone") }
    func testActualLibraryAndDownloadSourceChoicesPersistAndKeepSimklIndependentOnIPad() { verify("ipad") }
    private func verify(_ device: String) {
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "site.harbor.iphone")
        app.launchArguments = ["-uiLanguage", "en", "-homeMode", "classic", "-nativeGuide.initialized.v1", "YES", "-nativeGuide.completed.v1", "YES"]
        ReadingUIInteraction.launchPreparedApplication(app)
        defer { if (testRun?.failureCount ?? 0) > 0 { ReadingUIInteraction.recordFailureContext(app) }; app.terminate() }
        open(app)
        let library = app.switches["settings-cw-library"], local = app.switches["settings-cw-local"], simkl = app.switches["settings-cw-simkl"]
        for toggle in [library, local] { show(toggle, app); XCTAssertEqual(toggle.value as? String, "1") }
        capture(app, "local-cw-sources-default-" + device)
        show(library, app); ReadingUIInteraction.tapVisible(library, in: app); XCTAssertEqual(library.value as? String, "0")
        show(local, app); XCTAssertEqual(local.value as? String, "1"); ReadingUIInteraction.tapVisible(local, in: app); XCTAssertEqual(local.value as? String, "0")
        show(simkl, app); XCTAssertEqual(simkl.value as? String, "0"); ReadingUIInteraction.tapVisible(simkl, in: app); XCTAssertEqual(simkl.value as? String, "1")
        app.terminate(); ReadingUIInteraction.launchPreparedApplication(app); open(app)
        for toggle in [library, local] { show(toggle, app); XCTAssertEqual(toggle.value as? String, "0") }
        capture(app, "local-cw-sources-restored-" + device)
        show(simkl, app); XCTAssertEqual(simkl.value as? String, "1")
        show(local, app); ReadingUIInteraction.tapVisible(local, in: app); XCTAssertEqual(local.value as? String, "1")
        show(library, app); XCTAssertEqual(library.value as? String, "0"); ReadingUIInteraction.tapVisible(library, in: app); XCTAssertEqual(library.value as? String, "1")
        capture(app, "local-cw-sources-enabled-" + device)
        show(simkl, app); XCTAssertEqual(simkl.value as? String, "1"); ReadingUIInteraction.tapVisible(simkl, in: app); XCTAssertEqual(simkl.value as? String, "0")
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
    private func show(_ element: XCUIElement, _ app: XCUIApplication) {
        ReadingUIInteraction.reveal(element, in: app, container: app.scrollViews["interface-settings-scroll"])
        XCTAssertTrue(element.isEnabled); XCTAssertTrue(element.isHittable)
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}

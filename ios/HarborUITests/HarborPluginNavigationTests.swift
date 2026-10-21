import XCTest

@MainActor final class HarborPluginNavigationTests: XCTestCase {
    func testRealPluginSettingsAndRepositoryControlsOnIPhone() { verify(device: "iphone") }
    func testRealPluginSettingsAndRepositoryControlsOnIPad() { verify(device: "ipad") }

    private func verify(device: String) {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-uiLanguage", "es", "-nativeGuide.initialized.v1", "YES", "-nativeGuide.completed.v1", "YES"]
        app.launch(); defer { app.terminate() }
        open(app)
        let configure = app.buttons["plugin-configure-owned.ui.form"]
        XCTAssertTrue(configure.waitForExistence(timeout: 15)); reveal(configure, in: app)
        capture(app, "plugin-installed-" + device)
        configure.tap()
        let token = app.secureTextFields["Token"]
        XCTAssertTrue(token.waitForExistence(timeout: 15)); token.tap(); token.typeText("owned-ui-secret")
        let quality = app.buttons["Quality"]
        reveal(quality, in: app); quality.tap()
        let hd = app.buttons["HD"]; XCTAssertTrue(hd.waitForExistence(timeout: 5)); hd.tap()
        let name = app.textFields["Name"]
        reveal(name, in: app); name.tap()
        if let value = name.value as? String { name.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: value.count)) }
        name.typeText("Owned " + device)
        app.swipeUp()
        capture(app, "plugin-fields-" + device)
        let save = app.buttons["plugin-settings-save"]
        reveal(save, in: app); save.tap()
        XCTAssertTrue(configure.waitForExistence(timeout: 15))
        app.terminate(); app.launch(); open(app)
        let reopened = app.buttons["plugin-configure-owned.ui.form"]
        XCTAssertTrue(reopened.waitForExistence(timeout: 15)); reveal(reopened, in: app); reopened.tap()
        let savedName = app.textFields["Name"]
        XCTAssertTrue(savedName.waitForExistence(timeout: 15)); reveal(savedName, in: app)
        XCTAssertEqual(savedName.value as? String, "Owned " + device)
        XCTAssertTrue(app.buttons["Quality"].exists)
        capture(app, "plugin-persisted-" + device)
        let cancel = app.buttons["Cancelar"]
        reveal(cancel, in: app); cancel.tap()
        let repositories = app.buttons["Repositorios"]
        XCTAssertTrue(repositories.waitForExistence(timeout: 10)); reveal(repositories, in: app); repositories.tap()
        let link = app.textFields["plugin-repository-link"]
        XCTAssertTrue(link.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Owned UI repository"].exists)
        capture(app, "plugin-repositories-" + device)
        app.buttons["Plugins"].tap()
        let remove = app.buttons["plugin-remove-owned.ui.form"]
        reveal(remove, in: app); remove.tap()
        let confirm = app.buttons["plugin-confirm-remove"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5)); confirm.tap()
        XCTAssertTrue(app.staticTexts["plugin-empty"].waitForExistence(timeout: 10))
        capture(app, "plugin-removed-" + device)
    }
    private func open(_ app: XCUIApplication) {
        XCTAssertTrue(app.buttons["main-menu"].waitForExistence(timeout: 45)); app.buttons["main-menu"].tap()
        let navigation = app.descendants(matching: .any).matching(identifier: "navigation-scroll").firstMatch
        XCTAssertTrue(navigation.waitForExistence(timeout: 10))
        let settings = app.buttons["nav-settings"]
        for _ in 0..<10 { if settings.isHittable { break }; navigation.swipeUp() }
        XCTAssertTrue(settings.isHittable); settings.press(forDuration: 0.6)
        let search = app.textFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 10)); search.tap(); search.typeText("Plugins")
        let plugins = app.buttons["settings-plugins"]
        XCTAssertTrue(plugins.waitForExistence(timeout: 10)); reveal(plugins, in: app); plugins.tap()
    }
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        XCTAssertTrue(element.waitForExistence(timeout: 10))
        for _ in 0..<6 { if element.isHittable { return }; app.swipeUp() }
        XCTAssertTrue(element.isHittable)
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}

import XCTest

@MainActor final class ProfileStartupNavigationTests: XCTestCase {
    func testStartupDefaultAndExplicitProfileChoiceOnIPhone() { configure(device: "iphone", name: "iPhone") }
    func testStartupDefaultAndExplicitProfileChoiceOnIPad() { configure(device: "ipad", name: "iPad") }
    func testExpiredReturnPromptAndRecentSelectionOnIPhone() { verifyReturn(device: "iphone", name: "iPhone") }
    func testExpiredReturnPromptAndRecentSelectionOnIPad() { verifyReturn(device: "ipad", name: "iPad") }

    private func app() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiLanguage", "es", "-nativeGuide.initialized.v1", "YES", "-nativeGuide.completed.v1", "YES"]
        return app
    }
    private func configure(device: String, name: String) {
        continueAfterFailure = false
        let app = app(); app.launch(); defer { app.terminate() }
        let normal = "Inicio " + name, protected = "PIN " + name
        create(normal, pin: false, in: app)
        create(protected, pin: true, in: app)
        startupSettings(app)
        choose("profile-startup-interval", option: "Nunca", app: app)
        let defaultMenu = app.buttons["profile-startup-default"]
        reveal(defaultMenu, app: app); defaultMenu.tap()
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label == %@", protected)).firstMatch.exists, "A PIN-protected profile is never offered as a startup default")
        let option = app.buttons.matching(NSPredicate(format: "label == %@", normal)).firstMatch
        XCTAssertTrue(option.waitForExistence(timeout: 5)); option.tap()
        capture("startup-\(device)-default-configured")
        app.buttons["account-close"].tap()
        app.terminate(); app.launch()
        let account = app.buttons["main-account"].firstMatch
        waitValue(normal, element: account)
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "household-select-")).firstMatch.exists)
        capture("startup-\(device)-default-reopened")
        startupSettings(app)
        choose("profile-startup-interval", option: "En cada inicio", app: app)
        choose("profile-startup-default", option: "Sin perfil predeterminado", app: app)
        app.buttons["account-close"].tap()
        app.terminate(); app.launch()
        let choice = profile(normal, app: app)
        XCTAssertTrue(choice.waitForExistence(timeout: 45))
        XCTAssertFalse(account.exists, "The startup picker precedes loading the previous profile's content")
        capture("startup-\(device)-choose")
        closePicker(app)
        waitValue(normal, element: account)
        capture("startup-\(device)-close-reopened")
        startupSettings(app)
        choose("profile-startup-interval", option: "Cada 15 min", app: app)
        choose("profile-startup-default", option: normal, app: app)
        capture("startup-\(device)-timed-configured")
        app.buttons["account-close"].tap()
    }
    private func verifyReturn(device: String, name: String) {
        continueAfterFailure = false
        // The separate native fixture writes an ordinary expired selection time.
        // A default must skip the cold picker but not the later foreground prompt.
        let app = app(); app.launch(); defer { app.terminate() }
        let normal = "Inicio " + name, account = app.buttons["main-account"].firstMatch
        waitValue(normal, element: account)
        XCTAssertFalse(profile(normal, app: app).exists)
        capture("startup-\(device)-cold-default")
        XCUIDevice.shared.press(.home); app.activate()
        let choice = profile(normal, app: app)
        XCTAssertTrue(choice.waitForExistence(timeout: 20)); reveal(choice, app: app)
        capture("startup-\(device)-timed-return")
        choice.tap()
        waitValue(normal, element: account)
        let active = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isHittable == true"), object: account)
        XCTAssertEqual(XCTWaiter.wait(for: [active], timeout: 15), .completed)
        XCUIDevice.shared.press(.home); app.activate()
        // The real selection above resets the persisted timer. No argument-domain
        // clock override is allowed to mask that write on the second return.
        Thread.sleep(forTimeInterval: 2)
        XCTAssertFalse(profile(normal, app: app).exists); XCTAssertTrue(account.isHittable)
        capture("startup-\(device)-recent-return")
    }
    private func create(_ name: String, pin: Bool, in app: XCUIApplication) {
        let account = app.buttons["main-account"].firstMatch
        XCTAssertTrue(account.waitForExistence(timeout: 45)); account.tap()
        let manage = app.buttons["account-manage-profiles"]
        XCTAssertTrue(manage.waitForExistence(timeout: 10)); manage.tap()
        // Only primary creates additional people. Return to the original primary
        // after the first secondary was created and selected by its editor.
        let create = app.buttons["household-profile-create"]
        if !create.waitForExistence(timeout: 3) {
            let other = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label != %@", "household-select-", "Cambiar a Inicio " + (name.hasSuffix("iPad") ? "iPad" : "iPhone"))).firstMatch
            XCTAssertTrue(other.waitForExistence(timeout: 10)); other.tap()
            XCTAssertTrue(account.waitForExistence(timeout: 20))
            let returned = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isHittable == true"), object: account)
            XCTAssertEqual(XCTWaiter.wait(for: [returned], timeout: 15), .completed)
            account.tap(); app.buttons["account-manage-profiles"].tap()
        }
        XCTAssertTrue(create.waitForExistence(timeout: 10)); create.tap()
        let field = app.textFields["household-profile-name"]
        XCTAssertTrue(field.waitForExistence(timeout: 10)); field.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 10)); field.typeText(name + "\n")
        if pin {
            let setPIN = app.buttons["Establecer un PIN"]
            reveal(setPIN, app: app); setPIN.tap(); enterPIN("4826", app: app)
            XCTAssertTrue(app.staticTexts["Confirma tu PIN"].waitForExistence(timeout: 10)); enterPIN("4826", app: app)
        }
        let save = app.buttons["household-profile-save"]
        reveal(save, app: app); save.tap()
        XCTAssertTrue(profile(name, app: app).waitForExistence(timeout: 45)); closePicker(app)
        waitValue(name, element: account)
    }
    private func startupSettings(_ app: XCUIApplication) {
        let account = app.buttons["main-account"].firstMatch
        XCTAssertTrue(account.waitForExistence(timeout: 45)); XCTAssertTrue(account.isHittable); account.tap()
        let tab = app.buttons["account-tab-profiles"]
        XCTAssertTrue(tab.waitForExistence(timeout: 10)); tab.tap()
        XCTAssertTrue(app.buttons["profile-startup-interval"].waitForExistence(timeout: 10))
    }
    private func profile(_ name: String, app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label == %@", "household-select-", "Cambiar a " + name)).firstMatch
    }
    private func choose(_ identifier: String, option: String, app: XCUIApplication) {
        let menu = app.buttons[identifier]
        reveal(menu, app: app); menu.tap()
        let choice = app.buttons.matching(NSPredicate(format: "label == %@", option)).firstMatch
        XCTAssertTrue(choice.waitForExistence(timeout: 5)); choice.tap(); waitValue(option, element: menu)
    }
    private func enterPIN(_ value: String, app: XCUIApplication) {
        let field = app.buttons["profile-pin-entry"]
        XCTAssertTrue(field.waitForExistence(timeout: 10)); waitValue("0 / 4", element: field)
        for digit in value { app.buttons["profile-pin-digit-" + String(digit)].tap() }
    }
    private func closePicker(_ app: XCUIApplication) {
        let visible = app.buttons.matching(NSPredicate(format: "label == %@", "Cerrar")).allElementsBoundByIndex.filter(\.isHittable)
        XCTAssertEqual(visible.count, 1); visible.first?.tap()
        let account = app.buttons["main-account"].firstMatch
        XCTAssertTrue(account.waitForExistence(timeout: 45))
        let closed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isHittable == true"), object: account)
        XCTAssertEqual(XCTWaiter.wait(for: [closed], timeout: 10), .completed)
    }
    private func waitValue(_ value: String, element: XCUIElement) {
        XCTAssertTrue(element.waitForExistence(timeout: 45))
        let changed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", value), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 15), .completed)
    }
    private func reveal(_ element: XCUIElement, app: XCUIApplication) {
        XCTAssertTrue(element.waitForExistence(timeout: 10))
        for _ in 0..<10 { if element.isHittable { break }; if element.frame.midY < app.frame.minY + 80 { app.swipeDown() } else { app.swipeUp() } }
        XCTAssertTrue(element.isHittable)
    }
    private func capture(_ name: String) {
        let image = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); image.name = name; image.lifetime = .keepAlways; add(image)
    }
}

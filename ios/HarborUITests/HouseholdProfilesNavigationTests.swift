import XCTest

@MainActor final class HouseholdProfilesNavigationTests: XCTestCase {
    func testNormalProfileCreationIdentityAndRestartPINWorkOnIPhone() { verifyProfiles(device: "iphone", name: "iPhone") }
    func testNormalProfileCreationIdentityAndRestartPINWorkOnIPad() { verifyProfiles(device: "ipad", name: "iPad") }

    private func verifyProfiles(device: String, name: String) {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["-uiLanguage", "es", "-nativeGuide.initialized.v1", "YES", "-nativeGuide.completed.v1", "YES"]
        app.launch(); defer { app.terminate(); XCUIDevice.shared.orientation = .portrait }
        let account = app.buttons.matching(identifier: "main-account").firstMatch
        XCTAssertTrue(account.waitForExistence(timeout: 45)); account.tap()
        let manage = app.buttons["account-manage-profiles"]
        XCTAssertTrue(manage.waitForExistence(timeout: 10)); manage.tap()
        let create = app.buttons["household-profile-create"]
        XCTAssertTrue(create.waitForExistence(timeout: 10))
        capture(name: "profiles-\(device)-list")
        create.tap()
        let field = app.textFields["household-profile-name"]
        XCTAssertTrue(field.waitForExistence(timeout: 10)); replace(field, with: "Perfil " + name)
        let avatar = app.buttons["Elige un avatar"]
        reveal(avatar, in: app); avatar.tap()
        let person = app.buttons["Person 1"]
        XCTAssertTrue(person.waitForExistence(timeout: 10)); person.tap()
        let setPIN = app.buttons["Establecer un PIN"]
        reveal(setPIN, in: app); setPIN.tap()
        enterPIN("4826", in: app)
        XCTAssertTrue(app.staticTexts["Confirma tu PIN"].waitForExistence(timeout: 10))
        enterPIN("4826", in: app)
        let save = app.buttons["household-profile-save"]
        XCTAssertTrue(save.waitForExistence(timeout: 10)); reveal(save, in: app)
        capture(name: "profiles-\(device)-editor")
        save.tap()
        let chosen = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label == %@", "household-select-", "Cambiar a Perfil " + name)).firstMatch
        XCTAssertTrue(chosen.waitForExistence(timeout: 45))
        XCTAssertFalse(create.exists, "An existing secondary cannot create another profile")
        capture(name: "profiles-\(device)-created")
        closePicker(app)
        XCTAssertTrue(account.waitForExistence(timeout: 15)); expectValue("Perfil " + name, of: account)
        account.tap(); app.buttons["account-tab-profile"].tap()
        let profileName = app.textFields["profile-name"]
        XCTAssertTrue(profileName.waitForExistence(timeout: 10)); expectValue("Perfil " + name, of: profileName)
        replace(profileName, with: "Cuenta " + name)
        expectValue("Cuenta " + name, of: profileName)
        capture(name: "profiles-\(device)-account")
        app.buttons["account-manage-profiles"].tap()
        let renamed = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label == %@", "household-select-", "Cambiar a Cuenta " + name)).firstMatch
        XCTAssertTrue(renamed.waitForExistence(timeout: 10))
        capture(name: "profiles-\(device)-renamed")
        closePicker(app)
        app.terminate(); app.launch()
        XCTAssertTrue(renamed.waitForExistence(timeout: 45)); XCTAssertFalse(account.exists)
        renamed.tap()
        XCTAssertTrue(app.buttons["profile-pin-digit-4"].waitForExistence(timeout: 45))
        XCTAssertTrue(app.staticTexts["Cuenta " + name].exists)
        if device == "ipad" { XCUIDevice.shared.orientation = .landscapeLeft }
        enterPIN("4827", in: app)
        let error = app.staticTexts["profile-pin-error"]
        XCTAssertTrue(error.waitForExistence(timeout: 15)); XCTAssertEqual(error.label, "PIN incorrecto")
        capture(name: "profiles-\(device)-locked")
        enterPIN("4826", in: app)
        XCTAssertTrue(account.waitForExistence(timeout: 30)); expectValue("Cuenta " + name, of: account)
        XCTAssertFalse(app.buttons["profile-pin-digit-4"].exists)
        capture(name: "profiles-\(device)-reopened")
    }
    private func replace(_ field: XCUIElement, with value: String) {
        XCTAssertTrue(field.isHittable)
        let previous = field.value as? String ?? ""
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: previous.count) + value + "\n")
    }
    private func expectValue(_ value: String, of element: XCUIElement) {
        let changed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", value), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 10), .completed)
    }
    private func enterPIN(_ pin: String, in app: XCUIApplication) {
        let entry = app.buttons["profile-pin-entry"]
        XCTAssertTrue(entry.waitForExistence(timeout: 10)); expectValue("0 / 4", of: entry)
        for digit in pin {
            let button = app.buttons["profile-pin-digit-" + String(digit)]
            XCTAssertTrue(button.waitForExistence(timeout: 10)); reveal(button, in: app); XCTAssertTrue(button.isEnabled); button.tap()
        }
    }
    private func closePicker(_ app: XCUIApplication) {
        let buttons = app.buttons.matching(NSPredicate(format: "label == %@", "Cerrar"))
        let visible = buttons.allElementsBoundByIndex.filter(\.isHittable)
        XCTAssertEqual(visible.count, 1); visible.first?.tap()
        let account = app.buttons["main-account"].firstMatch
        XCTAssertTrue(account.waitForExistence(timeout: 15))
        let dismissed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isHittable == true"), object: account)
        XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: 10), .completed)
    }
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        XCTAssertTrue(element.waitForExistence(timeout: 10))
        for _ in 0..<10 {
            if element.isHittable { break }
            if element.frame.midY < app.frame.minY + 80 { app.swipeDown() } else { app.swipeUp() }
        }
        XCTAssertTrue(element.isHittable)
    }
    private func capture(name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}

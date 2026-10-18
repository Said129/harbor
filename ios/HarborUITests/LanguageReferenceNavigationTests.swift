import XCTest

@MainActor final class LanguageReferenceNavigationTests: XCTestCase {
    func testReferenceLanguagesSwitchInTheOrdinaryIPhoneSettings() {
        verifyLanguages(device: "iphone")
    }

    func testReferenceLanguagesSwitchInTheOrdinaryIPadSettings() {
        verifyLanguages(device: "ipad")
    }

    private func verifyLanguages(device: String) {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchArguments = ["-nativeGuide.initialized.v1", "YES", "-nativeGuide.completed.v1", "YES"]; app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.buttons["main-menu"].waitForExistence(timeout: 45))
        guard let initialName = app.buttons.matching(identifier: "main-account").firstMatch.value as? String, !initialName.isEmpty else {
            XCTFail("The active profile must expose its actual display name"); return
        }
        app.buttons["main-menu"].tap()
        let destination = app.buttons["nav-settings"]
        let navigation = app.descendants(matching: .any).matching(identifier: "navigation-scroll").firstMatch
        XCTAssertTrue(navigation.waitForExistence(timeout: 10))
        for _ in 0..<10 { if destination.isHittable { break }; navigation.swipeUp() }
        XCTAssertTrue(destination.isHittable); destination.tap()
        let cases = [("Français", "Paramètres", "fr"), ("日本語", "設定", "ja"), ("العربية", "الإعدادات", "ar"), ("Español", "Configuración", "es")]
        for (name, heading, code) in cases {
            let picker = app.buttons["settings-app-language"]
            XCTAssertTrue(picker.waitForExistence(timeout: 10)); picker.tap()
            let option = app.buttons[name].firstMatch
            for _ in 0..<4 {
                if option.exists && option.isHittable { break }
                if app.collectionViews.firstMatch.exists { app.collectionViews.firstMatch.swipeUp() }
                else { app.swipeUp() }
            }
            XCTAssertTrue(option.waitForExistence(timeout: 5)); XCTAssertTrue(option.isHittable); option.tap()
            XCTAssertTrue(app.staticTexts[heading].firstMatch.waitForExistence(timeout: 10))
            XCTAssertEqual(picker.value as? String, name)
            let account = app.buttons.matching(identifier: "main-account").firstMatch
            let samePersonalName = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", initialName), object: account)
            XCTAssertEqual(XCTWaiter.wait(for: [samePersonalName], timeout: 5), .completed)
            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.name = "reference-language-\(device)-\(code)"; attachment.lifetime = .keepAlways; add(attachment)
        }
    }
}

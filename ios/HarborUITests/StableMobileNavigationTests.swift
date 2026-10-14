import XCTest

@MainActor final class StableMobileNavigationTests: XCTestCase {
    func testContinueRemovalLanguagesAndReadingImportInNormalApp() throws {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launch()
        XCTAssertTrue(app.buttons["main-menu"].waitForExistence(timeout: 30))
        let remove = app.buttons["continue-watching-remove"].firstMatch
        XCTAssertTrue(remove.waitForExistence(timeout: 45), "Native preflight seeded the simulator's ordinary guest library")
        capture(app, "home-before-x-fixture")
        remove.tap()
        let removed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: remove)
        XCTAssertEqual(XCTWaiter.wait(for: [removed], timeout: 5), .completed)
        XCTAssertFalse(app.otherElements["player-surface"].exists)
        XCTAssertTrue(app.buttons["main-menu"].exists, "X must not navigate into playback")
        capture(app, "home-after-x-fixture")
        navigate(app, "settings")
        let headings = ["English": "Settings", "Русский": "Настройки", "العربية": "الإعدادات", "Português": "Configurações", "Español": "Ajustes"]
        for name in ["English", "Русский", "العربية", "Português", "Español", "English"] {
            let choice = app.descendants(matching: .any).matching(identifier: "settings-app-language").firstMatch
            XCTAssertTrue(choice.waitForExistence(timeout: 8)); choice.tap()
            let option = app.buttons[name].firstMatch
            XCTAssertTrue(option.waitForExistence(timeout: 5)); option.tap()
            XCTAssertTrue(app.staticTexts[headings[name]!].firstMatch.waitForExistence(timeout: 5))
            capture(app, "settings-language-\(name)")
        }
        XCTAssertTrue(app.staticTexts["Settings"].firstMatch.exists)
        navigate(app, "ebook")
        let importer = app.buttons["ebook-import"]
        XCTAssertTrue(importer.waitForExistence(timeout: 8))
        XCTAssertTrue(importer.label.contains("Import from Files"), "The native literal must follow the selected interface language")
        importer.tap()
        let cancel = app.buttons["Cancel"].firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 10), "The system picker must open on iPhone and iPad")
        capture(app, "ebook-system-file-picker"); cancel.tap()
        app.buttons["ebook-reading-help"].tap()
        XCTAssertTrue(app.staticTexts["Apple Books"].waitForExistence(timeout: 5))
        capture(app, "ebook-reading-help")
        if UIDeviceIsPad(app) {
            XCUIDevice.shared.orientation = .landscapeLeft
            capture(app, "ipad-reading-help-landscape")
            XCUIDevice.shared.orientation = .portrait
        }
        app.terminate()
    }
    private func UIDeviceIsPad(_ app: XCUIApplication) -> Bool { max(app.frame.width, app.frame.height) >= 1000 }
    private func navigate(_ app: XCUIApplication, _ name: String) {
        app.buttons["main-menu"].tap()
        let button = app.buttons["nav-\(name)"]
        let scroll = app.descendants(matching: .any).matching(identifier: "navigation-scroll").firstMatch
        XCTAssertTrue(scroll.waitForExistence(timeout: 5))
        for _ in 0..<8 { if button.isHittable { break }; scroll.swipeUp() }
        XCTAssertTrue(button.isHittable); button.tap()
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}

import XCTest
import UIKit

@MainActor final class StableMobileNavigationTests: XCTestCase {
    func testReadingHelpRemainsUsableAfterTabletRotation() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-uiLanguage", "en"]
        XCUIDevice.shared.orientation = .portrait
        app.launch()
        defer { XCUIDevice.shared.orientation = .portrait; app.terminate() }
        XCTAssertTrue(app.buttons["main-menu"].waitForExistence(timeout: 30))
        XCTAssertTrue(UIDeviceIsPad(app), "This case requires a tablet")
        navigate(app, "ebook")
        let help = app.buttons["ebook-reading-help"]
        XCTAssertTrue(help.waitForExistence(timeout: 15))
        let done = app.buttons["Done"].firstMatch
        for (orientation, landscape, name) in [
            (UIDeviceOrientation.portrait, false, "portrait-before"),
            (.landscapeLeft, true, "landscape-left"),
            (.landscapeRight, true, "landscape-right"),
            (.portrait, false, "portrait-after")
        ] {
            help.tap()
            XCTAssertTrue(done.waitForExistence(timeout: 10))
            XCUIDevice.shared.orientation = orientation
            let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                let frame = app.frame
                return (frame.width > frame.height) == landscape && done.isHittable && frame.contains(done.frame)
            }, object: app)
            let result = XCTWaiter.wait(for: [ready], timeout: 45)
            // Capture the complete display, avoiding a stale app-element crop after rotation.
            let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            attachment.name = "ipad-help-" + name
            attachment.lifetime = .keepAlways
            add(attachment)
            XCTAssertEqual(result, .completed, "Rotation must keep the sheet's close control inside the app and tappable")
            let section = app.staticTexts["Apple Books"].firstMatch
            XCTAssertTrue(section.isHittable)
            XCTAssertTrue(app.frame.contains(section.frame))
            let scroll = app.scrollViews.containing(.staticText, identifier: "Apple Books").firstMatch
            XCTAssertTrue(scroll.exists)
            let library = app.staticTexts["Your library"].firstMatch
            for _ in 0..<3 { if library.isHittable { break }; scroll.swipeUp() }
            XCTAssertTrue(library.isHittable, "The end of the help must remain reachable")
            XCTAssertTrue(done.isHittable)
            done.tap()
            let closed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isHittable == true"), object: help)
            XCTAssertEqual(XCTWaiter.wait(for: [closed], timeout: 45), .completed)
        }
        XCTAssertFalse(app.staticTexts["Apple Books"].exists)
        XCTAssertTrue(app.buttons["ebook-import"].isHittable)
        XCTAssertTrue(app.buttons["main-menu"].isHittable)
    }

    func testContinueRemovalLanguagesAndReadingImportInNormalApp() throws {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launch()
        XCTAssertTrue(app.buttons["main-menu"].waitForExistence(timeout: 30))
        let remove = app.buttons["continue-watching-remove"].firstMatch
        XCTAssertTrue(remove.waitForExistence(timeout: 45), "Native preflight seeded the simulator's ordinary guest library")
        capture(app, "home-before-x-fixture")
        remove.tap()
        let removed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: remove)
        // A tablet accessibility snapshot can outlive the visual removal.
        let removalResult = XCTWaiter.wait(for: [removed], timeout: 45)
        capture(app, "home-after-x-fixture")
        XCTAssertEqual(removalResult, .completed)
        XCTAssertFalse(app.otherElements["player-surface"].exists)
        XCTAssertTrue(app.buttons["main-menu"].exists, "X must not navigate into playback")
        navigate(app, "settings")
        let headings = ["English": "Settings", "Русский": "Настройки", "العربية": "الإعدادات", "Português": "Configurações", "Español": "Configuración"]
        for name in ["English", "Русский", "العربية", "Português", "Español", "English"] {
            let choice = app.buttons["settings-app-language"]
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
        // The first Documents view-service launch on a cold CI simulator can
        // take longer than the Harbor view. Wait for the real system control.
        let opened = cancel.waitForExistence(timeout: 60)
        capture(app, "ebook-system-file-picker")
        XCTAssertTrue(opened, "The system picker must open on iPhone and iPad")
        cancel.tap()
        let help = app.buttons["ebook-reading-help"]
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isHittable == true"), object: help)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 10), .completed)
        help.tap()
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

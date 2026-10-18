import XCTest

@MainActor final class ServiceCatalogNavigationTests: XCTestCase {
    func testServiceIndexFiltersAndMetadataSetupWorkInTheIPhoneInterface() { verifyServices(device: "iphone") }
    func testServiceIndexFiltersAndMetadataSetupWorkInTheIPadInterface() { verifyServices(device: "ipad") }

    private func verifyServices(device: String) {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-uiLanguage", "es", "-nativeGuide.initialized.v1", "YES", "-nativeGuide.completed.v1", "YES"]
        app.launch(); defer { app.terminate() }
        XCTAssertTrue(app.buttons["main-menu"].waitForExistence(timeout: 45)); app.buttons["main-menu"].tap()
        let menu = app.descendants(matching: .any).matching(identifier: "navigation-scroll").firstMatch
        let settings = app.buttons["nav-settings"]
        XCTAssertTrue(menu.waitForExistence(timeout: 10))
        for _ in 0..<10 { if settings.isHittable { break }; menu.swipeUp() }
        XCTAssertTrue(settings.isHittable); settings.tap()
        let search = app.textFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 10)); search.tap(); search.typeText("Streaming")
        let entry = app.buttons["settings-streaming"]
        XCTAssertTrue(entry.waitForExistence(timeout: 5)); entry.tap()
        let browse = app.buttons["streaming-browse-services"]
        for _ in 0..<10 { if browse.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(browse.isHittable); browse.tap()
        let index = app.scrollViews["services-index"]
        XCTAssertTrue(index.waitForExistence(timeout: 10))
        let prime = app.buttons["browse-service-prime"]
        XCTAssertTrue(prime.waitForExistence(timeout: 10))
        capture(app, name: "service-browser-\(device)-index")
        prime.tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "service-missing-key").firstMatch.waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["service-category-all"].isSelected)
        capture(app, name: "service-browser-\(device)-provider")
        let categories = app.scrollViews["service-categories"]
        let horror = app.buttons["service-category-horror"]
        tapVisibleFloatingControl(app.buttons["service-category-menu"], app: app)
        let horrorAction = app.buttons.matching(NSPredicate(format: "label == %@ AND identifier != %@", "Terror", "service-category-horror")).firstMatch
        XCTAssertTrue(horrorAction.waitForExistence(timeout: 5)); horrorAction.tap()
        let selected = expectation(for: NSPredicate(format: "isSelected == true"), evaluatedWith: horror)
        wait(for: [selected], timeout: 5)
        XCTAssertTrue(categories.frame.intersects(horror.frame))
        capture(app, name: "service-browser-\(device)-filter")
        tapVisibleFloatingControl(app.buttons["service-back-to-top"], app: app)
        let metadata = app.buttons["service-configure-metadata"]
        XCTAssertTrue(metadata.waitForExistence(timeout: 5)); metadata.tap()
        XCTAssertTrue(app.buttons["metadata-manage-key"].waitForExistence(timeout: 10))
    }
    private func tapVisibleFloatingControl(_ control: XCUIElement, app: XCUIApplication) {
        XCTAssertTrue(control.waitForExistence(timeout: 5)); XCTAssertTrue(control.isEnabled)
        let frame = control.frame
        XCTAssertGreaterThanOrEqual(frame.width, 44); XCTAssertGreaterThanOrEqual(frame.height, 44)
        XCTAssertTrue(app.frame.contains(frame))
        // XCTest returns an invalid AX hit point for these visible SwiftUI Menu
        // controls. A real touch at the observed frame must still open its menu;
        // the caller requires the actual option and selected state afterwards.
        control.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    }
    private func capture(_ app: XCUIApplication, name: String) {
        let image = XCTAttachment(screenshot: app.screenshot()); image.name = name; image.lifetime = .keepAlways; add(image)
    }
}

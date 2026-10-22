import XCTest

@MainActor final class HarborReadingBulkNavigationTests: XCTestCase {
    func testReadingBulkProgressPartialFailureAndConfirmedUninstallOnIPhone() { ReadingBulkUIRoute(owner: self).verify("iphone") }
    func testReadingBulkProgressPartialFailureAndConfirmedUninstallOnIPad() { ReadingBulkUIRoute(owner: self).verify("ipad") }
}

@MainActor struct ReadingBulkUIRoute {
    let owner: XCTestCase
    func verify(_ device: String) {
        owner.continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-uiLanguage", "es", "-nativeGuide.initialized.v1", "YES", "-nativeGuide.completed.v1", "YES"]
        app.launch(); defer { app.terminate() }
        let menu = app.buttons["main-menu"]; XCTAssertTrue(menu.waitForExistence(timeout: 45)); menu.tap()
        let navigation = app.descendants(matching: .any).matching(identifier: "navigation-scroll").firstMatch
        XCTAssertTrue(navigation.waitForExistence(timeout: 10))
        let settings = app.buttons["nav-settings"]
        for _ in 0..<12 { if settings.isHittable { break }; navigation.swipeUp() }
        XCTAssertTrue(settings.isHittable); settings.press(forDuration: 0.6)
        let search = app.textFields.firstMatch; XCTAssertTrue(search.waitForExistence(timeout: 15)); search.tap(); search.typeText("Plugins")
        let plugins = app.buttons["settings-plugins"]; XCTAssertTrue(plugins.waitForExistence(timeout: 10)); plugins.tap()
        let books = app.buttons["Libros"].firstMatch; XCTAssertTrue(books.waitForExistence(timeout: 15)); books.tap()
        let repositories = app.buttons["Repositorios"]; XCTAssertTrue(repositories.waitForExistence(timeout: 10)); repositories.tap()
        let repo = "ebook|http://127.0.0.1:18734/bulk/repo.json"
        let install = app.buttons["reading-plugin-install-all-" + repo]; XCTAssertTrue(install.waitForExistence(timeout: 15)); reveal(install, app)
        capture(app, "reading-bulk-before-" + device)
        install.tap()
        let progress = app.progressIndicators["reading-plugin-bulk-progress"].firstMatch
        let container = app.descendants(matching: .any).matching(identifier: "reading-plugin-bulk-progress").firstMatch
        XCTAssertTrue(container.waitForExistence(timeout: 20)); XCTAssertTrue(progress.exists || container.exists)
        capture(app, "reading-bulk-progress-" + device)
        let remove = app.buttons["reading-plugin-remove-all-" + repo]
        let completed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in remove.exists && remove.isEnabled && !container.exists }, object: app)
        XCTAssertEqual(XCTWaiter.wait(for: [completed], timeout: 90), .completed)
        reveal(remove, app)
        capture(app, "reading-bulk-partial-" + device)
        remove.tap()
        let confirm = app.buttons["reading-plugin-confirm-remove"]; XCTAssertTrue(confirm.waitForExistence(timeout: 10)); confirm.tap()
        let removed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: remove)
        XCTAssertEqual(XCTWaiter.wait(for: [removed], timeout: 20), .completed)
        XCTAssertTrue(app.staticTexts["Owned bulk repository"].exists)
        capture(app, "reading-bulk-uninstalled-" + device)
    }
    private func reveal(_ element: XCUIElement, _ app: XCUIApplication) {
        ReadingUIInteraction.reveal(element, in: app)
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; owner.add(attachment)
    }
}

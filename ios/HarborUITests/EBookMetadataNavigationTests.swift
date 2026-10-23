import XCTest

@MainActor struct EBookMetadataUIRoute {
    let owner: XCTestCase
    func verify(_ device: String) {
        owner.continueAfterFailure = false
        let app = XCUIApplication(); app.launchArguments = ["-uiLanguage", "es", "-nativeGuide.initialized.v1", "YES", "-nativeGuide.completed.v1", "YES"]
        app.launch(); defer { app.terminate() }
        navigate("ebook", app)
        let tabs = app.segmentedControls["ebook-screen"]; XCTAssertTrue(tabs.waitForExistence(timeout: 15)); reveal(tabs, app, up: false)
        tabs.buttons.element(boundBy: 1).tap()
        selectCategory("Fantasía", fallback: "Fantasy", app: app)
        let search = app.textFields["ebook-search"]; reveal(search, app, up: false); search.tap()
        if !app.keyboards.firstMatch.waitForExistence(timeout: 2) { search.tap() }; search.typeText("Owned\n")
        let discovered = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'ebook-discovery-card-' AND label CONTAINS 'Owned Book'")).firstMatch
        XCTAssertTrue(discovered.waitForExistence(timeout: 30))
        reveal(discovered, app); XCTAssertTrue(discovered.exists)
        capture(app, "ebook-metadata-search-" + device)
        discovered.tap()
        let title = app.staticTexts["ebook-detail-title"]; XCTAssertTrue(title.waitForExistence(timeout: 20))
        capture(app, "ebook-metadata-detail-" + device)
        let read = app.buttons["ebook-detail-read"]; XCTAssertTrue(read.waitForExistence(timeout: 30)); reveal(read, app, up: false); read.tap()
        let paragraph = app.staticTexts.matching(identifier: "ebook-reader-text").firstMatch
        XCTAssertTrue(paragraph.waitForExistence(timeout: 30)); XCTAssertEqual(paragraph.label, "Owned first chapter paragraph.")
        capture(app, "ebook-metadata-reader-" + device)
        navigate("ebook", app)
        let screen = app.segmentedControls["ebook-screen"]; XCTAssertTrue(screen.waitForExistence(timeout: 20)); reveal(screen, app, up: false); screen.buttons.element(boundBy: 1).tap()
        if search.value as? String == "Owned" {
            let clearSearch = app.buttons["Borrar búsqueda"].firstMatch
            reveal(clearSearch, app, up: false); XCTAssertTrue(clearSearch.isHittable); clearSearch.tap()
            XCTAssertNotEqual(search.value as? String, "Owned")
        }
        selectCategory("Todo", fallback: "All", app: app)
        let popular = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'ebook-discovery-card-'")).firstMatch
        reveal(popular, app); XCTAssertTrue(popular.exists)
        capture(app, "ebook-metadata-discover-" + device)
        let settings = app.buttons["ebook-metadata-settings"]; XCTAssertTrue(settings.waitForExistence(timeout: 10)); settings.tap()
        XCTAssertTrue(app.secureTextFields["ebook-google-key"].waitForExistence(timeout: 15))
        capture(app, "ebook-metadata-settings-" + device)
        let clear = app.buttons["ebook-metadata-clear-cache"]; reveal(clear, app); clear.tap()
        XCTAssertTrue(app.staticTexts["ebook-metadata-message"].waitForExistence(timeout: 15))
        capture(app, "ebook-metadata-cache-cleared-" + device)
    }
    private func selectCategory(_ title: String, fallback: String, app: XCUIApplication) {
        let category = app.buttons["ebook-discovery-category"]; XCTAssertTrue(category.waitForExistence(timeout: 20)); reveal(category, app, up: false); category.tap()
        let choice = app.buttons[title].firstMatch
        if choice.waitForExistence(timeout: 2) { choice.tap() } else { app.buttons[fallback].firstMatch.tap() }
    }
    private func navigate(_ section: String, _ app: XCUIApplication) {
        let menu = app.buttons["main-menu"]; XCTAssertTrue(menu.waitForExistence(timeout: 45)); menu.tap()
        let navigation = app.descendants(matching: .any).matching(identifier: "navigation-scroll").firstMatch; XCTAssertTrue(navigation.waitForExistence(timeout: 10))
        let target = app.buttons["nav-" + section]
        for _ in 0..<12 { if target.isHittable { break }; navigation.swipeDown() }
        for _ in 0..<12 { if target.isHittable { break }; navigation.swipeUp() }
        XCTAssertTrue(target.isHittable); target.press(forDuration: 0.6)
    }
    private func reveal(_ element: XCUIElement, _ app: XCUIApplication, up: Bool = true) {
        ReadingUIInteraction.reveal(element, in: app, up: up)
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; owner.add(attachment)
    }
}

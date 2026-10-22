import XCTest

@MainActor final class HarborReadingHTMLNavigationTests: XCTestCase {
    func testManualSourceEditorValidationAndActualMangaAndBookReadersOnIPhone() { verify("iphone") }
    func testManualSourceEditorValidationAndActualMangaAndBookReadersOnIPad() { verify("ipad") }
    private func verify(_ device: String) {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchArguments = ["-uiLanguage", "es", "-nativeGuide.initialized.v1", "YES", "-nativeGuide.completed.v1", "YES"]
        app.launch(); defer { app.terminate() }
        navigate("settings", app)
        let settingsSearch = app.textFields.firstMatch; XCTAssertTrue(settingsSearch.waitForExistence(timeout: 15)); settingsSearch.tap(); settingsSearch.typeText("Plugins")
        let plugins = app.buttons["settings-plugins"]; XCTAssertTrue(plugins.waitForExistence(timeout: 10)); plugins.tap()
        let mangaKind = app.buttons["Manga"].firstMatch; XCTAssertTrue(mangaKind.waitForExistence(timeout: 15)); mangaKind.tap()
        let edit = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'reading-html-edit-custom-html-'")).firstMatch
        XCTAssertTrue(edit.waitForExistence(timeout: 20)); reveal(edit, app); edit.tap()
        let name = app.textFields["reading-html-name"]; XCTAssertTrue(name.waitForExistence(timeout: 15)); replace(name, with: "Renamed manual Manga")
        XCTAssertTrue(app.textViews["reading-html-config"].exists)
        capture(app, "reading-html-editor-" + device)
        app.buttons["reading-html-save"].tap()
        let edited = app.staticTexts["Renamed manual Manga"]; XCTAssertTrue(edited.waitForExistence(timeout: 30))
        capture(app, "reading-html-saved-" + device)
        let add = app.buttons["reading-html-add"]; reveal(add, app, up: false); add.tap()
        let config = app.textViews["reading-html-config"]; XCTAssertTrue(config.waitForExistence(timeout: 15)); replace(config, with: "{}")
        app.buttons["reading-html-save"].tap()
        let invalid = app.staticTexts["reading-html-error"]; XCTAssertTrue(invalid.waitForExistence(timeout: 30)); reveal(invalid, app)
        capture(app, "reading-html-invalid-" + device)
        app.buttons["reading-html-cancel"].tap()
        navigate("manga", app)
        let manga = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'manga-card-custom-html-' AND label CONTAINS 'The Book'")).firstMatch
        XCTAssertTrue(manga.waitForExistence(timeout: 40)); reveal(manga, app); manga.tap()
        let readManga = app.buttons["manga-detail-read"]; XCTAssertTrue(readManga.waitForExistence(timeout: 25)); reveal(readManga, app); readManga.tap()
        XCTAssertTrue(app.images["manga-page-0"].firstMatch.waitForExistence(timeout: 30))
        capture(app, "reading-html-manga-reader-" + device)
        navigate("ebook", app)
        let book = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'ebook-card-source:html' AND label CONTAINS 'The Book'")).firstMatch
        XCTAssertTrue(book.waitForExistence(timeout: 40)); reveal(book, app)
        capture(app, "reading-html-book-catalog-" + device); book.tap()
        let readBook = app.buttons["ebook-detail-read"]; XCTAssertTrue(readBook.waitForExistence(timeout: 25)); readBook.tap()
        let paragraph = app.staticTexts.matching(NSPredicate(format: "identifier == 'ebook-reader-text' AND label == 'First paragraph.'")).firstMatch
        XCTAssertTrue(paragraph.waitForExistence(timeout: 30))
        capture(app, "reading-html-book-reader-" + device)
    }
    private func replace(_ field: XCUIElement, with value: String) {
        field.tap()
        if !XCUIApplication().keyboards.firstMatch.waitForExistence(timeout: 2) { field.tap() }
        let count = (field.value as? String)?.count ?? 0
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: count) + value)
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
        for _ in 0..<10 { if element.isHittable { return }; if up { app.swipeUp() } else { app.swipeDown() } }
        XCTAssertTrue(element.isHittable)
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}

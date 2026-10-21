import XCTest

@MainActor final class HarborReadingPluginNavigationTests: XCTestCase {
    func testOwnedReadingSourcesManagementSearchAndReadersOnIPhone() { verify("iphone") }
    func testOwnedReadingSourcesManagementSearchAndReadersOnIPad() { verify("ipad") }
    private func verify(_ device: String) {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-uiLanguage", "es", "-nativeGuide.initialized.v1", "YES", "-nativeGuide.completed.v1", "YES"]
        app.launch(); defer { app.terminate() }
        navigate("settings", app)
        let search = app.textFields.firstMatch; XCTAssertTrue(search.waitForExistence(timeout: 15)); search.tap(); search.typeText("Plugins")
        let plugins = app.buttons["settings-plugins"]; XCTAssertTrue(plugins.waitForExistence(timeout: 10)); plugins.tap()
        let mangaKind = app.buttons["Manga"].firstMatch; XCTAssertTrue(mangaKind.waitForExistence(timeout: 10)); mangaKind.tap()
        let toggle = app.switches["reading-plugin-enabled-owned.ui.reading.manga"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 20)); reveal(toggle, app)
        set(toggle, false); set(toggle, true)
        capture(app, "reading-plugin-manga-installed-" + device)
        app.buttons["Repositorios"].tap()
        let installed = app.buttons["reading-plugin-install-owned.ui.reading.manga"]
        XCTAssertTrue(installed.waitForExistence(timeout: 10)); reveal(installed, app); XCTAssertFalse(installed.isEnabled)
        capture(app, "reading-plugin-manga-repository-" + device)
        app.buttons["Libros"].firstMatch.tap()
        XCTAssertTrue(app.switches["reading-plugin-enabled-owned.ui.reading.books"].waitForExistence(timeout: 10))
        capture(app, "reading-plugin-books-installed-" + device)
        navigate("manga", app)
        let mangaSearch = app.textFields.firstMatch; XCTAssertTrue(mangaSearch.waitForExistence(timeout: 20)); reveal(mangaSearch, app); mangaSearch.tap(); mangaSearch.typeText("Owned\n")
        let card = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'manga-card-' AND label CONTAINS 'Owned Manga'")).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 30)); reveal(card, app)
        capture(app, "reading-plugin-manga-search-" + device); card.tap()
        let read = app.buttons["manga-detail-read"]; XCTAssertTrue(read.waitForExistence(timeout: 20)); reveal(read, app); read.tap()
        let page = app.images["manga-page-0"].firstMatch; XCTAssertTrue(page.waitForExistence(timeout: 30))
        capture(app, "reading-plugin-manga-reader-" + device)
        navigate("ebook", app)
        let provider = app.buttons["ebook-source"]; XCTAssertTrue(provider.waitForExistence(timeout: 20)); reveal(provider, app); provider.tap()
        let owned = app.buttons["Owned UI Books"].firstMatch; XCTAssertTrue(owned.waitForExistence(timeout: 10)); owned.tap()
        let bookSearch = app.textFields["ebook-search"]; XCTAssertTrue(bookSearch.waitForExistence(timeout: 10)); bookSearch.tap(); bookSearch.typeText("Owned\n")
        let book = app.buttons["ebook-card-source:plugin%3Aowned.ui.reading.books:owned"]
        XCTAssertTrue(book.waitForExistence(timeout: 30)); reveal(book, app)
        capture(app, "reading-plugin-book-search-" + device); book.tap()
        let readBook = app.buttons["ebook-detail-read"]
        XCTAssertTrue(readBook.waitForExistence(timeout: 15)); readBook.tap()
        let paragraph = app.staticTexts.matching(identifier: "ebook-reader-text").firstMatch
        XCTAssertTrue(paragraph.waitForExistence(timeout: 30)); XCTAssertTrue(paragraph.label.contains("Owned first chapter paragraph."))
        capture(app, "reading-plugin-book-reader-" + device)
        let next = app.buttons["ebook-next-section"]; XCTAssertTrue(next.waitForExistence(timeout: 10)); next.tap()
        let updated = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "Owned second chapter paragraph."), object: paragraph)
        XCTAssertEqual(XCTWaiter.wait(for: [updated], timeout: 20), .completed)
        capture(app, "reading-plugin-book-next-" + device)
    }
    private func set(_ toggle: XCUIElement, _ enabled: Bool) {
        let value = enabled ? "1" : "0"
        if toggle.value as? String != value { toggle.coordinate(withNormalizedOffset: .init(dx: 1, dy: 0.5)).withOffset(.init(dx: -20, dy: 0)).tap() }
        let changed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", value), object: toggle)
        XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 5), .completed)
    }
    private func navigate(_ section: String, _ app: XCUIApplication) {
        let menu = app.buttons["main-menu"]; XCTAssertTrue(menu.waitForExistence(timeout: 45)); menu.tap()
        let navigation = app.descendants(matching: .any).matching(identifier: "navigation-scroll").firstMatch
        XCTAssertTrue(navigation.waitForExistence(timeout: 10))
        let target = app.buttons["nav-" + section]
        for _ in 0..<12 { if target.isHittable { break }; navigation.swipeDown() }
        for _ in 0..<12 { if target.isHittable { break }; navigation.swipeUp() }
        XCTAssertTrue(target.isHittable); target.press(forDuration: 0.6)
    }
    private func reveal(_ element: XCUIElement, _ app: XCUIApplication) {
        for _ in 0..<8 { if element.isHittable { return }; app.swipeUp() }
        XCTAssertTrue(element.isHittable)
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}

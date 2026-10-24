import XCTest

@MainActor final class EBookCatalogNavigationTests: XCTestCase {
    func testCombinedBooksFiltersSourceSelectionAndDetailReaderOnIPhone() { EBookCatalogUIRoute(owner: self).verify("iphone") }
    func testCombinedBooksFiltersSourceSelectionAndDetailReaderOnIPad() { EBookCatalogUIRoute(owner: self).verify("ipad") }
}

@MainActor struct EBookCatalogUIRoute {
    let owner: XCTestCase
    func verify(_ device: String) {
        owner.continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-uiLanguage", "es", "-nativeGuide.initialized.v1", "YES", "-nativeGuide.completed.v1", "YES"]
        app.launch(); defer { app.terminate() }
        navigate("ebook", app)
        let search = app.textFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 20)); search.tap(); search.typeText("Owned\n")
        let card = app.buttons["ebook-card-source:plugin%3Aowned.ui.reading.books:owned"]
        XCTAssertTrue(card.waitForExistence(timeout: 30))
        let scroll = app.scrollViews["ebook-catalog-scroll"], deadline = Date(timeIntervalSinceNow: 30)
        var grouped = false
        repeat {
            // Independent provider results can move this lazy grid cell while loading.
            ReadingUIInteraction.reveal(card, in: app, container: scroll)
            if card.label.contains("2") { grouped = true; break }
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.5))
        } while Date() < deadline
        if !grouped {
            let details = XCTAttachment(string: app.debugDescription); details.name = "ebook-catalog-grouping-hierarchy"; details.lifetime = .keepAlways; owner.add(details)
        }
        XCTAssertTrue(grouped, "The visible result must still expose both grouped readable sources")
        capture(app, "ebook-catalog-grouped-" + device)
        ReadingUIInteraction.tapVisible(card, in: app)
        let alternative = app.buttons["ebook-detail-source-source:plugin%3Aowned.ui.reading.alternate:owned"]
        XCTAssertTrue(alternative.waitForExistence(timeout: 20)); reveal(alternative, app)
        capture(app, "ebook-catalog-detail-" + device)
        alternative.tap()
        let switched = XCTNSPredicateExpectation(predicate: NSPredicate(format: "selected == true"), object: alternative)
        XCTAssertEqual(XCTWaiter.wait(for: [switched], timeout: 20), .completed)
        let read = app.buttons["ebook-detail-read"]; reveal(read, app, up: false); read.tap()
        let paragraph = app.staticTexts.matching(NSPredicate(format: "identifier == 'ebook-reader-text' AND label == 'Owned first chapter paragraph.'")).firstMatch
        ReadingUIInteraction.reveal(paragraph, in: app, container: app.scrollViews["ebook-reader-scroll"])
        XCTAssertTrue(paragraph.waitForExistence(timeout: 30)); XCTAssertEqual(paragraph.label, "Owned first chapter paragraph.")
        capture(app, "ebook-catalog-alternate-reader-" + device)
        navigate("ebook", app)
        let source = app.buttons["ebook-source"]; XCTAssertTrue(source.waitForExistence(timeout: 20)); reveal(source, app, up: false); source.tap()
        let owned = app.buttons["Owned UI Books"].firstMatch; XCTAssertTrue(owned.waitForExistence(timeout: 10)); owned.tap()
        let status = app.buttons["ebook-filter-status"]; XCTAssertTrue(status.waitForExistence(timeout: 10)); status.tap()
        let ongoing = app.buttons["En curso"].firstMatch
        let fallback = app.buttons["Ongoing"].firstMatch
        if ongoing.waitForExistence(timeout: 3) { ongoing.tap() } else { XCTAssertTrue(fallback.waitForExistence(timeout: 5)); fallback.tap() }
        app.buttons["ebook-filter-apply"].tap()
        XCTAssertTrue(card.waitForExistence(timeout: 30)); reveal(card, app)
        capture(app, "ebook-catalog-filters-" + device)
        reveal(app.buttons["ebook-filter-reset"], app, up: false); app.buttons["ebook-filter-reset"].tap()
        XCTAssertTrue(card.waitForExistence(timeout: 30))
        navigate("manga", app)
        let tags = app.buttons["manga-tag-filter"]; XCTAssertTrue(tags.waitForExistence(timeout: 30)); reveal(tags, app); tags.tap()
        let tag = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Owned tag'")).firstMatch
        XCTAssertTrue(tag.waitForExistence(timeout: 10)); tag.tap()
        let manga = app.buttons["manga-card-owned.ui.reading.manga::tagged"]
        XCTAssertTrue(manga.waitForExistence(timeout: 30)); reveal(manga, app)
        capture(app, "ebook-catalog-manga-tag-" + device)
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
    private func reveal(_ element: XCUIElement, _ app: XCUIApplication, up: Bool = true) {
        ReadingUIInteraction.reveal(element, in: app, up: up)
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; owner.add(attachment)
    }
}

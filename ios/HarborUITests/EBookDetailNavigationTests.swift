import XCTest

@MainActor final class EBookDetailNavigationTests: XCTestCase {
    func testOriginalBookVolumesSearchChapterReadingAndIndependentListsOnIPhone() { verify("iphone") }
    func testOriginalBookVolumesSearchChapterReadingAndIndependentListsOnIPad() { verify("ipad") }
    private func verify(_ device: String) {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchArguments = ["-uiLanguage", "en", "-nativeGuide.initialized.v1", "YES", "-nativeGuide.completed.v1", "YES"]
        app.launch(); defer { app.terminate() }
        openBooks(app)
        let card = app.buttons["ebook-card-source:plugin%3Achapters:owned"]
        XCTAssertTrue(card.waitForExistence(timeout: 45)); reveal(card, app); card.tap()
        let volume = app.buttons["ebook-volume-۲"]
        XCTAssertTrue(volume.waitForExistence(timeout: 30)); reveal(volume, app)
        capture(app, "ebook-detail-volumes-" + device)
        volume.tap()
        let view = app.segmentedControls["ebook-chapter-view"]; XCTAssertTrue(view.waitForExistence(timeout: 15)); reveal(view, app); view.buttons.element(boundBy: 0).tap()
        let second = app.buttons["ebook-chapter-original:2"], third = app.buttons["ebook-chapter-original:3"]
        XCTAssertTrue(second.waitForExistence(timeout: 15)); reveal(second, app); reveal(third, app)
        XCTAssertLessThan(second.frame.minY, third.frame.minY)
        capture(app, "ebook-detail-chapters-" + device)
        let search = app.textFields["ebook-chapter-search"]; reveal(search, app, up: false)
        search.tap(); if !app.keyboards.firstMatch.waitForExistence(timeout: 2) { search.tap() }; search.typeText("Third\n")
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: second)], timeout: 15), .completed)
        XCTAssertTrue(third.waitForExistence(timeout: 15)); reveal(third, app)
        capture(app, "ebook-detail-chapter-search-" + device)
        third.tap()
        let paragraph = app.staticTexts.matching(identifier: "ebook-reader-text").firstMatch
        XCTAssertTrue(paragraph.waitForExistence(timeout: 30)); XCTAssertEqual(paragraph.label, "Actual original:3 paragraph.")
        capture(app, "ebook-detail-reader-" + device)
        back(app)
        let bookmark = app.buttons["ebook-detail-save"], favorite = app.buttons["ebook-detail-list-favorites"], later = app.buttons["ebook-detail-list-readLater"]
        reveal(bookmark, app, up: false); bookmark.tap(); favorite.tap(); later.tap()
        capture(app, "ebook-detail-lists-" + device)
        back(app)
        let tabs = app.segmentedControls["ebook-screen"]; XCTAssertTrue(tabs.waitForExistence(timeout: 15)); reveal(tabs, app, up: false); tabs.buttons.element(boundBy: 2).tap()
        filter("Favorites", app); XCTAssertTrue(card.waitForExistence(timeout: 15)); reveal(card, app)
        capture(app, "ebook-detail-favorites-" + device)
        filter("Read later", app); XCTAssertTrue(card.waitForExistence(timeout: 15)); reveal(card, app)
        capture(app, "ebook-detail-read-later-" + device)
        card.tap(); reveal(bookmark, app, up: false); bookmark.tap(); back(app)
        filter("Bookmarked", app)
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: card)], timeout: 15), .completed)
        capture(app, "ebook-detail-bookmarks-removed-" + device)
        filter("Favorites", app); XCTAssertTrue(card.waitForExistence(timeout: 15)); reveal(card, app); card.tap()
        let read = app.buttons["ebook-detail-read"]; XCTAssertTrue(read.waitForExistence(timeout: 15)); reveal(read, app, up: false); read.tap()
        XCTAssertTrue(paragraph.waitForExistence(timeout: 30)); XCTAssertEqual(paragraph.label, "Actual original:3 paragraph.")
    }
    private func filter(_ title: String, _ app: XCUIApplication) {
        let picker = app.buttons["ebook-shelf-filter"]; XCTAssertTrue(picker.waitForExistence(timeout: 10)); reveal(picker, app, up: false); picker.tap()
        let item = app.buttons[title].firstMatch; XCTAssertTrue(item.waitForExistence(timeout: 10)); item.tap()
    }
    private func back(_ app: XCUIApplication) { app.navigationBars.buttons.element(boundBy: 0).tap() }
    private func openBooks(_ app: XCUIApplication) {
        let menu = app.buttons["main-menu"]; XCTAssertTrue(menu.waitForExistence(timeout: 45)); menu.tap()
        let navigation = app.descendants(matching: .any).matching(identifier: "navigation-scroll").firstMatch
        XCTAssertTrue(navigation.waitForExistence(timeout: 10)); let target = app.buttons["nav-ebook"]
        for _ in 0..<12 { if target.isHittable { break }; navigation.swipeDown() }
        for _ in 0..<12 { if target.isHittable { break }; navigation.swipeUp() }
        XCTAssertTrue(target.isHittable); target.press(forDuration: 0.6)
    }
    private func reveal(_ element: XCUIElement, _ app: XCUIApplication, up: Bool = true) {
        ReadingUIInteraction.reveal(element, in: app, up: up)
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}

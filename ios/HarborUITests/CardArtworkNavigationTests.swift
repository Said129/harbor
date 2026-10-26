import XCTest

@MainActor final class CardArtworkNavigationTests: XCTestCase {
    func testPinnedArtworkAndOriginalImageLanguageChipsReorderRemoveAndPersistOnIPhone() { verify("iphone") }
    func testPinnedArtworkAndOriginalImageLanguageChipsReorderRemoveAndPersistOnIPad() { verify("ipad") }
    private func verify(_ device: String) {
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "site.harbor.iphone")
        app.launchArguments = ["-uiLanguage", "en", "-homeMode", "classic", "-nativeGuide.initialized.v1", "YES", "-nativeGuide.completed.v1", "YES"]
        ReadingUIInteraction.launchPreparedApplication(app)
        defer { if (testRun?.failureCount ?? 0) > 0 { ReadingUIInteraction.recordFailureContext(app) }; app.terminate() }
        let home = app.scrollViews["home-scroll"]; XCTAssertTrue(home.waitForExistence(timeout: 45))
        let folder = element("source-folder-owned-posters-0", app)
        ReadingUIInteraction.reveal(folder, in: app, container: home); ReadingUIInteraction.tapVisible(folder, in: app)
        let card = app.buttons["catalog-browser-media"].firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 30)); XCTAssertEqual(card.label, "Owned catalog title 1")
        XCTAssertGreaterThan(card.frame.width, card.frame.height * 1.5)
        capture(app, "card-artwork-pinned-catalog-" + device)
        app.terminate(); ReadingUIInteraction.launchPreparedApplication(app); openMetadata(app)
        let picker = element("metadata-image-languages", app)
        show(picker, app); XCTAssertEqual(picker.value as? String, "en,original")
        capture(app, "card-image-languages-" + device)
        ReadingUIInteraction.tapVisible(app.buttons["metadata-image-languages-toggle"], in: app)
        let chooser = element("metadata-image-languages-chooser", app)
        XCTAssertTrue(chooser.waitForExistence(timeout: 10))
        let search = app.textFields["metadata-image-languages-search"]
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        ReadingUIInteraction.tapVisible(search, in: app); search.typeText("Spanish")
        let spanish = app.buttons["metadata-image-languages-add-es"]
        ReadingUIInteraction.reveal(spanish, in: app, container: app.scrollViews["metadata-image-languages-options"])
        capture(app, "card-image-search-" + device)
        ReadingUIInteraction.tapVisible(spanish, in: app)
        let added = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "en,original,es"), object: chooser)
        if XCTWaiter.wait(for: [added], timeout: 10) != .completed { ReadingUIInteraction.recordFailureContext(app); XCTFail("Selecting Spanish must update the live image-language preference"); return }
        ReadingUIInteraction.tapVisible(app.buttons["metadata-image-languages-done"], in: app)
        show(picker, app); XCTAssertEqual(picker.value as? String, "en,original,es")
        capture(app, "card-image-added-" + device)
        let earlier = app.buttons["metadata-image-languages-earlier-es"]
        for _ in 0..<2 { show(earlier, app); ReadingUIInteraction.tapVisible(earlier, in: app) }
        XCTAssertEqual(picker.value as? String, "es,en,original")
        capture(app, "card-image-order-" + device)
        let remove = app.buttons["metadata-image-languages-remove-original"]; show(remove, app); ReadingUIInteraction.tapVisible(remove, in: app)
        XCTAssertEqual(picker.value as? String, "es,en")
        app.terminate(); ReadingUIInteraction.launchPreparedApplication(app); openMetadata(app)
        show(picker, app); XCTAssertEqual(picker.value as? String, "es,en")
        capture(app, "card-image-restored-" + device)
    }
    private func openMetadata(_ app: XCUIApplication) {
        let menu = app.buttons["main-menu"]; XCTAssertTrue(menu.waitForExistence(timeout: 45)); ReadingUIInteraction.tapVisible(menu, in: app)
        let navigation = element("navigation-scroll", app); XCTAssertTrue(navigation.waitForExistence(timeout: 10))
        let settings = app.buttons["nav-settings"]
        ReadingUIInteraction.reveal(settings, in: app, container: navigation); ReadingUIInteraction.tapVisible(settings, in: app)
        let scroll = app.scrollViews["settings-scroll"]; XCTAssertTrue(scroll.waitForExistence(timeout: 15))
        let metadata = app.buttons["settings-metadata"]
        ReadingUIInteraction.reveal(metadata, in: app, container: scroll); ReadingUIInteraction.tapVisible(metadata, in: app)
        XCTAssertTrue(app.scrollViews["metadata-settings-scroll"].waitForExistence(timeout: 15))
    }
    private func element(_ identifier: String, _ app: XCUIApplication) -> XCUIElement { app.descendants(matching: .any).matching(identifier: identifier).firstMatch }
    private func show(_ control: XCUIElement, _ app: XCUIApplication, up: Bool = true) {
        let scroll = app.scrollViews["metadata-settings-scroll"]
        ReadingUIInteraction.reveal(control, in: app, up: up, container: scroll); ReadingUIInteraction.revealWithinViewport(control, in: app, container: scroll)
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}

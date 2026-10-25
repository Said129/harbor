import XCTest

@MainActor final class CustomSourceNavigationTests: XCTestCase {
    func testDesktopFoldersImportOpenExplainRequirementsEditHideRestoreAndDeleteOnIPhone() { verify("iphone") }
    func testDesktopFoldersImportOpenExplainRequirementsEditHideRestoreAndDeleteOnIPad() { verify("ipad") }
    private func verify(_ device: String) {
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "site.harbor.iphone")
        app.launchArguments = ["-uiLanguage", "en", "-homeMode", "classic", "-nativeGuide.initialized.v1", "YES", "-nativeGuide.completed.v1", "YES"]
        ReadingUIInteraction.launchPreparedApplication(app)
        defer { if (testRun?.failureCount ?? 0) > 0 { ReadingUIInteraction.recordFailureContext(app) }; app.terminate() }
        let scroll = app.scrollViews["home-scroll"], customize = app.buttons["page-customize"]
        XCTAssertTrue(scroll.waitForExistence(timeout: 45)); show(customize, app, scroll)
        ReadingUIInteraction.tapVisible(customize, in: app)
        let add = app.buttons["custom-source-add"]; show(add, app, scroll); ReadingUIInteraction.tapVisible(add, in: app)
        let url = app.textFields["source-import-url"]; XCTAssertTrue(url.waitForExistence(timeout: 15))
        capture(app, "source-import-dialog-" + device)
        for (index, entry) in [("missing-sources.json", "Failed to fetch JSON", "fetch-error"), ("malformed.json", "Invalid SourceRow JSON format", "format-error")].enumerated() {
            let (path, message, state) = entry
            if index == 0 { enterEmpty(url, "http://127.0.0.1:18734/" + path, app) }
            else { ReadingUIInteraction.replace(url, with: "http://127.0.0.1:18734/" + path, in: app) }
            ReadingUIInteraction.tapVisible(app.buttons["source-import-save"], in: app)
            let failure = app.staticTexts["source-import-error"]
            XCTAssertTrue(failure.waitForExistence(timeout: 15))
            let shown = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", message), object: failure)
            XCTAssertEqual(XCTWaiter.wait(for: [shown], timeout: 15), .completed)
            capture(app, "source-" + state + "-" + device)
        }
        ReadingUIInteraction.replace(url, with: "http://127.0.0.1:18734/sources.json", in: app)
        ReadingUIInteraction.tapVisible(app.buttons["source-import-save"], in: app)
        let row = element("source-row-owned-imported-sources", app), folder = element("source-folder-owned-imported-sources-0", app)
        show(row, app, scroll); XCTAssertTrue(row.exists); capture(app, "source-imported-" + device)
        ReadingUIInteraction.tapVisible(folder, in: app)
        let title = app.buttons["catalog-browser-media"].firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 30)); XCTAssertEqual(title.label, "Owned catalog title 1")
        let fifth = app.buttons.matching(identifier: "catalog-browser-media").matching(NSPredicate(format: "label == %@", "Owned catalog title 5")).firstMatch
        show(fifth, app, app.scrollViews["catalog-browser-scroll"])
        capture(app, "source-catalog-" + device)
        ReadingUIInteraction.tapVisible(app.navigationBars.buttons.firstMatch, in: app)
        show(row, app, scroll)
        let folders = app.scrollViews["source-folders-owned-imported-sources"]
        for (index, heading, state) in [(1, "Missing TMDB Key", "missing-key"), (2, "Addon not installed", "missing-addon")] {
            let target = element("source-folder-owned-imported-sources-\(index)", app)
            revealHorizontal(target, app, folders)
            ReadingUIInteraction.tapVisible(target, in: app)
            XCTAssertTrue(app.staticTexts[heading].waitForExistence(timeout: 15))
            capture(app, "source-" + state + "-" + device)
            ReadingUIInteraction.tapVisible(app.buttons["source-requirement-dismiss"], in: app)
            XCTAssertTrue(row.waitForExistence(timeout: 10), "Closing a requirement returns to the original home row")
        }
        revealHorizontal(folder, app, folders, left: false)
        show(customize, app, scroll, up: false)
        if !app.buttons["custom-source-add"].exists { ReadingUIInteraction.tapVisible(customize, in: app) }
        show(app.buttons["source-images-owned-imported-sources-0"], app, scroll)
        ReadingUIInteraction.tapVisible(app.buttons["source-images-owned-imported-sources-0"], in: app)
        let cover = app.textFields["source-cover-url"], focus = app.textFields["source-focus-url"]
        XCTAssertTrue(cover.waitForExistence(timeout: 15))
        capture(app, "source-image-editor-" + device)
        ReadingUIInteraction.replace(cover, with: "http://127.0.0.1:18734/edited.png", in: app)
        enterEmpty(focus, "http://127.0.0.1:18734/focus.gif", app)
        ReadingUIInteraction.tapVisible(app.buttons["source-images-save"], in: app)
        show(row, app, scroll); capture(app, "source-images-edited-" + device)
        let controls = element("page-row-controls-source-owned-imported-sources", app)
        show(controls, app, scroll)
        XCTAssertTrue(controls.buttons["Move up"].isEnabled)
        ReadingUIInteraction.tapVisible(controls.buttons["Move up"], in: app)
        show(controls, app, scroll)
        ReadingUIInteraction.tapVisible(controls.buttons["Rename row"], in: app)
        let name = app.textFields["page-row-name-source-owned-imported-sources"]
        ReadingUIInteraction.replace(name, with: "Owned renamed folders", in: app); name.typeText("\n")
        show(controls, app, scroll); ReadingUIInteraction.tapVisible(controls.buttons["Hide row"], in: app)
        let hidden = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in !row.exists }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [hidden], timeout: 10), .completed); capture(app, "source-hidden-" + device)
        show(controls, app, scroll)
        ReadingUIInteraction.tapVisible(controls.buttons["Show row"], in: app)
        ReadingUIInteraction.tapVisible(app.buttons["page-customize-done"], in: app)
        app.terminate(); ReadingUIInteraction.launchPreparedApplication(app)
        show(row, app, scroll); XCTAssertTrue(row.staticTexts["Owned renamed folders"].exists)
        capture(app, "source-restored-" + device)
        show(customize, app, scroll, up: false); ReadingUIInteraction.tapVisible(customize, in: app)
        show(app.buttons["source-delete-owned-imported-sources"], app, scroll)
        ReadingUIInteraction.tapVisible(app.buttons["source-delete-owned-imported-sources"], in: app)
        let removed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in !row.exists }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [removed], timeout: 10), .completed)
        show(element("source-row-owned-posters", app), app, scroll, up: false)
        capture(app, "source-deleted-" + device)
    }
    private func element(_ id: String, _ app: XCUIApplication) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }
    private func enterEmpty(_ field: XCUIElement, _ value: String, _ app: XCUIApplication) {
        // The fresh import URL and the fixture's null GIF have no selected text.
        // Type normally; Select All cannot exist in an empty field.
        ReadingUIInteraction.tapVisible(field, in: app); field.typeText(value)
        XCTAssertEqual(field.value as? String, value)
    }
    private func revealHorizontal(_ target: XCUIElement, _ app: XCUIApplication, _ container: XCUIElement, left: Bool = true) {
        for _ in 0..<6 {
            if ReadingUIInteraction.visibleFrame(target, in: app) != nil { break }
            if left { container.swipeLeft() } else { container.swipeRight() }
        }
        XCTAssertTrue(target.waitForExistence(timeout: 10)); XCTAssertNotNil(ReadingUIInteraction.visibleFrame(target, in: app))
    }
    private func show(_ element: XCUIElement, _ app: XCUIApplication, _ scroll: XCUIElement, up: Bool = true) {
        if !element.exists { ReadingUIInteraction.reveal(element, in: app, up: up, container: scroll) }
        XCTAssertTrue(element.waitForExistence(timeout: 15)); ReadingUIInteraction.revealWithinViewport(element, in: app, container: scroll)
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}

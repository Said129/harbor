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
            else { replaceURL(url, "source-import-url", "http://127.0.0.1:18734/" + path, app) }
            ReadingUIInteraction.tapVisible(app.buttons["source-import-save"], in: app)
            let failure = app.staticTexts["source-import-error"]
            XCTAssertTrue(failure.waitForExistence(timeout: 15))
            let shown = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", message), object: failure)
            XCTAssertEqual(XCTWaiter.wait(for: [shown], timeout: 15), .completed)
            capture(app, "source-" + state + "-" + device)
        }
        replaceURL(url, "source-import-url", "http://127.0.0.1:18734/sources.json", app)
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
            let dismiss = app.buttons["source-requirement-dismiss"]
            if !dismiss.waitForExistence(timeout: 10) { ReadingUIInteraction.recordFailureContext(app); XCTFail("The visible requirement must expose its OK action"); return }
            ReadingUIInteraction.tapVisible(dismiss, in: app)
            XCTAssertTrue(row.waitForExistence(timeout: 10), "Closing a requirement returns to the original home row")
        }
        revealHorizontal(folder, app, folders, left: false)
        show(customize, app, scroll, up: false)
        if !app.buttons["custom-source-add"].exists { ReadingUIInteraction.tapVisible(customize, in: app) }
        show(row, app, scroll)
        let editImages = app.buttons["source-images-owned-imported-sources-0"]
        revealHorizontal(editImages, app, folders, left: false)
        show(editImages, app, scroll)
        ReadingUIInteraction.tapVisible(editImages, in: app)
        let cover = app.textFields["source-cover-url"], focus = app.textFields["source-focus-url"]
        XCTAssertTrue(cover.waitForExistence(timeout: 15))
        capture(app, "source-image-editor-" + device)
        replaceURL(cover, "source-cover-url", "http://127.0.0.1:18734/edited.png", app)
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
    private func replaceURL(_ field: XCUIElement, _ identifier: String, _ value: String, _ app: XCUIApplication) {
        let clear = app.buttons[identifier + "-clear"]
        XCTAssertTrue(clear.waitForExistence(timeout: 10)); ReadingUIInteraction.tapVisible(clear, in: app)
        enterEmpty(field, value, app)
    }
    private func revealHorizontal(_ target: XCUIElement, _ app: XCUIApplication, _ container: XCUIElement, left: Bool = true) {
        for _ in 0..<12 {
            let bounds = container.frame, viewport = bounds.intersection(app.windows.firstMatch.frame)
            // The stroked folder's AX frame extends half a point beyond its
            // 180pt scroll viewport. Accept that border, never an offscreen tile.
            if let frame = ReadingUIInteraction.visibleFrame(target, in: app), viewport.insetBy(dx: -1, dy: -1).contains(frame) {
                let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isHittable == true"), object: target)
                if XCTWaiter.wait(for: [ready], timeout: 3) == .completed { return }
                ReadingUIInteraction.recordFailureContext(app); XCTFail("The fully visible folder control must accept a tap"); return
            }
            guard !viewport.isNull, viewport.width > 80, viewport.height > 40 else {
                ReadingUIInteraction.recordFailureContext(app); XCTFail("The folder row must have a visible viewport before a horizontal gesture"); return
            }
            let moveLeft = target.exists ? target.frame.maxX > viewport.maxX : left
            let needed = target.exists ? (moveLeft ? target.frame.maxX - viewport.maxX + 12 : viewport.minX - target.frame.minX + 12) : viewport.width / 2
            let distance = min(viewport.width * 0.6, max(20, needed))
            let origin = container.coordinate(withNormalizedOffset: .zero)
            let startX = viewport.minX - bounds.minX + viewport.width * (moveLeft ? 0.8 : 0.2)
            let start = origin.withOffset(.init(dx: startX, dy: viewport.midY - bounds.minY))
            let end = origin.withOffset(.init(dx: startX + (moveLeft ? -distance : distance), dy: viewport.midY - bounds.minY))
            start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.2)
        }
        if ReadingUIInteraction.visibleFrame(target, in: app) == nil { ReadingUIInteraction.recordFailureContext(app) }
        XCTAssertTrue(target.waitForExistence(timeout: 10)); XCTAssertNotNil(ReadingUIInteraction.visibleFrame(target, in: app)); XCTAssertTrue(target.isHittable)
    }
    private func show(_ element: XCUIElement, _ app: XCUIApplication, _ scroll: XCUIElement, up: Bool = true) {
        if element.identifier.hasPrefix("source-row-") {
            // This AX group has no action of its own. Reveal its actual bounds
            // and a tappable child, rather than requiring the group to be a button.
            for _ in 0..<20 {
                let bounds = scroll.frame, viewport = bounds.intersection(app.windows.firstMatch.frame)
                if let frame = ReadingUIInteraction.visibleFrame(element, in: app), viewport.insetBy(dx: -1, dy: -1).contains(frame),
                   element.buttons.allElementsBoundByIndex.contains(where: { ReadingUIInteraction.visibleFrame($0, in: app) != nil && $0.isHittable }) { return }
                guard viewport.width > 80, viewport.height > 80 else { break }
                let above = element.exists ? element.frame.minY < viewport.minY : !up
                let origin = scroll.coordinate(withNormalizedOffset: .zero)
                let start = origin.withOffset(.init(dx: viewport.minX - bounds.minX + 8, dy: viewport.minY - bounds.minY + viewport.height * (above ? 0.2 : 0.8)))
                let end = origin.withOffset(.init(dx: viewport.minX - bounds.minX + 8, dy: viewport.minY - bounds.minY + viewport.height * (above ? 0.8 : 0.2)))
                start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.2)
            }
            ReadingUIInteraction.recordFailureContext(app); XCTFail("The source row and one actionable folder must be visible"); return
        }
        if !element.exists { ReadingUIInteraction.reveal(element, in: app, up: up, container: scroll) }
        XCTAssertTrue(element.waitForExistence(timeout: 15)); ReadingUIInteraction.revealWithinViewport(element, in: app, container: scroll)
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}

import XCTest

@MainActor enum ReadingUIInteraction {
    static func chooseBookScreen(_ index: Int, in app: XCUIApplication) {
        let tabs = app.segmentedControls["ebook-screen"]
        XCTAssertTrue(tabs.waitForExistence(timeout: 15))
        let scroll = app.scrollViews["ebook-catalog-scroll"]
        reveal(tabs, in: app, up: false, container: scroll)
        let target = tabs.buttons.element(boundBy: index)
        XCTAssertTrue(target.waitForExistence(timeout: 10)); tapVisible(target, in: app)
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "selected == true"), object: target)], timeout: 15), .completed)
    }

    static func chooseBookSource(_ name: String, in app: XCUIApplication) {
        let picker = app.buttons["ebook-source"]
        XCTAssertTrue(picker.waitForExistence(timeout: 20)); reveal(picker, in: app, up: false); tapVisible(picker, in: app)
        let source = app.buttons[name].firstMatch
        XCTAssertTrue(source.waitForExistence(timeout: 10)); tapVisible(source, in: app)
    }

    static func assertReaderViewport(_ app: XCUIApplication) {
        let scroll = app.scrollViews["ebook-reader-scroll"]
        XCTAssertTrue(scroll.waitForExistence(timeout: 30))
        let laidOut = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            guard let frame = visibleFrame(scroll, in: app) else { return false }
            return frame.width > 100 && frame.height > 100
        }, object: scroll)
        if XCTWaiter.wait(for: [laidOut], timeout: 20) != .completed {
            XCTContext.runActivity(named: "Actual reader viewport failure") { activity in
                let screenshot = XCTAttachment(screenshot: app.screenshot()); screenshot.name = "reader-viewport-failure"; screenshot.lifetime = .keepAlways; activity.add(screenshot)
                let hierarchy = XCTAttachment(string: app.debugDescription); hierarchy.name = "reader-viewport-hierarchy"; hierarchy.lifetime = .keepAlways; activity.add(hierarchy)
            }
            XCTFail("The actual reader scroll view did not lay out within the visible window")
        }
        XCTAssertGreaterThan(scroll.frame.width, 100)
        XCTAssertGreaterThan(scroll.frame.height, 100, "A text element in a zero-sized scroll view does not prove readable content")
    }

    static func visibleFrame(_ element: XCUIElement, in app: XCUIApplication) -> CGRect? {
        guard element.exists else { return nil }
        let frame = element.frame, window = app.windows.firstMatch.frame
        guard !frame.isNull, !frame.isInfinite, frame.width > 1, frame.height > 1,
              frame.minX.isFinite, frame.minY.isFinite, frame.maxX.isFinite, frame.maxY.isFinite,
              window.contains(CGPoint(x: frame.midX, y: frame.midY)) else { return nil }
        return frame
    }

    static func reveal(_ element: XCUIElement, in app: XCUIApplication, up: Bool = true, container: XCUIElement? = nil) {
        for _ in 0..<(container == nil ? 14 : 30) {
            // Querying hittability before a lazy cell has a visible frame throws inside XCTest.
            if visibleFrame(element, in: app) != nil, element.isHittable { return }
            if let container { swipeVisible(container, in: app, up: up) }
            else if up { app.swipeUp() } else { app.swipeDown() }
        }
        XCTAssertNotNil(visibleFrame(element, in: app), element.description)
        XCTAssertTrue(element.isHittable)
    }

    private static func swipeVisible(_ container: XCUIElement, in app: XCUIApplication, up: Bool) {
        let original = container.frame
        var frame = original.intersection(app.windows.firstMatch.frame)
        // A List's AX frame can extend behind the keyboard and its safe-area footer.
        for overlay in [app.keyboards.firstMatch, app.buttons["ebook-passage-close"], app.buttons["ebook-narration-done"]] where overlay.exists {
            let boundary = overlay.frame
            if frame.intersects(boundary), boundary.minY > frame.minY { frame.size.height = min(frame.maxY, boundary.minY) - frame.minY }
        }
        guard original.minX.isFinite, original.minY.isFinite, !frame.isNull, frame.width > 80, frame.height > 80 else { XCTFail("No visible viewport to scroll: " + container.description); return }
        let origin = container.coordinate(withNormalizedOffset: .zero)
        let first = origin.withOffset(.init(dx: frame.midX - original.minX, dy: frame.minY - original.minY + frame.height * (up ? 0.8 : 0.2)))
        let last = origin.withOffset(.init(dx: frame.midX - original.minX, dy: frame.minY - original.minY + frame.height * (up ? 0.2 : 0.8)))
        first.press(forDuration: 0.05, thenDragTo: last)
    }

    static func revealWithinViewport(_ element: XCUIElement, in app: XCUIApplication, container: XCUIElement) {
        for _ in 0..<30 {
            var viewport = container.frame.intersection(app.windows.firstMatch.frame)
            let search = app.searchFields.firstMatch
            if search.exists, viewport.intersects(search.frame) {
                let top = max(viewport.minY, search.frame.maxY)
                viewport.size.height = max(0, viewport.maxY - top); viewport.origin.y = top
            }
            for overlay in [app.keyboards.firstMatch, app.buttons["ebook-narration-done"]] where overlay.exists {
                if viewport.intersects(overlay.frame) { viewport.size.height = max(0, min(viewport.maxY, overlay.frame.minY) - viewport.minY) }
            }
            if let frame = visibleFrame(element, in: app), viewport.contains(frame), element.isHittable { return }
            let above = element.exists && element.frame.maxY < viewport.minY
            swipeVisible(container, in: app, up: !above)
        }
        let hierarchy = XCTAttachment(string: app.debugDescription); hierarchy.name = "reading-visible-row-hierarchy"; hierarchy.lifetime = .keepAlways
        XCTContext.runActivity(named: "The requested row must be inside the unobstructed list") { $0.add(hierarchy) }
        XCTFail("The row remained behind the search bar or fixed footer: " + element.description)
    }

    static func waitForLandscape(_ app: XCUIApplication) {
        let settled = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let frame = app.windows.firstMatch.frame
            return frame.width > frame.height && !app.keyboards.firstMatch.exists
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [settled], timeout: 20), .completed, "Wait for the actual landscape window and dismissed keyboard before capturing")
    }

    static func tapVisible(_ element: XCUIElement, in app: XCUIApplication) {
        guard visibleFrame(element, in: app) != nil else { XCTFail("Control is outside the visible window: " + element.description); return }
        XCTAssertTrue(element.isEnabled)
        // Use the observed on-screen control; AXScrollToVisible fails on some iPad toolbar buttons.
        element.coordinate(withNormalizedOffset: .init(dx: 0.5, dy: 0.5)).tap()
    }

    static func back(from title: String, in app: XCUIApplication) {
        let bar = app.navigationBars[title]
        XCTAssertTrue(bar.waitForExistence(timeout: 15))
        let back = bar.buttons.element(boundBy: 0)
        XCTAssertTrue(back.waitForExistence(timeout: 10)); tapVisible(back, in: app)
    }

    static func replace(_ field: XCUIElement, with value: String, in app: XCUIApplication) {
        field.tap(); field.press(forDuration: 1.1)
        let predicate = NSPredicate(format: "label IN %@", ["Select All", "Seleccionar todo"])
        let menu = app.menuItems.matching(predicate).firstMatch
        let button = app.buttons.matching(predicate).firstMatch
        if menu.waitForExistence(timeout: 2) { menu.tap() }
        else if button.waitForExistence(timeout: 2) { button.tap() }
        else { XCTFail("The text selection menu did not offer Select All"); return }
        field.typeText(value)
        XCTAssertEqual(field.value as? String, value, "Replace the entire value before saving")
    }
}

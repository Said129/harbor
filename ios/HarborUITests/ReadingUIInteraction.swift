import XCTest

@MainActor enum ReadingUIInteraction {
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
        for _ in 0..<14 {
            // Querying hittability before a lazy cell has a visible frame throws inside XCTest.
            if visibleFrame(element, in: app) != nil, element.isHittable { return }
            if up { (container ?? app).swipeUp() } else { (container ?? app).swipeDown() }
        }
        XCTAssertNotNil(visibleFrame(element, in: app), element.description)
        XCTAssertTrue(element.isHittable)
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

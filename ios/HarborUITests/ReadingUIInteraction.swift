import XCTest

@MainActor enum ReadingUIInteraction {
    static func chooseBookSource(_ name: String, in app: XCUIApplication) {
        let picker = app.buttons["ebook-source"]
        XCTAssertTrue(picker.waitForExistence(timeout: 20)); reveal(picker, in: app, up: false); picker.tap()
        let source = app.buttons[name].firstMatch
        XCTAssertTrue(source.waitForExistence(timeout: 10)); source.tap()
    }

    static func assertReaderViewport(_ app: XCUIApplication) {
        let scroll = app.scrollViews.firstMatch
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

    static func reveal(_ element: XCUIElement, in app: XCUIApplication, up: Bool = true) {
        for _ in 0..<14 {
            // Querying hittability before a lazy cell has a visible frame throws inside XCTest.
            if visibleFrame(element, in: app) != nil, element.isHittable { return }
            if up { app.swipeUp() } else { app.swipeDown() }
        }
        XCTAssertNotNil(visibleFrame(element, in: app), element.description)
        XCTAssertTrue(element.isHittable)
    }

    static func tapVisible(_ element: XCUIElement, in app: XCUIApplication) {
        guard let frame = visibleFrame(element, in: app) else { XCTFail("Control is outside the visible window: " + element.description); return }
        XCTAssertTrue(element.isEnabled)
        // Use the observed on-screen control; AXScrollToVisible fails on some iPad toolbar buttons.
        app.coordinate(withNormalizedOffset: .zero).withOffset(.init(dx: frame.midX, dy: frame.midY)).tap()
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

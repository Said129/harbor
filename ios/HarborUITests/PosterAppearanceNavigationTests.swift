import XCTest

@MainActor final class PosterAppearanceNavigationTests: XCTestCase {
    func testDesktopPosterAndTVChoicesRenderFitPersistAndResetOnIPhone() { verify("iphone") }
    func testDesktopPosterAndTVChoicesRenderFitPersistAndResetOnIPad() { verify("ipad") }
    private func verify(_ device: String) {
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "site.harbor.iphone")
        app.launchArguments = ["-uiLanguage", "en", "-homeMode", "classic", "-nativeGuide.initialized.v1", "YES", "-nativeGuide.completed.v1", "YES"]
        ReadingUIInteraction.launchPreparedApplication(app)
        defer { if (testRun?.failureCount ?? 0) > 0 { ReadingUIInteraction.recordFailureContext(app) }; app.terminate() }
        let portrait = openCatalog(app)
        XCTAssertGreaterThan(portrait.frame.height, portrait.frame.width * 1.3)
        capture(app, "poster-grid-" + device)
        relaunch(app); openAppearance(app)
        assertBundledPreview(app, style: "poster", height: 177)
        capture(app, "poster-fallback-preview-" + device)
        choose("poster-card-style", "TV", app)
        choose("poster-logo-position", "Center", app)
        assertBundledPreview(app, style: "tv", height: 132.75)
        capture(app, "poster-fallback-tv-preview-" + device)
        let size = app.sliders["poster-card-size"], radius = app.sliders["poster-card-radius"]
        show(size, app); size.adjust(toNormalizedSliderPosition: 1)
        show(radius, app); radius.adjust(toNormalizedSliderPosition: 1)
        let sizeValue = size.value as? String, radiusValue = radius.value as? String
        XCTAssertNotNil(sizeValue); XCTAssertNotNil(radiusValue)
        show(app.segmentedControls["poster-card-style"], app, up: false)
        capture(app, "poster-tv-controls-" + device)
        choose("poster-card-effect", "Fade", app)
        choose("poster-card-quality", "Balanced", app)
        capture(app, "poster-quality-controls-" + device)
        let behaviorIDs = ["poster-focused-card", "poster-backdrop-expansion", "poster-dock-magnification"]
        for identifier in behaviorIDs {
            let toggle = app.switches[identifier]; show(toggle, app)
            XCTAssertEqual(toggle.value as? String, "0"); ReadingUIInteraction.tapVisible(toggle, in: app)
            XCTAssertEqual(toggle.value as? String, "1")
        }
        let duration = app.sliders["poster-dock-duration"]; show(duration, app)
        duration.adjust(toNormalizedSliderPosition: 0.8); let durationValue = duration.value as? String
        XCTAssertNotNil(durationValue)
        let preview = app.descendants(matching: .any).matching(identifier: "poster-dock-preview").firstMatch
        show(preview, app); XCTAssertEqual(preview.value as? String, "The General")
        XCTAssertGreaterThan(preview.frame.width, 200); XCTAssertGreaterThan(preview.frame.height, 70)
        capture(app, "poster-behavior-controls-" + device)
        relaunch(app)
        let wide = openCatalog(app)
        XCTAssertGreaterThan(wide.frame.width, wide.frame.height * 1.5)
        XCTAssertLessThanOrEqual(wide.frame.maxX, app.frame.maxX + 1)
        XCTAssertGreaterThanOrEqual(wide.frame.minX, app.frame.minX - 1)
        capture(app, "poster-tv-grid-" + device)
        relaunch(app); openAppearance(app)
        assertChoice("poster-card-style", "TV", app)
        assertChoice("poster-logo-position", "Center", app)
        show(size, app); XCTAssertEqual(size.value as? String, sizeValue)
        show(radius, app); XCTAssertEqual(radius.value as? String, radiusValue)
        assertChoice("poster-card-effect", "Fade", app)
        assertChoice("poster-card-quality", "Balanced", app)
        capture(app, "poster-restored-" + device)
        for identifier in behaviorIDs { let toggle = app.switches[identifier]; show(toggle, app); XCTAssertEqual(toggle.value as? String, "1") }
        show(duration, app); XCTAssertEqual(duration.value as? String, durationValue)
        show(preview, app); capture(app, "poster-behavior-restored-" + device)
        let reset = app.buttons["theme-reset"]; show(reset, app); ReadingUIInteraction.tapVisible(reset, in: app)
        for identifier in behaviorIDs { let toggle = app.switches[identifier]; show(toggle, app, up: false); XCTAssertEqual(toggle.value as? String, "0") }
        XCTAssertFalse(duration.exists); capture(app, "poster-behavior-reset-" + device)
        assertChoice("poster-card-style", "Poster", app, up: false)
        assertChoice("poster-card-effect", "Instant", app)
        assertChoice("poster-card-quality", "High", app)
        capture(app, "poster-reset-" + device)
    }
    private func relaunch(_ app: XCUIApplication) { app.terminate(); ReadingUIInteraction.launchPreparedApplication(app) }
    private func assertBundledPreview(_ app: XCUIApplication, style: String, height: CGFloat) {
        let preview = app.descendants(matching: .any).matching(identifier: "poster-card-preview").firstMatch
        show(preview, app, up: false)
        XCTAssertEqual(preview.label, "The General"); XCTAssertEqual(preview.value as? String, style)
        XCTAssertEqual(preview.frame.height, height, accuracy: 4)
        XCTAssertLessThanOrEqual(preview.frame.maxX, app.windows.firstMatch.frame.maxX)
    }
    private func openCatalog(_ app: XCUIApplication) -> XCUIElement {
        let scroll = app.scrollViews["home-scroll"]
        XCTAssertTrue(scroll.waitForExistence(timeout: 45))
        let folder = app.descendants(matching: .any).matching(identifier: "source-folder-owned-posters-0").firstMatch
        ReadingUIInteraction.reveal(folder, in: app, container: scroll)
        ReadingUIInteraction.tapVisible(folder, in: app)
        let title = app.buttons["catalog-browser-media"].firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 30))
        ReadingUIInteraction.revealWithinViewport(title, in: app, container: app.scrollViews["catalog-browser-scroll"])
        XCTAssertEqual(title.label, "Owned catalog title 1")
        return title
    }
    private func openAppearance(_ app: XCUIApplication) {
        let menu = app.buttons["main-menu"]; XCTAssertTrue(menu.waitForExistence(timeout: 45)); ReadingUIInteraction.tapVisible(menu, in: app)
        let navigation = app.descendants(matching: .any).matching(identifier: "navigation-scroll").firstMatch
        XCTAssertTrue(navigation.waitForExistence(timeout: 10))
        let settings = app.buttons["nav-settings"]
        ReadingUIInteraction.reveal(settings, in: app, container: navigation); ReadingUIInteraction.tapVisible(settings, in: app)
        let scroll = app.scrollViews["settings-scroll"]
        XCTAssertTrue(scroll.waitForExistence(timeout: 15))
        let appearance = app.buttons["settings-theme"]
        ReadingUIInteraction.reveal(appearance, in: app, container: scroll); ReadingUIInteraction.tapVisible(appearance, in: app)
        XCTAssertTrue(app.scrollViews["theme-settings-scroll"].waitForExistence(timeout: 15))
    }
    private func show(_ control: XCUIElement, _ app: XCUIApplication, up: Bool = true) {
        let scroll = app.scrollViews["theme-settings-scroll"]
        // The iPad seek-bar preview consumes drags started through its timeline.
        // Scroll in the page's outer gutter so the page receives the gesture.
        for _ in 0..<16 {
            let bounds = scroll.frame
            var viewport = bounds.intersection(app.windows.firstMatch.frame)
            viewport.size.height = max(0, viewport.height - 28)
            if let frame = ReadingUIInteraction.visibleFrame(control, in: app), viewport.contains(frame), control.isHittable { return }
            guard !viewport.isNull, viewport.height > 80, viewport.width > 80 else { break }
            let above = control.exists ? control.frame.midY < viewport.midY : !up
            let origin = scroll.coordinate(withNormalizedOffset: .zero)
            let start = origin.withOffset(.init(dx: viewport.minX - bounds.minX + 8, dy: viewport.minY - bounds.minY + viewport.height * (above ? 0.2 : 0.8)))
            let end = origin.withOffset(.init(dx: viewport.minX - bounds.minX + 8, dy: viewport.minY - bounds.minY + viewport.height * (above ? 0.8 : 0.2)))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
        ReadingUIInteraction.recordFailureContext(app)
        XCTFail("The appearance control must be inside the visible page: " + control.description)
    }
    private func choose(_ identifier: String, _ choice: String, _ app: XCUIApplication) {
        let picker = app.segmentedControls[identifier]; show(picker, app)
        ReadingUIInteraction.tapVisible(picker.buttons[choice], in: app)
        XCTAssertTrue(picker.buttons[choice].isSelected)
    }
    private func assertChoice(_ identifier: String, _ choice: String, _ app: XCUIApplication, up: Bool = true) {
        let picker = app.segmentedControls[identifier]; show(picker, app, up: up)
        XCTAssertTrue(picker.buttons[choice].isSelected)
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}

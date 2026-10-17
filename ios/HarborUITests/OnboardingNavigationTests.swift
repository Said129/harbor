import XCTest

@MainActor final class OnboardingNavigationTests: XCTestCase {
    func testTenStepSetupUsesRealControlsInTheIPhoneInterface() { verifyGuide(device: "iphone") }
    func testTenStepSetupUsesRealControlsInTheIPadInterface() { verifyGuide(device: "ipad") }

    private func verifyGuide(device: String) {
        continueAfterFailure = false
        let app = XCUIApplication()
        let fresh = device == "iphone"
        app.launchArguments = ["-uiLanguage", "es", "-nativeGuide.initialized.v1", "YES", "-nativeGuide.completed.v1", fresh ? "NO" : "YES"]
        app.launch(); defer { app.terminate() }
        let replay = app.buttons["about-replay"]
        if !fresh {
            XCTAssertTrue(app.buttons["main-menu"].waitForExistence(timeout: 45)); app.buttons["main-menu"].tap()
            let navigation = app.descendants(matching: .any).matching(identifier: "navigation-scroll").firstMatch
            let settings = app.buttons["nav-settings"]
            for _ in 0..<10 { if settings.isHittable { break }; navigation.swipeUp() }
            XCTAssertTrue(settings.isHittable); settings.press(forDuration: 0.6)
            let search = app.textFields.firstMatch
            XCTAssertTrue(search.waitForExistence(timeout: 10)); search.tap(); search.typeText("About")
            let about = app.buttons["settings-about"]
            XCTAssertTrue(about.waitForExistence(timeout: 5)); about.tap()
            XCTAssertTrue(replay.waitForExistence(timeout: 10)); replay.tap()
        }
        let splash = app.descendants(matching: .any).matching(identifier: "guide-splash").firstMatch
        if splash.exists { capture(app, name: "setup-\(device)-splash") }
        else {
            let observation = XCTAttachment(string: "The synchronized XCTest action returned after the transient splash. Inspect the real setup-\(device).mp4 recording; the next screen is checked below.")
            observation.name = "setup-\(device)-transient-splash-observation"; observation.lifetime = .keepAlways; add(observation)
        }
        stage("language", in: app, timeout: fresh ? 45 : 10); capture(app, name: "setup-\(device)-language")
        let language = app.buttons["guide-language-es"]
        reveal(language, in: app); language.tap()
        next(app); stage("welcome", in: app); capture(app, name: "setup-\(device)-welcome")
        next(app); stage("layout", in: app)
        let classic = app.buttons["home-style-classic"]
        reveal(classic, in: app); classic.tap(); XCTAssertTrue(classic.isSelected)
        capture(app, name: "setup-\(device)-layout")
        next(app); stage("tmdb", in: app); capture(app, name: "setup-\(device)-tmdb")
        let key = app.buttons["guide-metadata-key"]
        reveal(key, in: app); key.tap()
        XCTAssertTrue(app.buttons["metadata-key-close"].waitForExistence(timeout: 5)); app.buttons["metadata-key-close"].tap()
        next(app); stage("stremio", in: app); capture(app, name: "setup-\(device)-stremio")
        XCTAssertTrue(app.buttons["guide-stremio-account"].exists)
        next(app); stage("streaming", in: app)
        let netflix = app.buttons["streaming-netflix"]
        reveal(netflix, in: app)
        let previous = netflix.value as? String; netflix.tap()
        XCTAssertNotEqual(netflix.value as? String, previous)
        capture(app, name: "setup-\(device)-streaming")
        next(app); stage("subtitles", in: app)
        let picker = app.buttons["guide-subtitle-languages-toggle"]
        reveal(picker, in: app); picker.tap()
        let japanese = app.buttons["guide-subtitle-languages-add-ja"]
        let selectedJapanese = app.descendants(matching: .any).matching(identifier: "guide-subtitle-languages-selected-ja").firstMatch
        if !selectedJapanese.exists {
            let languageSearch = app.textFields["guide-subtitle-languages-search"]
            reveal(languageSearch, in: app); languageSearch.tap(); languageSearch.typeText("Japanese")
            XCTAssertTrue(japanese.waitForExistence(timeout: 5)); japanese.tap()
        }
        XCTAssertTrue(selectedJapanese.exists)
        capture(app, name: "setup-\(device)-subtitles")
        next(app); stage("taste", in: app)
        let title = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "guide-taste-")).firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 60)); reveal(title, in: app); title.tap()
        XCTAssertTrue(title.isSelected)
        capture(app, name: "setup-\(device)-taste")
        app.buttons["guide-skip-step"].tap()
        stage("done", in: app)
        // The reference check finishes drawing after 840 ms; inspect its end state.
        Thread.sleep(forTimeInterval: 0.9)
        capture(app, name: "setup-\(device)-done")
        next(app)
        if fresh { XCTAssertTrue(app.buttons["main-menu"].waitForExistence(timeout: 10)) }
        else { XCTAssertTrue(replay.waitForExistence(timeout: 10)) }
    }
    private func next(_ app: XCUIApplication) {
        let button = app.buttons["guide-next"]
        XCTAssertTrue(button.waitForExistence(timeout: 10)); XCTAssertTrue(button.isHittable); button.tap()
    }
    private func stage(_ name: String, in app: XCUIApplication, timeout: TimeInterval = 10) {
        let target = app.descendants(matching: .any).matching(identifier: "guide-stage-" + name).firstMatch
        XCTAssertTrue(target.waitForExistence(timeout: timeout))
    }
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        let content = app.scrollViews["guide-content"]
        for _ in 0..<10 { if element.isHittable { break }; content.swipeUp() }
        XCTAssertTrue(element.isHittable)
    }
    private func capture(_ app: XCUIApplication, name: String) {
        let image = XCTAttachment(screenshot: app.screenshot()); image.name = name; image.lifetime = .keepAlways; add(image)
    }
}

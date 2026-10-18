import XCTest
@testable import Harbor

@MainActor final class AppGuideTests: XCTestCase {
    private func withDefaults(_ body: (UserDefaults) throws -> Void) throws {
        let suite = "HarborGuideTests-" + UUID().uuidString, defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        try body(defaults)
    }
    func testExistingSetupSkipsWelcomeAndKeepsOtherPreferences() throws {
        try withDefaults { defaults in
            defaults.set("ja", forKey: "uiLanguage"); defaults.set(["home", "anime"], forKey: "navigationOrder")
            let guide = AppGuidePreferences(defaults: defaults)
            guide.prepare(hasSavedConfiguration: true)
            XCTAssertTrue(guide.completed); XCTAssertFalse(guide.presentationRequested)
            guide.prepare(hasSavedConfiguration: false)
            XCTAssertTrue(guide.completed, "A later empty account must not reinitialize the walkthrough")
            XCTAssertEqual(defaults.string(forKey: "uiLanguage"), "ja")
            XCTAssertEqual(defaults.stringArray(forKey: "navigationOrder"), ["home", "anime"])
        }
    }
    func testFreshWelcomeResumesUntilFinishedAndReplayRestoresOnlyGuideHints() throws {
        try withDefaults { defaults in
            defaults.set("es", forKey: "uiLanguage"); defaults.set("kept", forKey: "unrelatedData")
            let first = AppGuidePreferences(defaults: defaults); first.prepare(hasSavedConfiguration: false)
            XCTAssertFalse(first.completed); XCTAssertTrue(first.presentationRequested)
            let reopened = AppGuidePreferences(defaults: defaults)
            XCTAssertTrue(reopened.presentationRequested)
            reopened.finish()
            let finished = AppGuidePreferences(defaults: defaults)
            XCTAssertTrue(finished.completed); XCTAssertFalse(finished.presentationRequested)
            finished.dismiss(.imageCache); XCTAssertFalse(finished.isVisible(.imageCache))
            XCTAssertFalse(AppGuidePreferences(defaults: defaults).isVisible(.imageCache))
            finished.replay()
            XCTAssertFalse(finished.completed); XCTAssertTrue(finished.presentationRequested); XCTAssertTrue(finished.isVisible(.imageCache))
            XCTAssertEqual(defaults.string(forKey: "uiLanguage"), "es"); XCTAssertEqual(defaults.string(forKey: "unrelatedData"), "kept")
        }
    }
    func testRestoringHintsDoesNotReopenWelcome() throws {
        try withDefaults { defaults in
            let guide = AppGuidePreferences(defaults: defaults); guide.prepare(hasSavedConfiguration: true)
            guide.dismiss(.imageCache); guide.restoreHints()
            XCTAssertTrue(guide.isVisible(.imageCache)); XCTAssertTrue(guide.completed); XCTAssertFalse(guide.presentationRequested)
            XCTAssertTrue(AppGuidePreferences(defaults: defaults).isVisible(.imageCache))
        }
    }
    func testDesktopVariablesAreReplacedOnceWithUnicodeAndLiteralBraces() {
        XCTAssertEqual(DesktopInterfaceText.interpolate("{app}: {name}; {name}; {unknown}", variables: ["app": "Harbor {name}", "name": "日本語 📚"]), "Harbor {name}: 日本語 📚; 日本語 📚; {unknown}")
        XCTAssertEqual(DesktopInterfaceText.interpolate("مرحبا {name}!", variables: ["name": "読者"]), "مرحبا 読者!")
        XCTAssertEqual(DesktopInterfaceText.interpolate("{empty}x{empty}", variables: ["empty": ""]), "x")
    }
}

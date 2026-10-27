import XCTest

@MainActor final class HarborAccountNoteNavigationTests: XCTestCase {
    func testActualHarborServerNoteFollowsEnglishAndSpanishOnIPhone() { verify("iphone") }
    func testActualHarborServerNoteFollowsEnglishAndSpanishOnIPad() { verify("ipad") }
    private func verify(_ device: String) {
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "site.harbor.iphone")
        defer { if (testRun?.failureCount ?? 0) > 0 { ReadingUIInteraction.recordFailureContext(app) }; app.terminate() }
        for language in ["en", "es"] {
            app.launchArguments = ["-uiLanguage", language, "-homeMode", "classic", "-nativeGuide.initialized.v1", "YES", "-nativeGuide.completed.v1", "YES"]
            ReadingUIInteraction.launchPreparedApplication(app)
            let account = app.buttons["main-account"].firstMatch
            XCTAssertTrue(account.waitForExistence(timeout: 45)); ReadingUIInteraction.tapVisible(account, in: app)
            let tab = app.buttons["account-tab-harbor"]; XCTAssertTrue(tab.waitForExistence(timeout: 15)); ReadingUIInteraction.tapVisible(tab, in: app)
            let note = app.staticTexts["harbor-server-note"]
            ReadingUIInteraction.revealWithinViewport(note, in: app, container: app.scrollViews["account-scroll"])
            XCTAssertEqual(note.label, language == "en"
                ? "Use an account from this server. The original service closed; its sessions do not transfer automatically."
                : "Usa una cuenta de este servidor. El servicio original cerró; sus sesiones no se transfieren automáticamente.")
            XCTAssertTrue(note.isHittable); XCTAssertFalse(app.buttons["account-tab-stremio"].exists)
            let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = "harbor-server-note-" + language + "-" + device; attachment.lifetime = .keepAlways; add(attachment)
            app.terminate()
        }
    }
}

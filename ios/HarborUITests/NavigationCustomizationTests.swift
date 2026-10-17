import XCTest

@MainActor final class NavigationCustomizationTests: XCTestCase {
    func testOrdinaryIPhoneNavigationEditsPersistAfterRelaunch() { verifyNavigation(device: "iphone") }
    func testOrdinaryIPadNavigationEditsPersistAfterRelaunch() { verifyNavigation(device: "ipad") }

    private func verifyNavigation(device: String) {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchArguments = ["-uiLanguage", "es", "-nativeGuide.initialized.v1", "YES", "-nativeGuide.completed.v1", "YES"]; app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.buttons["main-menu"].waitForExistence(timeout: 45))
        app.buttons["main-menu"].tap()
        let menu = app.descendants(matching: .any).matching(identifier: "navigation-scroll").firstMatch
        let settings = app.buttons["nav-settings"]
        for _ in 0..<12 { if settings.isHittable { break }; menu.swipeUp() }
        XCTAssertTrue(settings.isHittable); settings.tap()
        let search = app.textFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 10)); search.tap(); search.typeText("Library")
        let library = app.buttons["settings-interface"]
        XCTAssertTrue(library.waitForExistence(timeout: 5)); library.tap()
        let interface = app.descendants(matching: .any).matching(identifier: "interface-settings-scroll").firstMatch
        let navigation = app.buttons["settings-navigation"]
        for _ in 0..<12 { if navigation.isHittable { break }; interface.swipeUp() }
        XCTAssertTrue(navigation.isHittable); navigation.tap()
        let editor = app.descendants(matching: .any).matching(identifier: "navigation-settings-scroll").firstMatch
        let anime = app.textFields["navigation-name-anime"]
        for _ in 0..<12 { if anime.isHittable { break }; editor.swipeUp() }
        XCTAssertTrue(anime.isHittable)
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: anime)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 30), .completed)
        anime.tap()
        let previous = anime.value as? String ?? ""
        anime.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: previous.count) + "Mi anime\n")
        XCTAssertEqual(anime.value as? String, "Mi anime")
        let hideMusic = app.buttons["navigation-visible-music"]
        for _ in 0..<12 { if hideMusic.isHittable { break }; editor.swipeDown() }
        XCTAssertTrue(hideMusic.isHittable)
        if hideMusic.value as? String != "Oculto" { hideMusic.tap() }
        XCTAssertEqual(hideMusic.value as? String, "Oculto")
        let move = app.buttons["navigation-up-anime"]
        for _ in 0..<12 { if move.isHittable { break }; editor.swipeUp() }
        XCTAssertTrue(move.isHittable); move.tap()
        capture(app, name: "navigation-local-" + device + "-configured")
        app.buttons["main-menu"].tap()
        let renamed = app.buttons["nav-anime"]
        let currentMenu = app.descendants(matching: .any).matching(identifier: "navigation-scroll").firstMatch
        for _ in 0..<12 { if renamed.isHittable { break }; currentMenu.swipeUp() }
        XCTAssertTrue(renamed.isHittable); XCTAssertEqual(renamed.label, "Mi anime")
        XCTAssertFalse(app.buttons["nav-music"].exists)
        capture(app, name: "navigation-local-" + device + "-menu")
        app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["main-menu"].waitForExistence(timeout: 45)); app.buttons["main-menu"].tap()
        let restored = app.buttons["nav-anime"]
        let restoredMenu = app.descendants(matching: .any).matching(identifier: "navigation-scroll").firstMatch
        let restoredName = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "Mi anime"), object: restored)
        XCTAssertEqual(XCTWaiter.wait(for: [restoredName], timeout: 20), .completed)
        for _ in 0..<12 { if restored.isHittable { break }; restoredMenu.swipeUp() }
        XCTAssertTrue(restored.isHittable); XCTAssertEqual(restored.label, "Mi anime")
        XCTAssertFalse(app.buttons["nav-music"].exists)
        capture(app, name: "navigation-local-" + device + "-restored")
    }
    private func capture(_ app: XCUIApplication, name: String) {
        let capture = XCTAttachment(screenshot: app.screenshot()); capture.name = name; capture.lifetime = .keepAlways; add(capture)
    }
}

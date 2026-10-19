import XCTest

@MainActor final class ContinuationParityNavigationTests: XCTestCase {
    func testIMDbAnimeContinuesInAnimeAndShowsWithAbsoluteEpisodeNumber() {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchArguments = ["-uiLanguage", "es", "-tvdbSeasonType", "absolute"]; app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.buttons["main-menu"].waitForExistence(timeout: 45))
        for section in ["anime", "shows"] {
            app.buttons["main-menu"].tap()
            let destination = app.buttons["nav-\(section)"]
            let navigation = app.descendants(matching: .any).matching(identifier: "navigation-scroll").firstMatch
            XCTAssertTrue(navigation.waitForExistence(timeout: 10))
            for _ in 0..<8 { if destination.isHittable { break }; navigation.swipeUp() }
            XCTAssertTrue(destination.isHittable); destination.tap()
            let card = app.buttons.matching(NSPredicate(format: "identifier == 'continue-watching-resume' AND label == 'Continuar viendo Dragon Ball Super'")).firstMatch
            if !card.waitForExistence(timeout: 30) {
                for _ in 0..<4 { app.swipeUp(); if card.waitForExistence(timeout: 10) { break } }
            }
            XCTAssertTrue(card.waitForExistence(timeout: 30))
            for _ in 0..<10 {
                if card.isHittable { break }
                if card.frame.midY < app.frame.minY + 100 { app.swipeDown() } else { app.swipeUp() }
            }
            XCTAssertTrue(card.isHittable)
            let absolute = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value CONTAINS 'T1 · E99'"), object: card)
            XCTAssertEqual(XCTWaiter.wait(for: [absolute], timeout: 90), .completed)
            XCTAssertTrue(app.buttons["continue-watching-remove"].firstMatch.exists)
            if card.frame.maxY > app.frame.maxY - 100 { app.swipeUp() }
            Thread.sleep(forTimeInterval: 2)
            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.name = "continue-super-99-\(section)"; attachment.lifetime = .keepAlways; add(attachment)
        }
    }
}

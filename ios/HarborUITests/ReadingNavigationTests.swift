import XCTest
import UIKit

@MainActor final class ReadingNavigationTests: XCTestCase {
    func testGutenbergSearchAndReadTheActualCoverAndText() throws {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchArguments = ["-uiLanguage", "es"]; app.launch()
        defer { app.terminate() }
        navigate(app, "ebook")
        let field = app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10)); field.tap(); field.typeText("Frankenstein\n")
        expectKeyboardClosed(app)
        let result = app.buttons["ebook-card-gutendex:84"]
        XCTAssertTrue(result.waitForExistence(timeout: 90), "Typing must actually search Gutenberg")
        XCTAssertTrue(result.isHittable)
        capture("gutenberg-frankenstein-results")
        result.tap()
        let read = app.buttons["ebook-detail-read"]
        XCTAssertTrue(read.waitForExistence(timeout: 15)); read.tap()
        let next = app.buttons["ebook-next-section"]
        let opened = next.waitForExistence(timeout: 90)
        capture("gutenberg-after-open")
        XCTAssertTrue(opened, "A real catalog EPUB must open")
        XCTAssertFalse(app.staticTexts["ebook-reader-error"].exists)
        capture("gutenberg-real-cover")
        next.tap()
        XCTAssertTrue(app.staticTexts["ebook-reader-text"].firstMatch.waitForExistence(timeout: 15))
        XCTAssertFalse(app.staticTexts["ebook-reader-error"].exists)
        capture("gutenberg-real-text")
    }

    func testLocalShelvesSearchSortCoversAndPDFMangaReader() throws {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchArguments = ["-uiLanguage", "es"]; XCUIDevice.shared.orientation = .portrait; app.launch()
        defer { XCUIDevice.shared.orientation = .portrait; app.terminate() }
        navigate(app, "ebook")
        let picker = app.segmentedControls["ebook-screen"]
        XCTAssertTrue(picker.waitForExistence(timeout: 10)); picker.buttons.element(boundBy: 1).tap()
        let field = app.textFields.firstMatch
        XCTAssertTrue(field.exists); field.tap(); field.typeText("Reading Volume\n")
        expectKeyboardClosed(app)
        let first = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'ebook-card-' AND label CONTAINS 'Reading Volume 1'")).firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 15))
        let links = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'ebook-card-'")).allElementsBoundByIndex
        XCTAssertEqual(links.count, 3)
        XCTAssertTrue(links[0].label.contains("Reading Volume 1")); XCTAssertTrue(links[1].label.contains("Reading Volume 2")); XCTAssertTrue(links[2].label.contains("Reading Volume 10"))
        capture("imported-ebook-covers-natural-order")
        let sort = app.buttons["reading-shelf-sort"]
        XCTAssertTrue(sort.isHittable); sort.tap()
        let recent = app.buttons["Leídos recientemente"].firstMatch
        XCTAssertTrue(recent.waitForExistence(timeout: 5)); recent.tap()
        capture("imported-ebook-sort-choice")
        navigate(app, "manga")
        let library = app.buttons["manga-library-card"]
        XCTAssertTrue(library.waitForExistence(timeout: 15))
        for _ in 0..<5 { if library.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(library.isHittable); library.tap()
        app.swipeDown(); app.swipeDown()
        let mangaSearch = app.textFields.firstMatch
        for _ in 0..<4 { if mangaSearch.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(mangaSearch.isHittable); mangaSearch.tap(); mangaSearch.typeText("Reading Volume 2\n")
        expectKeyboardClosed(app)
        app.swipeUp()
        let manga = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'manga-card-' AND label CONTAINS 'Reading Volume 2'")).firstMatch
        for _ in 0..<4 { if manga.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(manga.isHittable)
        capture("imported-manga-pdf-cover-search")
        manga.tap()
        let read = app.buttons["manga-detail-read"]
        XCTAssertTrue(read.waitForExistence(timeout: 20)); read.tap()
        let image = app.images["manga-page-0"].firstMatch
        XCTAssertTrue(image.waitForExistence(timeout: 20), "The PDF's rasterized page must actually render in the Manga reader")
        capture("manga-pdf-reader-portrait")
        try assertPageFillsReader(image, app: app)
        if max(app.frame.width, app.frame.height) >= 1000 {
            XCUIDevice.shared.orientation = .landscapeLeft
            let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in app.frame.width > app.frame.height && image.isHittable }, object: app)
            XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 45), .completed)
            capture("manga-pdf-reader-ipad-landscape")
            try assertPageFillsReader(image, app: app)
        }
    }
    private func navigate(_ app: XCUIApplication, _ name: String) {
        let menu = app.buttons["main-menu"]
        XCTAssertTrue(menu.waitForExistence(timeout: 30)); menu.tap()
        let scroll = app.descendants(matching: .any).matching(identifier: "navigation-scroll").firstMatch
        XCTAssertTrue(scroll.waitForExistence(timeout: 10))
        let button = app.buttons["nav-" + name]
        for _ in 0..<8 { if button.isHittable { break }; scroll.swipeDown() }
        for _ in 0..<8 { if button.isHittable { break }; scroll.swipeUp() }
        if !button.isHittable { capture("navigation-missing-" + name) }
        XCTAssertTrue(button.isHittable); button.tap()
    }
    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    private func expectKeyboardClosed(_ app: XCUIApplication) {
        let closed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.keyboards.firstMatch)
        XCTAssertEqual(XCTWaiter.wait(for: [closed], timeout: 10), .completed)
    }
    private func assertPageFillsReader(_ element: XCUIElement, app: XCUIApplication) throws {
        XCTAssertGreaterThan(element.frame.width, app.frame.width * 0.7, "Fit to width must show a readable full-size page")
        let shot = XCUIScreen.main.screenshot().image
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let normalized = UIGraphicsImageRenderer(size: app.frame.size, format: format).image { _ in shot.draw(in: CGRect(origin: .zero, size: app.frame.size)) }
        let screenshot = try XCTUnwrap(normalized.cgImage)
        let visible = element.frame.intersection(app.frame)
        let sx = CGFloat(screenshot.width) / app.frame.width, sy = CGFloat(screenshot.height) / app.frame.height
        let cropRect = CGRect(x: (visible.minX - app.frame.minX) * sx, y: (visible.minY - app.frame.minY) * sy, width: visible.width * sx, height: visible.height * sy).insetBy(dx: visible.width * sx * 0.08, dy: visible.height * sy * 0.08)
        let crop = try XCTUnwrap(screenshot.cropping(to: cropRect))
        var pixels = [UInt8](repeating: 0, count: 80 * 80 * 4)
        try pixels.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(CGContext(data: buffer.baseAddress, width: 80, height: 80, bitsPerComponent: 8, bytesPerRow: 320, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
            context.draw(crop, in: CGRect(x: 0, y: 0, width: 80, height: 80))
        }
        var colored = 0
        for offset in stride(from: 0, to: pixels.count, by: 4) {
            let red = Int(pixels[offset]), green = Int(pixels[offset + 1]), blue = Int(pixels[offset + 2])
            if blue > red + 40 && blue > green + 40 { colored += 1 }
        }
        XCTAssertGreaterThan(Double(colored) / 6400, 0.65, "The fixture page must fill the reader image, not remain a small picture in a white canvas")
    }
}

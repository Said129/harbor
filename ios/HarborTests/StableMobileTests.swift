import PDFKit
import SwiftUI
import XCTest
@testable import Harbor

final class StableMobileTests: XCTestCase {
    @MainActor func testImportEPUBAndPDFKeepsOwnerIsolationAndReadingPosition() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("My book.pdf")
        let pdf = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 600, height: 800)).pdfData { context in
            for page in 1...2 { context.beginPage(); ("Owned PDF page \(page)" as NSString).draw(at: CGPoint(x: 50, y: 50), withAttributes: [.font: UIFont.systemFont(ofSize: 24)]) }
        }
        try pdf.write(to: file)
        let service = EBookService(), owner = "reader-a-" + UUID().uuidString, other = "reader-b-" + UUID().uuidString
        let book = try await service.importDocument(file, owner: owner)
        XCTAssertTrue(book.isPDF)
        let same = try await service.importDocument(file, owner: other)
        XCTAssertEqual(same.id, book.id, "Identical file content has stable identity")
        let local = try await service.pdfURL(book, owner: owner), separate = try await service.pdfURL(same, owner: other)
        XCTAssertNotEqual(local, separate)
        XCTAssertEqual(PDFDocument(url: local)?.pageCount, 2)
        let shelf = EBookShelf(owner: owner)
        try shelf.addImported(book); try shelf.savePosition(book, chapter: 0, block: 1)
        let reimported = try await service.importDocument(file, owner: owner)
        try shelf.addImported(reimported)
        XCTAssertEqual(shelf.records.count, 1); XCTAssertEqual(shelf.record(book)?.block, 1)
        try await service.remove(book, owner: owner); try shelf.remove(book)
        XCTAssertTrue(FileManager.default.fileExists(atPath: separate.path), "Removing one account's copy keeps the other account's file")
        try await service.remove(same, owner: other)
        try Data("not a PDF".utf8).write(to: file)
        do { _ = try await service.importDocument(file, owner: owner); XCTFail("A corrupt PDF must be rejected") }
        catch let error as HarborError { XCTAssertEqual(error.code, "ebook-format") }
        let epub = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "reader", withExtension: "epub", subdirectory: "Fixtures"))
        let imported = try await service.importDocument(epub, owner: owner)
        XCTAssertFalse(imported.isPDF)
        let publication = try await service.open(imported, owner: owner)
        XCTAssertEqual(publication.chapters.count, 2)
        try await service.remove(imported, owner: owner)
        var fields = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(imported)) as? [String: Any])
        fields.removeValue(forKey: "format")
        let legacy = try JSONDecoder().decode(EBook.self, from: JSONSerialization.data(withJSONObject: fields))
        XCTAssertFalse(legacy.isPDF, "Books saved before build 89 remain EPUBs")
    }

    func testReopeningEPUBDoesNotRewriteTheCachedPublication() async throws {
        let service = EBookService(), owner = UUID().uuidString
        let epub = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "reader", withExtension: "epub", subdirectory: "Fixtures"))
        let book = try await service.importDocument(epub, owner: owner)
        let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
        let cached = support.appendingPathComponent("Harbor/eBooks/" + EBookShelf.hash(owner + "|" + book.id) + ".epub")
        let originalDate = Date(timeIntervalSince1970: 1_700_000_000)
        try FileManager.default.setAttributes([.modificationDate: originalDate], ofItemAtPath: cached.path)
        let restored = try await EBookService().open(book, owner: owner)
        XCTAssertEqual(restored.chapters.count, 2)
        let actual = try XCTUnwrap(FileManager.default.attributesOfItem(atPath: cached.path)[.modificationDate] as? Date)
        XCTAssertEqual(actual.timeIntervalSince1970, originalDate.timeIntervalSince1970, accuracy: 1)
        try await service.remove(book, owner: owner)
    }

    @MainActor func testDesktopLanguagesAndNativeFeedbackUseTheSelectedCatalog() throws {
        let defaults = UserDefaults.standard, old = defaults.string(forKey: "uiLanguage")
        defer { defaults.set(old, forKey: "uiLanguage") }
        XCTAssertEqual(Set(InterfaceLanguage.all.map(\.code)), ["en", "es", "ar", "pt", "ru"])
        let expected = ["en": "Settings", "es": "Configuración", "pt": "Configurações", "ru": "Настройки", "ar": "الإعدادات"]
        for language in InterfaceLanguage.all {
            defaults.set(language.code, forKey: "uiLanguage")
            XCTAssertEqual(DesktopInterfaceText.value("Settings"), expected[language.code])
            XCTAssertEqual(DesktopInterfaceText.value("Ajustes"), expected[language.code], "Native Spanish labels resolve through the same Desktop catalog")
            XCTAssertFalse(DesktopInterfaceText.value("Reading help").isEmpty)
            if language.code != "en" { XCTAssertNotEqual(DesktopInterfaceText.value("Couldn't auto-sync"), "Couldn't auto-sync") }
        }
        XCTAssertEqual(InterfaceLanguage.resolve("invalid"), "es")
        let state = PlayerState()
        let controller = MPVController(source: PlaybackSource(url: "https://example.org/not-opened.mp4", headers: nil, subtitles: nil, via: "fixture"), state: state)
        controller.synchronizeSubtitle()
        XCTAssertEqual(state.subtitleSyncPhase, .declined)
        XCTAssertNotNil(state.subtitleSyncMessage)
        controller.close()
    }

    @MainActor func testContinueDismissalAndPrepareNormalAppUITapFixture() async throws {
        // Seed only the simulator's ordinary guest cache. No fixture or test
        // launch mode is included in the application target or delivered IPA.
        let raw = try JSONDecoder().decode(JSONValue.self, from: Data(#"{"_id":"harbor-stable-removal-fixture","type":"movie","name":"Harbor removal fixture","removed":false,"temp":false,"_mtime":1791950000000,"state":{"timeOffset":120000,"duration":3600000}}"#.utf8))
        let cache = LibraryCache()
        try await cache.save([raw], owner: "guest")
        let app = AppModel()
        await app.library.setSession(nil)
        let record = try XCTUnwrap(app.library.items.first)
        app.library.showContinuing(record)
        app.library.hideContinuing(record, owner: "different-account")
        XCTAssertEqual(app.library.continuing.count, 1)
        try await render(ContinueWatching(app: app), size: CGSize(width: 393, height: 260), name: "continue-watching-x-before-removal-fixture")
        app.library.hideContinuing(record, owner: "guest")
        XCTAssertTrue(app.library.continuing.isEmpty)
        XCTAssertEqual(app.library.items.first?.raw, raw, "Dismissal must not change saved progress or library membership")
        let restored = LibraryModel(); await restored.setSession(nil)
        XCTAssertTrue(restored.continuing.isEmpty, "Dismissal persists for this owner")
        restored.showContinuing(record)
        UserDefaults.standard.set("es", forKey: "uiLanguage")
        UserDefaults.standard.set("classic", forKey: "homeMode")
    }

    @MainActor func testResponsiveFeedbackAndReadingHelp() async throws {
        let state = PlayerState()
        for phase in [SubtitleSyncPhase.analyzing, .synced, .declined, .failed] {
            state.updateSubtitleSync(phase, message: "Native feedback layout fixture")
            try await render(ZStack { Color.black; SubtitleSyncFeedback(state: state) }, size: CGSize(width: 844, height: 390), name: "subtitle-feedback-\(phase.rawValue)")
        }
        try await render(ReadingHelpView(), size: CGSize(width: 393, height: 852), name: "reading-help-phone")
    }

    @MainActor func testRTLControlsAndLocalizedContinueWatchingLayout() async throws {
        let defaults = UserDefaults.standard, previous = defaults.string(forKey: "uiLanguage")
        defer { defaults.set(previous, forKey: "uiLanguage") }
        let raw = try JSONDecoder().decode(JSONValue.self, from: Data(#"{"_id":"harbor-stable-removal-fixture","type":"movie","name":"Harbor removal fixture","removed":false,"temp":false,"_mtime":1791950000000,"state":{"timeOffset":120000,"duration":3600000}}"#.utf8))
        try await LibraryCache().save([raw], owner: "guest")
        let app = AppModel(); await app.library.setSession(nil)
        app.library.showContinuing(try XCTUnwrap(app.library.items.first))
        for code in ["en", "ar"] {
            defaults.set(code, forKey: "uiLanguage")
            XCTAssertNotEqual(DesktopInterfaceText.value("Continuar viendo"), "Continuar viendo")
            for width in [CGFloat(393), CGFloat(1024)] {
                let content = VStack(alignment: .leading, spacing: 24) {
                    HarborSettingsToggle(DesktopInterfaceText.value("Rotate featured banners automatically"), isOn: .constant(true))
                    HarborSettingsToggle(DesktopInterfaceText.value("Automatically hide controls"), isOn: .constant(false))
                    HarborSettingsSegmented(selection: .constant(true), choices: [(DesktopInterfaceText.value("Instant"), true), (DesktopInterfaceText.value("Pick a source"), false)])
                    ContinueWatching(app: app)
                }.padding(20).background(HarborTheme.background)
                    .environment(\.locale, Locale(identifier: code))
                    .environment(\.layoutDirection, code == "ar" ? .rightToLeft : .leftToRight)
                try await render(content, size: CGSize(width: width, height: 600), name: "controls-\(code)-\(Int(width))")
            }
        }
        defaults.set("classic", forKey: "homeMode")
    }

    @MainActor func testTabletResizableReadingAndPlaybackOrientation() async throws {
        XCTAssertEqual(UIDevice.current.userInterfaceIdiom, .pad, "This case runs only on the iPad simulator")
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        XCTAssertEqual(PlayerOrientation.supportedOrientations(for: window), .all)
        XCTAssertEqual(PlayerOrientation.supportedOrientations(for: nil), .all)
        let lease = PlayerOrientation.begin(in: window)
        XCTAssertEqual(PlayerOrientation.supportedOrientations(for: window), .all)
        PlayerOrientation.end(lease)
        for size in [CGSize(width: 1024, height: 1366), CGSize(width: 1366, height: 1024), CGSize(width: 390, height: 1024)] {
            try await render(ReadingHelpView(), size: size, name: "reading-help-tablet-\(Int(size.width))")
        }
    }

    @MainActor func testPDFReaderRestoresPageAfterLayoutAndNavigatesInBothDirections() async throws {
        let data = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 600, height: 800)).pdfData { context in
            for page in 1...3 { context.beginPage(); ("Reader page \(page)" as NSString).draw(at: CGPoint(x: 50, y: 50), withAttributes: [.font: UIFont.systemFont(ofSize: 24)]) }
        }
        let document = try XCTUnwrap(PDFDocument(data: data))
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first { $0.isKeyWindow }
        let window = UIWindow(windowScene: scene); window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        var current = -1
        let host = UIHostingController(rootView: PDFBookSurface(document: document, initialPage: 1, horizontal: true) { current = $0 })
        window.rootViewController = host; window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil; previous?.makeKeyAndVisible() }
        try await Task.sleep(for: .milliseconds(500)); host.view.layoutIfNeeded()
        func find(_ view: UIView) -> PDFView? { (view as? PDFView) ?? view.subviews.compactMap(find).first }
        let pdf = try XCTUnwrap(find(host.view))
        XCTAssertEqual(document.index(for: try XCTUnwrap(pdf.currentPage)), 1, "Restore only after PDFView knows its page geometry")
        XCTAssertEqual(pdf.displayDirection, .horizontal)
        XCTAssertEqual(pdf.displayMode, .singlePageContinuous, "All pages remain reachable horizontally")
        pdf.goToNextPage(nil)
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(current, 2, "Page changes must report the saved position")
        pdf.goToPreviousPage(nil)
        window.frame = CGRect(x: 0, y: 0, width: 844, height: 390)
        host.view.setNeedsLayout(); host.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(document.index(for: try XCTUnwrap(pdf.currentPage)), 1)
        let attachment = XCTAttachment(image: UIGraphicsImageRenderer(bounds: host.view.bounds).image { _ in _ = host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true) })
        attachment.name = "pdf-native-horizontal-restored-page"; attachment.lifetime = .keepAlways; add(attachment)
        host.rootView = PDFBookSurface(document: document, initialPage: 1, horizontal: false) { current = $0 }
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(pdf.displayDirection, .vertical)
        XCTAssertEqual(document.index(for: try XCTUnwrap(pdf.currentPage)), 1)
    }

    @MainActor private func render<Content: View>(_ content: Content, size: CGSize, name: String) async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first { $0.isKeyWindow }
        let window = UIWindow(windowScene: scene); window.frame = CGRect(origin: .zero, size: size)
        let host = UIHostingController(rootView: content.preferredColorScheme(.dark)); window.rootViewController = host; window.makeKeyAndVisible()
        var disposed = false
        defer { if !disposed { window.isHidden = true; window.rootViewController = nil; previous?.makeKeyAndVisible() } }
        try await Task.sleep(for: .milliseconds(450)); host.view.layoutIfNeeded()
        let image = UIGraphicsImageRenderer(bounds: host.view.bounds).image { _ in _ = host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true) }
        let attachment = XCTAttachment(image: image); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
        // Let UIKit finish hiding the host before detaching its controller.
        // Removing it in the same turn interrupts appearance forwarding.
        window.isHidden = true; previous?.makeKeyAndVisible()
        try await Task.sleep(for: .milliseconds(400))
        window.rootViewController = nil; disposed = true
    }
}

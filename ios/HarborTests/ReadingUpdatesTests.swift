import GLKit
import ImageIO
import PDFKit
import SwiftUI
import XCTest
@testable import Harbor

final class ReadingUpdatesTests: XCTestCase {
    @MainActor func testRealGutenbergSVGWrappersAndImportedCoversKeepProgress() async throws {
        let service = EBookService(), owner = "reading90-" + UUID().uuidString
        for id in [11, 84] {
            let file = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "gutenberg-\(id)", withExtension: "epub", subdirectory: "Fixtures"))
            let reader = try EPUBReader(data: Data(contentsOf: file))
            XCTAssertNotNil(reader.coverData)
            XCTAssertNotNil(try reader.blocks(reader.publication.chapters[0]).first?.image, "The original Gutenberg SVG cover must open")
            var text = ""
            for chapter in reader.publication.chapters { text += try reader.blocks(chapter).filter { $0.image == nil }.map(\.text).joined(separator: " ") }
            XCTAssertGreaterThan(text.count, 10_000, "The actual publication must remain readable beyond its cover")
            let book = try await service.importDocument(file, owner: owner)
            let shelf = EBookShelf(owner: owner)
            try shelf.addImported(book); try shelf.savePosition(book, chapter: 1, block: 0)
            let loadedCover = try await service.cover(book, owner: owner)
            let data = try XCTUnwrap(loadedCover)
            let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
            let cover = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
            XCTAssertLessThanOrEqual(max(cover.width, cover.height), 600); XCTAssertGreaterThan(min(cover.width, cover.height), 100)
            let same = try await service.importDocument(file, owner: owner)
            try shelf.addImported(same)
            XCTAssertEqual(shelf.record(same)?.chapter, 1, "Lazy cover migration and reimport preserve reading position")
            try await service.remove(book, owner: owner); try shelf.remove(book)
        }
    }

    @MainActor func testPDFMangaPagesCoversAndOwnerIsolation() async throws {
        let file = try pdf(title: "Manga Volume 2"), owner = UUID().uuidString, store = MangaLocalStore()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let book = try await store.importPDF(file, owner: owner)
        XCTAssertTrue(book.isPDF); XCTAssertEqual(book.title, "Manga Volume 2")
        let pages = try await store.pages(book, owner: owner)
        XCTAssertEqual(pages.map(\.id), [0, 1, 2])
        let chapters = try await store.chapters(book, owner: owner)
        XCTAssertEqual(chapters.first?.pages, 3)
        for page in pages {
            let data = try await store.data(book, owner: owner, path: page.path, maxPixels: 600)
            let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
            let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
            XCTAssertEqual(image.width, 450); XCTAssertEqual(image.height, 600)
            let attachment = XCTAttachment(image: UIImage(cgImage: image)); attachment.name = "manga-pdf-page-\(page.id)"; attachment.lifetime = .keepAlways; add(attachment)
        }
        do { _ = try await store.data(book, owner: owner, path: "../page-0.jpg"); XCTFail("Unsafe page identifiers must fail") } catch {}
        do { _ = try await store.pages(book, owner: owner + "-other"); XCTFail("Another owner must not open this document") } catch {}
        let shelf = MangaShelf(owner: owner)
        var record = MangaRecord(book: book); record.progress["local"] = MangaProgress(page: 1)
        try shelf.save(record)
        XCTAssertEqual(MangaShelf(owner: owner).record(book)?.progress["local"]?.page, 1)
        try shelf.remove(book); try await store.remove(book, owner: owner)
        let ebooks = EBookService(), ebook = try await ebooks.importDocument(file, owner: owner)
        let cover = try await ebooks.cover(ebook, owner: owner)
        XCTAssertNotNil(cover); try await ebooks.remove(ebook, owner: owner)
        var fields = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(book)) as? [String: Any])
        fields.removeValue(forKey: "format")
        XCTAssertFalse(try JSONDecoder().decode(MangaBook.self, from: JSONSerialization.data(withJSONObject: fields)).isPDF)
        try Data("invalid PDF".utf8).write(to: file)
        do { _ = try await store.importPDF(file, owner: owner); XCTFail("Malformed PDFs must fail before entering the shelf") } catch {}
    }

    func testNaturalShelfOrderingAndTitleAuthorSearch() {
        let titles = ["Volumen 10", "Volumen 2", "Volumen 1"]
        XCTAssertEqual(titles.sorted { ReadingShelfSort.title.before(title: $0, author: "", updated: .distantPast, id: $0, title: $1, author: "", updated: .distantPast, id: $1) }, ["Volumen 1", "Volumen 2", "Volumen 10"])
        XCTAssertTrue(ReadingShelfSort.matches("  garcia  ", title: "Cien años de soledad", author: "Gabriel García Márquez"))
        XCTAssertFalse(ReadingShelfSort.matches("Frankenstein", title: "Alicia", author: "Lewis Carroll"))
        XCTAssertTrue(ReadingShelfSort.recent.before(title: "Z", author: "", updated: .now, id: "1", title: "A", author: "", updated: .distantPast, id: "2"))
    }

    func testSkipProvidersMergeBoundsAndRealChapterFallback() throws {
        let response = try JSONDecoder().decode(JSONValue.self, from: Data(#"{"found":true,"results":[{"skipType":"op","interval":{"startTime":34.159,"endTime":124.159}},{"skipType":"ed","interval":{"startTime":1273.125,"endTime":1363.125}}]}"#.utf8))
        let anime = SkipIntroService.parseAniSkip(response)
        let chapters = SkipSegment.chapters([.init(id: 0, title: "Recap", time: 0), .init(id: 1, title: "Opening", time: 34), .init(id: 2, title: "Episode", time: 124), .init(id: 3, title: "Ending", time: 1273)], duration: 1420)
        let merged = SkipSegment.merge([anime, chapters], duration: 1420)
        XCTAssertEqual(merged.count, 3); XCTAssertEqual(merged.first?.kind, .recap)
        let intro = try XCTUnwrap(merged.first { $0.kind == .intro })
        XCTAssertEqual(intro.source, "aniskip"); XCTAssertTrue(intro.active(at: 35)); XCTAssertFalse(intro.active(at: 124))
        XCTAssertTrue(SkipSegment.merge([[.init(kind: .intro, start: .nan, end: 90, source: "invalid"), .init(kind: .intro, start: 0, end: 500, source: "invalid"), .init(kind: .outro, start: 100, end: 190, source: "invalid")]], duration: 1420).isEmpty)
        let television = try JSONDecoder().decode(JSONValue.self, from: Data(#"{"intro":[{"start_ms":10000,"end_ms":100000}],"credits":[{"start_ms":1380000,"end_ms":null}]}"#.utf8))
        XCTAssertEqual(SkipSegment.merge([SkipIntroService.parseIntroDB(television, duration: 1420)], duration: 1420).map(\.end), [100, 1420])
    }
    @MainActor func testAddedSkipPreferenceKeepsEarlierPlaybackSettings() throws {
        let name = "reading90-preferences-" + UUID().uuidString, storage = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { storage.removePersistentDomain(forName: name) }
        storage.set(try JSONSerialization.data(withJSONObject: ["seekBackSeconds": 30, "subtitleLanguage": "spa", "autoPlayNextEpisode": false]), forKey: "iphone.player-options.v1")
        let restored = PlaybackPreferences(storage: storage)
        XCTAssertEqual(restored.options.seekBackSeconds, 30); XCTAssertEqual(restored.options.subtitleLanguage, "spa"); XCTAssertFalse(restored.options.autoPlayNextEpisode)
        XCTAssertTrue(restored.options.showSkipIntro)
        restored.options.showSkipIntro = false
        XCTAssertFalse(PlaybackPreferences(storage: storage).options.showSkipIntro)
    }

    @available(iOS, deprecated: 12.0)
    @MainActor func testSkipButtonSeeksTheActualMPVWithoutReloading() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first { $0.isKeyWindow }, window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 240)
        let video = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "render-8bit", withExtension: "mp4", subdirectory: "Fixtures"))
        let state = PlayerState(), controller = MPVController(source: PlaybackSource(url: video.absoluteString, headers: nil, subtitles: nil, via: "fixture"), state: state)
        window.rootViewController = controller; window.makeKeyAndVisible(); controller.view.layoutIfNeeded()
        var disposed = false
        defer { controller.close(); if !disposed { window.isHidden = true; window.rootViewController = nil; previous?.makeKeyAndVisible() } }
        let surface = try XCTUnwrap(controller.view as? GLKView)
        let deadline = Date().addingTimeInterval(15)
        while !state.loaded && Date() < deadline { surface.display(); try await Task.sleep(for: .milliseconds(30)) }
        XCTAssertTrue(state.loaded)
        controller.set("pause", "yes")
        let paused = Date().addingTimeInterval(3)
        while !state.paused && Date() < paused { surface.display(); try await Task.sleep(for: .milliseconds(30)) }
        let segment = SkipSegment(kind: .intro, start: 0, end: min(5, state.duration - 1), source: "chapters")
        XCTAssertGreaterThanOrEqual(segment.end, 2)
        let generation = state.mediaGeneration
        PlayerSkipAction.perform(segment, state: state)
        let seek = Date().addingTimeInterval(5)
        while abs(state.position - segment.end) > 0.3 && Date() < seek { surface.display(); try await Task.sleep(for: .milliseconds(30)) }
        XCTAssertEqual(state.position, segment.end, accuracy: 0.3); XCTAssertEqual(state.mediaGeneration, generation); XCTAssertTrue(state.paused)
        let pill = UIHostingController(rootView: PlayerSkipControl(segment: segment, skip: {}, dismiss: {}).padding().background(.black))
        controller.addChild(pill); controller.view.addSubview(pill.view); pill.view.frame = CGRect(x: 0, y: 50, width: 360, height: 80); pill.didMove(toParent: controller)
        try await Task.sleep(for: .milliseconds(450))
        let image = UIGraphicsImageRenderer(bounds: controller.view.bounds).image { _ in _ = controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true) }
        let attachment = XCTAttachment(image: image); attachment.name = "actual-mpv-skip-control"; attachment.lifetime = .keepAlways; add(attachment)
        window.isHidden = true; previous?.makeKeyAndVisible(); try await Task.sleep(for: .milliseconds(400)); window.rootViewController = nil; disposed = true
    }

    @MainActor func testPrepareOrdinaryReadingShelfUIFixtures() async throws {
        let service = EBookService(), shelf = EBookShelf(owner: "guest"), mangas = MangaShelf(owner: "guest")
        let epub = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "gutenberg-11", withExtension: "epub", subdirectory: "Fixtures"))
        try shelf.addImported(try await service.importDocument(epub, owner: "guest"))
        for number in [10, 2, 1] {
            let file = try pdf(title: "Reading Volume \(number)")
            defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
            try shelf.addImported(try await service.importDocument(file, owner: "guest"))
            let book = try await MangaLocalStore.shared.importPDF(file, owner: "guest")
            try mangas.save(MangaRecord(book: book))
        }
        UserDefaults.standard.set("title", forKey: "ebook.shelfSort"); UserDefaults.standard.set("title", forKey: "manga.shelfSort")
        UserDefaults.standard.set(false, forKey: "autoRotateBanners")
    }

    @MainActor private func pdf(title: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent(title + ".pdf"), format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [kCGPDFContextTitle as String: title, kCGPDFContextAuthor as String: "Reader Fixture"]
        let data = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 600, height: 800), format: format).pdfData { context in
            for page in 0..<3 {
                context.beginPage(); UIColor(red: CGFloat(page) * 0.2 + 0.2, green: 0.25, blue: 0.65, alpha: 1).setFill(); context.cgContext.fill(CGRect(x: 0, y: 0, width: 600, height: 800))
                (title + "\nPage \(page + 1)" as NSString).draw(in: CGRect(x: 40, y: 120, width: 520, height: 250), withAttributes: [.font: UIFont.systemFont(ofSize: 42), .foregroundColor: UIColor.white])
            }
        }
        try data.write(to: file); return file
    }
}

import XCTest
@testable import Harbor

final class ReadingLiveTests: XCTestCase {
    func testGutenbergSearchEnglishSpanishAndActualBookOpening() async throws {
        let service = EBookService(), owner = "public-reader-" + UUID().uuidString
        let (english, _) = try await service.catalog(query: "Frankenstein", language: "en", page: 1)
        let book = try XCTUnwrap(english.first { $0.id == "gutendex:84" })
        let publication = try await service.open(book, owner: owner)
        XCTAssertFalse(publication.chapters.isEmpty)
        let cover = try await service.blocks(book, owner: owner, chapter: 0)
        XCTAssertNotNil(cover.first?.image)
        let text = try await service.blocks(book, owner: owner, chapter: 1)
        XCTAssertTrue(text.contains { $0.image == nil && !$0.text.isEmpty })
        try await service.remove(book, owner: owner)
        let (spanish, _) = try await service.catalog(query: "Don Quijote", language: "es", page: 1)
        XCTAssertTrue(spanish.contains { $0.id == "gutendex:2000" }, "A Spanish title must not be silently hidden by an English default")
        print("Actual Gutenberg search/open: Frankenstein 84 and Spanish Don Quijote 2000")
    }
    func testActualDanmachiEpisodeSevenAniSkipThroughKitsuMapping() async throws {
        let segments = try await SkipIntroService().segments(target: ResumeTarget(id: "kitsu:9962", season: 1, episode: 7), media: nil, duration: 1420)
        let intro = try XCTUnwrap(segments.first { $0.kind == .intro })
        XCTAssertEqual(intro.source, "aniskip"); XCTAssertGreaterThan(intro.end - intro.start, 80)
        XCTAssertTrue(intro.active(at: intro.start + 1)); XCTAssertFalse(intro.active(at: intro.end))
        print("Actual Danmachi S1E7 intro: \(intro.start)–\(intro.end) seconds")
    }
}

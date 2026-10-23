import XCTest
@testable import Harbor

final class EBookSearchTests: XCTestCase {
    func testActualJavaScriptCoreMatchesTenOriginalDiacriticAndSealedFutureSearchCases() async throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "ebook-search-reference", withExtension: "json", subdirectory: "Fixtures"))
        let fixture = try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: url))
        XCTAssertEqual(fixture["cases"].array.count, 10)
        let program = EBookSearchProgram()
        for row in fixture["cases"].array {
            let actual = try await program.apply(row["input"])
            XCTAssertEqual(actual, row["expected"], row["name"].string ?? "Search")
        }
    }
    func testSearchKeepsOriginalNoncontiguousBlockRoutesRejectsOversizedQueriesAndCancellation() async throws {
        let blocks = [EBookBlock(id: 9, text: "Passage one\n\nPassage two"), EBookBlock(id: 27, text: "Passage future"), EBookBlock(id: 99, text: "Passage picture", image: Data([1]))]
        let paragraphs = EBookSearchParagraph.make(blocks)
        XCTAssertEqual(paragraphs.map(\.block), [9, 9, 27])
        let program = EBookSearchProgram(), current = try XCTUnwrap(paragraphs.lastIndex(where: { $0.block <= 9 }))
        let sealed = try await program.search(paragraphs.map(\.text), query: "PASSAGE", current: current, revealFuture: false)
        XCTAssertEqual(sealed.shown.map(\.index), [0, 1]); XCTAssertEqual(sealed.hidden, 1)
        let revealed = try await program.search(paragraphs.map(\.text), query: "PASSAGE", current: current, revealFuture: true)
        XCTAssertEqual(revealed.shown.map { paragraphs[$0.index].block }, [9, 9, 27])
        let changed = try await program.search(paragraphs.map(\.text), query: "future", current: current, revealFuture: false)
        XCTAssertTrue(changed.shown.isEmpty); XCTAssertEqual(changed.hidden, 1)
        do { _ = try await program.search(["Text"], query: String(repeating: "x", count: 4097), current: 0, revealFuture: false); XCTFail("Oversized query must be rejected") } catch {}
        let cancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await program.search(paragraphs.map(\.text), query: "passage", current: 0, revealFuture: false)
        }
        do { _ = try await cancelled.value; XCTFail("Cancelled search must not publish a late result") } catch is CancellationError {}
    }
}

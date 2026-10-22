import CoreText
import ImageIO
import XCTest
@testable import Harbor

final class EBookPaginationTests: XCTestCase {
    private struct Fixture: Decodable {
        struct Case: Decodable {
            struct Input: Decodable { let text: String; let fontSize, lineHeight, measureFactor: Double }
            let name: String; let input: Input; let expected: EBookPrintLayout
        }
        struct Resume: Decodable { let starts: [Int]; let target, expected: Int }
        let whitespace: [UInt32]; let paper: [String: [String: String]]; let cases: [Case]; let resumeCases: [Resume]
    }
    func testNativePaginationMatchesNineOriginalLayoutsUnicodeWhitespacePaperAndFourResumeCases() throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "book-pagination-reference", withExtension: "json", subdirectory: "Fixtures"))
        let fixture = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
        XCTAssertEqual(fixture.cases.count, 9); XCTAssertEqual(fixture.resumeCases.count, 4)
        XCTAssertEqual(EBookPrintRules.whitespaceScalars, fixture.whitespace)
        for row in fixture.cases {
            let input = row.input
            let actual = try EBookPrintRules.layout(input.text, fontSize: input.fontSize, lineHeight: input.lineHeight) { Double($0.utf16.count) * input.measureFactor }
            XCTAssertEqual(actual, row.expected, row.name)
        }
        for row in fixture.resumeCases { XCTAssertEqual(EBookPrintRules.resumePage(starts: row.starts, paragraph: row.target), row.expected) }
        for (name, values) in fixture.paper {
            let paper = try XCTUnwrap(EBookPaper(rawValue: name))
            XCTAssertEqual(["desk": "#" + paper.desk, "page": "#" + paper.page, "ink": "#" + paper.ink, "muted": "#" + paper.muted], values)
        }
    }

    func testActualCoreTextDrawsReadableFullSizedPagesAndPreservesOriginalBlockRoutes() async throws {
        let renderer = EBookPageRenderer()
        let fontURL = try XCTUnwrap(Bundle.main.url(forResource: "Inter", withExtension: "ttf"))
        let font = EBookPrintFont(face: "custom", data: try Data(contentsOf: fontURL))
        let sentence = String(repeating: "Harbor page text remains readable with the imported font. ", count: 80)
        let blocks = [EBookBlock(id: 9, text: sentence), EBookBlock(id: 27, text: sentence), EBookBlock(id: 99, text: "Illustration", image: Data([1, 2, 3]))]
        let document = try await renderer.prepare(blocks: blocks, font: font, fontSize: 19, lineHeight: 1.85, paper: .dark, rtl: false, title: "Owned chapter", owner: "one")
        XCTAssertGreaterThan(document.layout.pages.count, 2); XCTAssertEqual(document.blockIDs, [9, 27])
        XCTAssertEqual(document.block(at: document.resumePage(block: 27)), 27)
        let png = try await renderer.page(document, index: 0)
        let source = try XCTUnwrap(CGImageSourceCreateWithData(png as CFData, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        XCTAssertEqual(image.width, 1200); XCTAssertEqual(image.height, 1600)
        let crop = try XCTUnwrap(image.cropping(to: CGRect(x: 400, y: 250, width: 500, height: 600)))
        var pixels = [UInt8](repeating: 0, count: 500 * 600 * 4)
        try pixels.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(CGContext(data: buffer.baseAddress, width: 500, height: 600, bitsPerComponent: 8, bytesPerRow: 2000, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
            context.draw(crop, in: CGRect(x: 0, y: 0, width: 500, height: 600))
        }
        var readableInk = 0
        for offset in stride(from: 0, to: pixels.count, by: 4) { if pixels[offset] > 100 && pixels[offset + 1] > 100 && pixels[offset + 2] > 100 { readableInk += 1 } }
        XCTAssertGreaterThan(readableInk, 100, "Text must draw inside the body; the footer and gutter are outside this crop")
        let other = try await renderer.prepare(blocks: blocks, font: font, fontSize: 19, lineHeight: 1.85, paper: .dark, rtl: false, title: "Owned chapter", owner: "two")
        XCTAssertNotEqual(document.id, other.id, "Pages from separate owners must not share a cache identity")
    }

    func testInvalidMetricsFontsAndCancelledEmptyChaptersNeverPublishAPage() async throws {
        for size in [Double.nan, .infinity, 0, -1] {
            XCTAssertThrowsError(try EBookPrintRules.layout("Text", fontSize: size, lineHeight: 1.85, measure: { Double($0.count) }))
        }
        let renderer = EBookPageRenderer(), invalid = EBookPrintFont(face: "custom", data: Data([1, 2, 3]))
        do {
            _ = try await renderer.prepare(blocks: [.init(id: 0, text: "Text")], font: invalid, fontSize: 19, lineHeight: 1.85, paper: .dark, rtl: false, title: "Invalid", owner: "owned")
            XCTFail("Invalid fonts must not produce fallback pages")
        } catch {}
        let cancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try EBookPrintRules.layout("", fontSize: 19, lineHeight: 1.85, measure: { Double($0.count) })
        }
        do { _ = try await cancelled.value; XCTFail("A cancelled empty chapter must not publish a layout") } catch is CancellationError {}
    }
}

private struct BookPaginationNetwork: HarborNativeNetworkCalling {
    func perform(_ request: HarborNetworkRequest) async throws -> HarborNetworkResponse {
        let text: String
        if request.url.hasSuffix("repo.json") {
            text = #"{"type":"ebook","plugins":[{"id":"owned.pages","name":"Owned pagination","entry":"book.js","lang":"en"}]}"#
        } else if request.url.hasSuffix("book.js") {
            text = #"var plugin={id:'owned.pages',name:'Owned pagination',popular:function(){return [{id:'owned',title:'Owned paginated book'}];},chapters:function(){return [{id:'one',title:'Chapter one'}];},content:function(){return Array.from({length:60},function(_,i){return 'Paragraph '+i+'. '+('Harbor pages keep this real chapter readable and preserve the original paragraph. ').repeat(5);}).join('\n\n');}};"#
        } else { throw HarborPluginRepositoryError("owned-pagination-route") }
        return .init(status: 200, ok: true, headers: [:], bodyBase64: Data(text.utf8).base64EncodedString(), url: request.url)
    }
}

final class BookPaginationInterfaceSeedTests: XCTestCase {
    @MainActor func testPrepareOwnedPaginatedBookInTheOrdinaryFreshGuest() async throws {
        guard try KeychainStore().read("account.v1", as: JSONValue.self) == nil else { XCTFail("Refuse configured account"); return }
        let context = AppProfileContext.shared; try context.prepare()
        guard context.profiles.profiles.count == 1, context.profiles.active?.credential == nil,
              context.configuration?.account == nil, let owner = context.binding?.personalOwner else { XCTFail("Refuse configured profiles"); return }
        if context.configuration?.guestAddons == nil { try context.save(HouseholdSourceAccount(account: nil, guestAddons: [])) }
        let store = try HarborReadingPluginStore(), saved = try await store.load()
        guard saved.plugins.isEmpty, saved.repositories.isEmpty else { XCTFail("Refuse existing sources"); return }
        let scope = PluginExecutionScope(owner: owner, activation: UUID())
        let manager = HarborReadingPluginManager(scope: scope, currentScope: { scope }, store: store, network: BookPaginationNetwork())
        defer { manager.dispose() }; try await manager.load()
        try await manager.addRepository("https://example.org/paged/repo.json", kind: .ebook)
        let repository = try XCTUnwrap(manager.document.repositories.first)
        try await manager.install(XCTUnwrap(repository.entries.first), repository: repository)
        XCTAssertEqual(manager.document.plugins.count, 1)
        let defaults = UserDefaults.standard
        defaults.set("en", forKey: "uiLanguage"); defaults.set(false, forKey: "interface.autoRotateBanners")
        defaults.set(true, forKey: "nativeGuide.initialized.v1"); defaults.set(true, forKey: "nativeGuide.completed.v1")
        defaults.set("harbor", forKey: "ebook.mode"); defaults.set(false, forKey: "ebook.focusMode")
    }
}

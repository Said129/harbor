import CoreText
import XCTest
@testable import Harbor

final class ReadingWebFontInterfaceSeedTests: XCTestCase {
    @MainActor func testPrepareBothOwnedWebFontsInTheOrdinaryFreshGuestReader() async throws {
        try await EBookDetailInterfaceSeedTests.prepare()
        let owner = try XCTUnwrap(AppProfileContext.shared.binding?.personalOwner)
        for format in ["woff", "woff2"] {
            let file = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "owned-reader-" + format, withExtension: format, subdirectory: "Fixtures"))
            let value = try await ReadingFontStore.shared.importFont(file, owner: owner)
            XCTAssertEqual(value.format, format)
        }
        let fonts = try await ReadingFontStore.shared.list(owner: owner)
        XCTAssertEqual(Set(fonts.map(\.format)), ["woff", "woff2"])
        let inter = try XCTUnwrap(Bundle.main.url(forResource: "Inter", withExtension: "ttf"))
        _ = try await ReadingFontStore.shared.importFont(inter, owner: owner)
    }
}

final class ReadingWebFontTests: XCTestCase {
    func testActualWOFFAndTransformedWOFF2PreserveNamesGlyphsMetricsAndRenderedPixels() async throws {
        let notice = try XCTUnwrap(Bundle.main.url(forResource: "ReadingFontNotices", withExtension: "txt"))
        XCTAssertTrue(try String(contentsOf: notice, encoding: .utf8).contains("Copyright (c) 2016 Dropbox, Inc."))
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("reading-web-font-" + UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let store = ReadingFontStore(root: root)
        for format in ["woff", "woff2"] {
            let file = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "owned-reader-" + format, withExtension: format, subdirectory: "Fixtures"))
            let original = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "owned-reader-" + format, withExtension: "ttf", subdirectory: "Fixtures"))
            let imported = try await store.importFont(file, owner: "owned")
            XCTAssertEqual(imported.format, format)
            let data = try await ReadingFontStore(root: root).data(id: imported.id, owner: "owned")
            let actual = try font(data), reference = try font(Data(contentsOf: original))
            XCTAssertEqual(CTFontCopyPostScriptName(actual) as String, "HarborOwned-" + format)
            let result = glyphs(actual), expected = glyphs(reference)
            XCTAssertEqual(result.0, expected.0); XCTAssertEqual(result.1, expected.1)
            let context = try XCTUnwrap(CGContext(data: nil, width: 400, height: 100, bitsPerComponent: 8, bytesPerRow: 1600, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.clear(CGRect(x: 0, y: 0, width: 400, height: 100)); context.setFillColor(CGColor(gray: 1, alpha: 1))
            var positions = result.0.indices.map { CGPoint(x: 10 + $0 * 28, y: 30) }
            CTFontDrawGlyphs(actual, result.0, &positions, result.0.count, context)
            let bitmap = try XCTUnwrap(context.makeImage()?.dataProvider?.data)
            XCTAssertTrue((bitmap as Data).contains { $0 != 0 }, "The converted font must actually draw glyph pixels")
        }
    }
    func testMalformedAndInflatedWebFontsDoNotPublishOrDamageTheExistingFont() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("reading-web-font-invalid-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let store = ReadingFontStore(root: root.appendingPathComponent("store"))
        let valid = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "owned-reader-woff2", withExtension: "woff2", subdirectory: "Fixtures"))
        let imported = try await store.importFont(valid, owner: "owned")
        let before = try await store.data(id: imported.id, owner: "owned")
        for format in ["woff", "woff2"] {
            var data = Data(repeating: 0, count: 48)
            data.replaceSubrange(0..<4, with: Data((format == "woff" ? "wOFF" : "wOF2").utf8))
            data[11] = 48; data[13] = 1; data.replaceSubrange(16..<20, with: [255, 255, 255, 255])
            let file = root.appendingPathComponent("invalid." + format); try data.write(to: file)
            do { _ = try await store.importFont(file, owner: "owned"); XCTFail("Inflated web font must be rejected before allocation") } catch {}
        }
        let rows = try await store.list(owner: "owned"); XCTAssertEqual(rows.map(\.id), [imported.id])
        let after = try await store.data(id: imported.id, owner: "owned"); XCTAssertEqual(after, before)
    }
    private func font(_ data: Data) throws -> CTFont {
        let provider = try XCTUnwrap(CGDataProvider(data: data as CFData)), graphic = try XCTUnwrap(CGFont(provider))
        return CTFontCreateWithGraphicsFont(graphic, 24, nil, nil)
    }
    private func glyphs(_ font: CTFont) -> ([CGGlyph], [CGSize]) {
        let characters = Array("Harbor ABñé".utf16)
        var glyphs = Array(repeating: CGGlyph(0), count: characters.count), advances = Array(repeating: CGSize.zero, count: characters.count)
        XCTAssertTrue(CTFontGetGlyphsForCharacters(font, characters, &glyphs, characters.count))
        _ = CTFontGetAdvancesForGlyphs(font, .horizontal, glyphs, &advances, glyphs.count)
        return (glyphs, advances)
    }
}

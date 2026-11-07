import XCTest
@testable import Harbor

final class ThemeLibraryTests: XCTestCase {
    private func sampleTokens(accent: String = "#7b5cff") -> [String: [Double]] {
        var tokens: [String: [Double]] = [:]
        for token in ThemeTokenNames.all {
            tokens[token] = ThemeColorCodec.parse("#102030") ?? []
        }
        tokens["accent"] = ThemeColorCodec.parse(accent) ?? []
        return tokens
    }

    private func themeObject(name: String = "Night Sea") -> [String: Any] {
        var colors: [String: String] = [:]
        for token in ThemeTokenNames.all {
            colors["--color-" + token] = "#102030"
        }
        return [
            "name": name,
            "blurb": "Calm",
            "swatch": ["#0a0d14", "#181d28", "#7b5cff"],
            "tokens": colors,
        ]
    }

    private func jsonData(_ object: Any) throws -> Data {
        try JSONSerialization.data(withJSONObject: object)
    }

    private func failure(_ data: Data) -> ThemeFileError? {
        if case .failure(let error) = ThemeFileCodec.decode(data) { return error }
        return nil
    }

    private func pngBase64() -> String {
        let bytes = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        return "data:image/png;base64," + bytes.base64EncodedString()
    }

    func testExportThenImportRoundTripsNameTokensAndBackground() throws {
        let entry = try ThemeLibrary.makeEntry(
            name: "Night Sea", blurb: "Calm", tokens: sampleTokens(accent: "#7b5cff80"),
            hasBackground: true, backgroundDim: 0.4, id: "entry-1")
        let image = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A])
        let exported = try ThemeFileCodec.encode(entry, imageData: image)
        let imported = try ThemeFileCodec.decode(exported).get()
        XCTAssertEqual(imported.name, "Night Sea")
        XCTAssertEqual(imported.blurb, "Calm")
        XCTAssertEqual(imported.tokens, entry.tokens)
        XCTAssertEqual(imported.tokens["accent"], ThemeColorCodec.parse("#7b5cff80"))
        XCTAssertEqual(imported.background?.imageData, image)
        XCTAssertEqual(imported.background?.dim, 0.4)
    }

    func testEncodedJSONUsesDesktopKeysAndOmitsBackgroundWhenAbsent() throws {
        let entry = try ThemeLibrary.makeEntry(
            name: "Plain", tokens: sampleTokens(), hasBackground: false, backgroundDim: 0.65, id: "plain")
        let exported = try ThemeFileCodec.encode(entry, imageData: nil)
        let object = try JSONSerialization.jsonObject(with: exported) as? [String: Any]
        XCTAssertEqual(object?["name"] as? String, "Plain")
        XCTAssertNil(object?["background"])
        let colors = object?["tokens"] as? [String: String]
        XCTAssertEqual(colors?["--color-accent"], "#7b5cff")
        XCTAssertEqual(colors?.count, 12)
    }

    func testDecodeRejectsUnreadableAndNonObjectFiles() {
        XCTAssertEqual(failure(Data("not json".utf8)), ThemeFileError.unreadable)
        XCTAssertEqual(failure(Data("[1,2]".utf8)), ThemeFileError.notATheme)
    }

    func testDecodeRejectsMissingNameAndBadSwatch() throws {
        XCTAssertEqual(failure(try jsonData(themeObject(name: "   "))), ThemeFileError.missingName)
        var badSwatch = themeObject()
        badSwatch["swatch"] = ["#000", "#111", "#222"]
        XCTAssertEqual(failure(try jsonData(badSwatch)), ThemeFileError.invalidSwatch)
    }

    func testDecodeReportsTheMissingColorByDesktopKey() throws {
        var object = themeObject()
        var colors = object["tokens"] as? [String: String] ?? [:]
        colors["--color-accent"] = nil
        object["tokens"] = colors
        XCTAssertEqual(failure(try jsonData(object)), ThemeFileError.missingColor("--color-accent"))
        var noTokens = themeObject()
        noTokens["tokens"] = nil
        XCTAssertEqual(failure(try jsonData(noTokens)), ThemeFileError.missingColors)
    }

    func testDecodeIgnoresDesktopOnlyFieldsAndCodeContent() throws {
        var object = themeObject()
        object["css"] = ".x { color: red }"
        object["js"] = "alert(1)"
        object["html"] = "<b>x</b>"
        object["layout"] = "sidebar"
        object["logo"] = ["wordmark": "data:image/svg+xml;base64,AAAA"]
        let imported = try ThemeFileCodec.decode(try jsonData(object)).get()
        XCTAssertEqual(imported.name, "Night Sea")
        XCTAssertNil(imported.background)
        XCTAssertEqual(imported.tokens.count, 12)
    }

    func testRemoteAndSVGBackgroundsAreDroppedAndBadDimFallsBackToDefault() throws {
        var remote = themeObject()
        remote["background"] = ["image": "https://example.com/a.png", "dim": 0.3]
        XCTAssertNil(try ThemeFileCodec.decode(try jsonData(remote)).get().background)

        var svg = themeObject()
        svg["background"] = ["image": "data:image/svg+xml;base64,PHN2Zy8+", "dim": 0.3]
        XCTAssertNil(try ThemeFileCodec.decode(try jsonData(svg)).get().background)

        var outOfRange = themeObject()
        outOfRange["background"] = ["image": pngBase64(), "dim": 1.5]
        let fallback = try ThemeFileCodec.decode(try jsonData(outOfRange)).get().background
        XCTAssertEqual(fallback?.dim, ThemeBackgroundDefaults.dim)

        var valid = themeObject()
        valid["background"] = ["image": pngBase64(), "dim": 0.25]
        XCTAssertEqual(try ThemeFileCodec.decode(try jsonData(valid)).get().background?.dim, 0.25)
    }

    func testNameAndBlurbAreClampedToDesktopLengths() throws {
        var object = themeObject(name: String(repeating: "a", count: 80))
        object["blurb"] = String(repeating: "b", count: 200)
        let imported = try ThemeFileCodec.decode(try jsonData(object)).get()
        XCTAssertEqual(imported.name.count, 60)
        XCTAssertEqual(imported.blurb.count, 160)
    }

    func testColorParsingSupportsHexRGBAndOKLCHOnly() throws {
        XCTAssertEqual(ThemeColorCodec.parse("#102030"), [16.0 / 255, 32.0 / 255, 48.0 / 255, 1])
        XCTAssertEqual(ThemeColorCodec.parse("rgb(255 0 0 / 50%)"), [1, 0, 0, 0.5])
        XCTAssertEqual(ThemeColorCodec.parse("rgba(0, 0, 255, 0.25)"), [0, 0, 1, 0.25])
        let white = try XCTUnwrap(ThemeColorCodec.parse("oklch(1 0 0)"))
        for (actual, expected) in zip(white, [1.0, 1.0, 1.0, 1.0]) {
            XCTAssertEqual(actual, expected, accuracy: 0.001)
        }
        let dark = try XCTUnwrap(ThemeColorCodec.parse("oklch(0.18 0.004 260)"))
        XCTAssertTrue(ThemeColorCodec.isValidRGBA(dark))
        XCTAssertNil(ThemeColorCodec.parse("hsl(0 0% 0%)"))
        XCTAssertNil(ThemeColorCodec.parse("#abc"))
        XCTAssertNil(ThemeColorCodec.parse("#zzzzzz"))
    }

    func testHexEncodingWritesAlphaOnlyWhenTransparent() {
        XCTAssertEqual(ThemeColorCodec.hex([1, 0, 0, 0.5]), "#ff000080")
        XCTAssertEqual(ThemeColorCodec.hex([0, 0, 0, 1]), "#000000")
        XCTAssertEqual(ThemeColorCodec.hex([16.0 / 255, 32.0 / 255, 48.0 / 255, 1]), "#102030")
    }

    func testLibraryCRUDSavesReplacesRemovesAndFinds() throws {
        var library = ThemeLibrary()
        let first = try ThemeLibrary.makeEntry(name: "One", tokens: sampleTokens(), hasBackground: false, backgroundDim: 0.65, id: "a")
        let second = try ThemeLibrary.makeEntry(name: "Two", tokens: sampleTokens(), hasBackground: false, backgroundDim: 0.65, id: "b")
        library.save(first)
        library.save(second)
        XCTAssertEqual(library.entries.map(\.id), ["a", "b"])

        var renamed = first
        renamed.name = "One renamed"
        library.save(renamed)
        XCTAssertEqual(library.entries.count, 2)
        XCTAssertEqual(library.entry(id: "a")?.name, "One renamed")

        library.remove(id: "a")
        XCTAssertEqual(library.entries.map(\.id), ["b"])
        XCTAssertNil(library.entry(id: "a"))
    }

    func testRenameTrimsClampsAndRejectsEmptyNames() throws {
        var library = ThemeLibrary()
        library.save(try ThemeLibrary.makeEntry(name: "Old", tokens: sampleTokens(), hasBackground: false, backgroundDim: 0.65, id: "r"))
        try library.rename(id: "r", to: "  New name  ")
        XCTAssertEqual(library.entry(id: "r")?.name, "New name")
        try library.rename(id: "r", to: String(repeating: "x", count: 90))
        XCTAssertEqual(library.entry(id: "r")?.name.count, 60)
        XCTAssertThrowsError(try library.rename(id: "r", to: "   ")) { error in
            XCTAssertEqual(error as? ThemeFileError, ThemeFileError.missingName)
        }
        XCTAssertEqual(library.entry(id: "r")?.name.count, 60)
        try library.rename(id: "missing", to: "Ignored")
        XCTAssertEqual(library.entries.count, 1)
    }

    func testMakeEntryRequiresNameAndEveryColorAndClampsDim() throws {
        XCTAssertThrowsError(try ThemeLibrary.makeEntry(name: "  ", tokens: sampleTokens(), hasBackground: false, backgroundDim: 0.5)) { error in
            XCTAssertEqual(error as? ThemeFileError, ThemeFileError.missingName)
        }
        var incomplete = sampleTokens()
        incomplete["danger"] = nil
        XCTAssertThrowsError(try ThemeLibrary.makeEntry(name: "X", tokens: incomplete, hasBackground: false, backgroundDim: 0.5)) { error in
            XCTAssertEqual(error as? ThemeFileError, ThemeFileError.missingColor("--color-danger"))
        }
        let high = try ThemeLibrary.makeEntry(name: "  Night  ", tokens: sampleTokens(), hasBackground: true, backgroundDim: 2)
        XCTAssertEqual(high.name, "Night")
        XCTAssertEqual(high.backgroundDim, 1)
        let low = try ThemeLibrary.makeEntry(name: "Low", tokens: sampleTokens(), hasBackground: true, backgroundDim: -1)
        XCTAssertEqual(low.backgroundDim, 0)
    }

    func testRestoredDropsInvalidEntriesAndKeepsValidOnes() throws {
        let valid = try ThemeLibrary.makeEntry(name: "Valid", tokens: sampleTokens(), hasBackground: false, backgroundDim: 0.65, id: "valid")
        let invalid = ThemeLibraryEntry(id: "bad", name: "Bad", blurb: "", tokens: [:], hasBackground: false, backgroundDim: 0.65)
        let data = try JSONEncoder().encode(ThemeLibrary(entries: [valid, invalid]))
        XCTAssertEqual(ThemeLibrary.restored(from: data).entries.map(\.id), ["valid"])
        XCTAssertTrue(ThemeLibrary.restored(from: nil).entries.isEmpty)
        XCTAssertTrue(ThemeLibrary.restored(from: Data("oops".utf8)).entries.isEmpty)
    }

    func testFileNameFollowsDesktopExportRule() {
        XCTAssertEqual(ThemeFileCodec.fileName(for: "Cool Theme"), "cool-theme.json")
        XCTAssertEqual(ThemeFileCodec.fileName(for: "night_sea-2"), "night_sea-2.json")
    }
}

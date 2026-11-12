import XCTest
@testable import Harbor

/// F11 B199: the Arabic word-list term of Desktop's `encoding.ts` now takes part in picking a legacy code page.
final class F11EncodingTests: XCTestCase {
    private let marhaba = "\u{0645}\u{0631}\u{062D}\u{0628}\u{0627}"
    private let bilAlam = "\u{0628}\u{0627}\u{0644}\u{0639}\u{0627}\u{0644}\u{0645}"

    func testAKnownArabicWordScoresOne() {
        XCTAssertEqual(SubtitleArabicPlausibility.score(marhaba), 1.0, accuracy: 1e-9)
    }

    func testTextWithoutArabicWordsScoresZero() {
        XCTAssertEqual(SubtitleArabicPlausibility.score(""), 0, accuracy: 1e-9)
        XCTAssertEqual(SubtitleArabicPlausibility.score("Hello world"), 0, accuracy: 1e-9)
        // One Arabic letter is not a word (Desktop needs two or more).
        XCTAssertEqual(SubtitleArabicPlausibility.score("\u{0628} \u{062C}"), 0, accuracy: 1e-9)
    }

    func testAnUnknownWordWithNoCommonPairScoresZero() {
        XCTAssertEqual(SubtitleArabicPlausibility.score("\u{0628}\u{062C}\u{062F}"), 0, accuracy: 1e-9)
    }

    func testVowelMarksAndTatweelAreStrippedBeforeCounting() {
        let marked = "\u{0645}\u{064E}\u{0631}\u{0652}\u{062D}\u{064E}\u{0628}\u{064B}\u{0627}"
        XCTAssertEqual(SubtitleArabicPlausibility.score(marked), 1.0, accuracy: 1e-9)
        let stretched = "\u{0645}\u{0631}\u{062D}\u{0640}\u{0640}\u{0628}\u{0627}"
        XCTAssertEqual(SubtitleArabicPlausibility.score(stretched), 1.0, accuracy: 1e-9)
    }

    func testTheShareOfKnownWordsDrivesMostOfTheScore() {
        // One known word and one unknown word: share 0.5 gives 0.35, plus up to 0.3 for the letter pairs.
        let value = SubtitleArabicPlausibility.score(marhaba + " \u{0628}\u{062C}\u{062F}")
        XCTAssertGreaterThanOrEqual(value, 0.35)
        XCTAssertLessThan(value, 0.66)
    }

    func testWindows1256BytesDecodeToArabicWhenTheLanguageIsArabic() throws {
        // "marhaba bil-alam" in Windows-1256. The same bytes are also valid in the other single-byte tables, with different letters.
        let bytes: [UInt8] = [0xE3, 0xD1, 0xCD, 0xC8, 0xC7, 0x20, 0xC8, 0xC7, 0xE1, 0xDA, 0xC7, 0xE1, 0xE3, 0x0A]
        let converted = try XCTUnwrap(SubtitleTextEncoding.convertedUTF8(Data(bytes), language: "ar"))
        let text = try XCTUnwrap(String(data: converted, encoding: .utf8))
        XCTAssertEqual(text, marhaba + " " + bilAlam + "\n")
    }

    func testValidUTF8IsKeptByteForByte() {
        XCTAssertNil(SubtitleTextEncoding.convertedUTF8(Data((marhaba + "\n").utf8), language: "ar"))
        XCTAssertNil(SubtitleTextEncoding.convertedUTF8(Data("1\n00:00:01,000 --> 00:00:02,000\nHola\n".utf8), language: "es"))
    }

    func testArabicLanguageTriesTheArabicCodePagesFirst() {
        XCTAssertEqual(SubtitleTextEncoding.legacyEncodings(language: "ar"), ["windows-1256", "iso-8859-6", "windows-1252"])
        XCTAssertEqual(SubtitleTextEncoding.legacyEncodings(language: "es"), ["windows-1252", "windows-1256", "iso-8859-6"])
    }
}

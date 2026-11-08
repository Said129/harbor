import XCTest
@testable import Harbor

/// The G5 player and subtitle helpers (seek-bar fill, subtitle text encoding, hide-SDH gate, truncated-end rule), checked without mpv or the network.
final class G5PlayerTests: XCTestCase {
    func testCacheFillClampsToTheTimeline() {
        XCTAssertEqual(PlaybackCacheFill.fraction(cacheEnd: nil, duration: 60), 0)
        XCTAssertEqual(PlaybackCacheFill.fraction(cacheEnd: 30, duration: 60), 0.5, accuracy: 0.0001)
        XCTAssertEqual(PlaybackCacheFill.fraction(cacheEnd: 90, duration: 60), 1)
        XCTAssertEqual(PlaybackCacheFill.fraction(cacheEnd: -5, duration: 60), 0)
        XCTAssertEqual(PlaybackCacheFill.fraction(cacheEnd: 30, duration: 0), 0)
        XCTAssertEqual(PlaybackCacheFill.fraction(cacheEnd: .nan, duration: 60), 0)
    }

    func testUTF8IsLeftAlone() {
        XCTAssertNil(SubtitleTextEncoding.convertedUTF8(Data("Hola, mundo\n".utf8), language: nil))
        XCTAssertNil(SubtitleTextEncoding.convertedUTF8(Data("café\n".utf8), language: "fr"))
        XCTAssertNil(SubtitleTextEncoding.convertedUTF8(Data([0xEF, 0xBB, 0xBF]) + Data("Hi".utf8), language: nil))
    }

    func testUTF16ByteOrderMarkConvertsToUTF8() {
        let littleEndian = Data([0xFF, 0xFE, 0x48, 0x00, 0x69, 0x00])
        let bigEndian = Data([0xFE, 0xFF, 0x00, 0x48, 0x00, 0x69])
        XCTAssertEqual(SubtitleTextEncoding.convertedUTF8(littleEndian, language: nil), Data("Hi".utf8))
        XCTAssertEqual(SubtitleTextEncoding.convertedUTF8(bigEndian, language: nil), Data("Hi".utf8))
    }

    func testLegacyLatinBytesBecomeUTF8() {
        // "café" in windows-1252: the 0xE9 byte is not valid UTF-8, and a declared French language rules out the Arabic code pages.
        let legacy = Data([0x63, 0x61, 0x66, 0xE9])
        XCTAssertEqual(SubtitleTextEncoding.convertedUTF8(legacy, language: "fr"), Data("café".utf8))
    }

    func testSDHGateFollowsDesktopRules() {
        XCTAssertTrue(SubtitleSDHGate.allows(forced: false, foreignOnly: false, language: "eng"))
        XCTAssertTrue(SubtitleSDHGate.allows(forced: false, foreignOnly: false, language: ""))
        XCTAssertTrue(SubtitleSDHGate.allows(forced: false, foreignOnly: false, language: nil))
        XCTAssertTrue(SubtitleSDHGate.allows(forced: false, foreignOnly: false, language: "spa"))
        XCTAssertFalse(SubtitleSDHGate.allows(forced: true, foreignOnly: false, language: "eng"))
        XCTAssertFalse(SubtitleSDHGate.allows(forced: false, foreignOnly: true, language: "eng"))
        XCTAssertFalse(SubtitleSDHGate.allows(forced: false, foreignOnly: false, language: "ar-EG"))
        XCTAssertFalse(SubtitleSDHGate.allows(forced: false, foreignOnly: false, language: "ja"))
    }

    func testTruncatedEndUsesTheEightyFivePercentRule() {
        XCTAssertFalse(PlaybackEndRule.isTruncatedEnd(position: 85, duration: 100))
        XCTAssertTrue(PlaybackEndRule.isTruncatedEnd(position: 84.9, duration: 100))
        XCTAssertFalse(PlaybackEndRule.isTruncatedEnd(position: 10, duration: 0))
        XCTAssertTrue(PlaybackEndRule.isNaturalEnd(position: 10, duration: 0))
    }
}

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

    func testProviderSubtitleArchiveSelectsEpisodeAndLanguageAndRejectsUnsafePaths() throws {
        // Deflated subtitle fixtures with two competing tracks and a separate traversal entry.
        let valid = try XCTUnwrap(Data(base64Encoded: """
        UEsDBBQAAAAIAAAAIQDwsIk5JgAAAC4AAAASAAAAU2hvdy5TMDFFMDYuZXMuc3J0M+QyMLACIUMdAwMDBV1dOwWogBFIgCu8KD
        8vXSG1ILM4PyWVCwBQSwMEFAAAAAgAAAAhAMVYbjInAAAALwAAABIAAABTaG93LlMwMUUwNy5lbi5zcnQz5DIwsAIhQx0DAwMF
        XV07BaiAEUiAK7woPy9dIScxL700MT2VCwBQSwMEFAAAAAgAAAAhAJlpf1gkAAAALAAAABIAAABTaG93LlMwMUUwNy5lcy5zcn
        Qz5DIwsAIhQx0DAwMFXV07BaiAEUiAyydRITm/qCg1uSSRCwBQSwECFAAUAAAACAAAACEA8LCJOSYAAAAuAAAAEgAAAAAAAAAA
        AAAAgAEAAAAAU2hvdy5TMDFFMDYuZXMuc3J0UEsBAhQAFAAAAAgAAAAhAMVYbjInAAAALwAAABIAAAAAAAAAAAAAAIABVgAAAF
        Nob3cuUzAxRTA3LmVuLnNydFBLAQIUABQAAAAIAAAAIQCZaX9YJAAAACwAAAASAAAAAAAAAAAAAACAAa0AAABTaG93LlMwMUUw
        Ny5lcy5zcnRQSwUGAAAAAAMAAwDAAAAAAQEAAAAA
        """, options: .ignoreUnknownCharacters))
        let unsafe = try XCTUnwrap(Data(base64Encoded: """
        UEsDBBQAAAAIAAAAIQAP6KT2HwAAACcAAAANAAAALi4vZXNjYXBlLnNydDPkMjCwAiFDHQMDAwVdXTsFqIARSIArNK84MS2VCw
        BQSwECFAAUAAAACAAAACEAD+ik9h8AAAAnAAAADQAAAAAAAAAAAAAAgAEAAAAALi4vZXNjYXBlLnNydFBLBQYAAAAAAQABADsA
        AABKAAAAAAA=
        """, options: .ignoreUnknownCharacters))
        let context = SubtitleProviderDownload(owner: "fixture", provider: .subdl, requiresKey: false,
            season: 1, episode: 7, release: nil, filename: nil)

        let subtitle = try ProviderSubtitleArchive.extract(valid, language: "es", context: context)
        XCTAssertEqual(subtitle.ext, "srt")
        XCTAssertTrue(String(decoding: subtitle.data, as: UTF8.self).contains("La correcta"))
        XCTAssertThrowsError(try ProviderSubtitleArchive.extract(unsafe, language: "es", context: context))
    }

    func testBuiltInOpenSubtitlesStepsAsideOnlyForAnEnabledSubtitleAddon() {
        let manifest: JSONValue = .object([
            "id": .string("com.opensubtitles.v3"), "resources": .array([.string("subtitles")])
        ])
        let configured = Addon(manifest: manifest, transportUrl: "https://opensubtitles-v3.strem.io/manifest.json", enabled: true)
        let disabled = Addon(manifest: manifest, transportUrl: configured.transportUrl, enabled: false)
        let enabled: Set<SubtitleProviderID> = [.opensubtitles, .subsource]
        XCTAssertEqual(OptionalSubtitleProviders.directProviders(enabled, addons: []), enabled)
        XCTAssertEqual(OptionalSubtitleProviders.directProviders(enabled, addons: [disabled]), enabled)
        XCTAssertEqual(OptionalSubtitleProviders.directProviders(enabled, addons: [configured]), [.subsource])
    }

    func testOnlyInMemorySubsourceDownloadGetsAnExactOriginCredential() throws {
        let context = SubtitleProviderDownload(owner: "fixture", provider: .subsource, requiresKey: true,
            season: nil, episode: nil, release: nil, filename: nil)
        let trusted = PlaybackSource.Subtitle(url: "https://api.subsource.net/api/v1/subtitles/abc-123/download",
            lang: "es", id: "subsource:abc-123", providerDownload: context)
        XCTAssertEqual(try SubtitleFileService.providerRequest(trusted, key: "fixture-key").value(forHTTPHeaderField: "X-API-Key"), "fixture-key")
        XCTAssertThrowsError(try SubtitleFileService.providerRequest(trusted, key: nil))

        for url in ["https://example.test/api/v1/subtitles/abc/download",
                    "https://api.subsource.net:8443/api/v1/subtitles/abc/download",
                    "https://api.subsource.net/api/v1/subtitles/abc/download?redirect=1"] {
            let other = PlaybackSource.Subtitle(url: url, lang: nil, id: nil, providerDownload: context)
            XCTAssertThrowsError(try SubtitleFileService.providerRequest(other, key: "fixture-key"))
        }

        let decoded = try JSONDecoder().decode(PlaybackSource.Subtitle.self, from: JSONEncoder().encode(trusted))
        XCTAssertNil(decoded.providerDownload)
        XCTAssertNil(try SubtitleFileService.providerRequest(decoded, key: "fixture-key").value(forHTTPHeaderField: "X-API-Key"))
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

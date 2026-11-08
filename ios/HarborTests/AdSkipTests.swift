import CryptoKit
import Foundation
import XCTest
@testable import Harbor

final class AdSkipTests: XCTestCase {
    private func signedDocument(_ payload: String, with key: Curve25519.Signing.PrivateKey) throws -> JSONValue {
        let signature = try key.signature(for: Data(payload.utf8)).base64EncodedString()
        return .object(["payload": .string(payload), "sig": .string(signature)])
    }

    private let corpusPayload = #"[{"content":"tt0000001","source":"ih_abcdef_0","ranges":[{"start":10,"end":40},{"start":50,"end":50},{"start":70,"end":60}]},{"content":"tt0000001","source":"rg_grp_1000_title","ranges":[{"start":5,"end":9}]},{"content":"tt0000002","source":"ih_abcdef_0","ranges":[{"start":1,"end":2}]}]"#

    // MARK: Fingerprint (`fingerprint.ts`)

    func testContentKeyUsesImdbOnlyWhenItIsATitleId() {
        XCTAssertEqual(AdSkipFingerprint.contentKey(metaID: "kitsu:1", imdbID: "tt0123456"), "tt0123456")
        XCTAssertEqual(AdSkipFingerprint.contentKey(metaID: "tmdb:movie:9", imdbID: "nm0001"), "tmdb:movie:9")
        XCTAssertEqual(AdSkipFingerprint.contentKey(metaID: "tt7", imdbID: nil), "tt7")
    }

    func testSourceKeyUsesTheInfoHashAndFileIndex() {
        XCTAssertEqual(AdSkipFingerprint.sourceKey(infoHash: "ABCdef", fileIdx: 2, releaseGroup: "grp", size: 9, parsedTitle: "t", url: "https://a.b/c"), "ih_abcdef_2")
        XCTAssertEqual(AdSkipFingerprint.sourceKey(infoHash: "abcdef", fileIdx: nil, releaseGroup: nil, size: nil, parsedTitle: nil, url: "https://a.b/c"), "ih_abcdef_0")
    }

    func testEmptyInfoHashFallsThroughToTheReleaseKey() {
        XCTAssertEqual(AdSkipFingerprint.sourceKey(infoHash: "", fileIdx: 4, releaseGroup: " RARBG ", size: 1_500_000_000, parsedTitle: "Movie.2024 ", url: "https://a.b/c"),
                       "rg_rarbg_1500000000_movie.2024")
    }

    func testReleaseKeyWithOnlyASizeKeepsTheEmptyParts() {
        XCTAssertEqual(AdSkipFingerprint.sourceKey(infoHash: nil, fileIdx: nil, releaseGroup: nil, size: 1000, parsedTitle: "  ", url: "https://a.b/c"), "rg__1000_")
    }

    func testReleaseKeyWithOnlyATitle() {
        XCTAssertEqual(AdSkipFingerprint.sourceKey(infoHash: nil, fileIdx: nil, releaseGroup: "", size: 0, parsedTitle: "Show S01E02", url: "https://a.b/c"), "rg__0_show s01e02")
    }

    func testZeroSizeAndNoOtherFieldsFallsBackToTheUrl() {
        XCTAssertEqual(AdSkipFingerprint.sourceKey(infoHash: nil, fileIdx: nil, releaseGroup: " ", size: 0, parsedTitle: nil, url: "https://Cdn.Example.com:443/Videos/A.mkv?x=1"),
                       "u_cdn.example.com/videos/a.mkv")
    }

    func testUrlRipKeepsANonDefaultPortAndAnEmptyPathBecomesSlash() {
        XCTAssertEqual(AdSkipFingerprint.urlRip("https://H.example:8443/P"), "h.example:8443/p")
        XCTAssertEqual(AdSkipFingerprint.urlRip("https://h.example"), "h.example/")
        XCTAssertEqual(AdSkipFingerprint.urlRip("http://h.example:80/x"), "h.example/x")
    }

    func testUrlRipCutsAValueThatIsNotAnAbsoluteUrl() {
        XCTAssertEqual(AdSkipFingerprint.urlRip("relative/Path"), "relative/path")
        XCTAssertEqual(AdSkipFingerprint.sourceKey(infoHash: nil, fileIdx: nil, releaseGroup: nil, size: nil, parsedTitle: nil, url: "relative/Path"), "u_relative/path")
    }

    func testFingerprintCombinesTheContentAndTheSource() {
        let key = AdSkipFingerprint.fingerprint(metaID: "kitsu:9", imdbID: nil, infoHash: "AA", fileIdx: 1, releaseGroup: nil, size: nil, parsedTitle: nil, url: "https://x.y/z")
        XCTAssertEqual(key, AdSkipFingerprint.Key(content: "kitsu:9", source: "ih_aa_1"))
    }

    func testStreamReadsTheOfferFieldsThatIOSCarries() {
        let raw: JSONValue = .object(["infoHash": .string("AB"), "fileIdx": .integer(3), "releaseGroup": .string("raw"), "releaseGroupNormalized": .string("GRP"), "size": .integer(1234), "parsedTitle": .string("T")])
        XCTAssertEqual(AdSkipStream(offer: raw, url: "https://u"), AdSkipStream(infoHash: "AB", fileIdx: 3, releaseGroup: "GRP", size: 1234, parsedTitle: "T", url: "https://u"))
        XCTAssertNil(AdSkipStream(offer: .object(["infoHash": .string("")]), url: "https://u").infoHash)
    }

    func testSizeIsReadAsWholeBytes() {
        XCTAssertEqual(AdSkipStream.bytes(.number(1024)), 1024)
        XCTAssertNil(AdSkipStream.bytes(.number(1024.5)))
        XCTAssertEqual(AdSkipStream.bytes(.string(" 77 ")), 77)
        XCTAssertEqual(AdSkipStream.bytes(.unsigned(5)), 5)
        XCTAssertNil(AdSkipStream.bytes(.null))
    }

    // MARK: Corpus (`adcorpus.ts`)

    func testSignedPayloadVerifiesAndDropsBadRanges() throws {
        let key = Curve25519.Signing.PrivateKey()
        let publicKey = key.publicKey.rawRepresentation.base64EncodedString()
        let signed = try signedDocument(corpusPayload, with: key)
        let entries = try XCTUnwrap(AdCorpusRules.verifiedEntries(payload: corpusPayload, signature: signed["sig"].string ?? "", publicKey: publicKey))
        XCTAssertEqual(entries.count, 3)
        XCTAssertEqual(entries[0].ranges, [AdCorpusRange(start: 10, end: 40)])
    }

    func testChangedPayloadIsRejected() throws {
        let key = Curve25519.Signing.PrivateKey()
        let publicKey = key.publicKey.rawRepresentation.base64EncodedString()
        let signature = try key.signature(for: Data(corpusPayload.utf8)).base64EncodedString()
        let tampered = corpusPayload.replacingOccurrences(of: "\"start\":10", with: "\"start\":11")
        XCTAssertNil(AdCorpusRules.verifiedEntries(payload: tampered, signature: signature, publicKey: publicKey))
    }

    func testWrongKeyIsRejected() throws {
        let key = Curve25519.Signing.PrivateKey()
        let other = Curve25519.Signing.PrivateKey()
        let signature = try key.signature(for: Data(corpusPayload.utf8)).base64EncodedString()
        XCTAssertNil(AdCorpusRules.verifiedEntries(payload: corpusPayload, signature: signature, publicKey: other.publicKey.rawRepresentation.base64EncodedString()))
        XCTAssertNil(AdCorpusRules.verifiedEntries(payload: corpusPayload, signature: "not base64!", publicKey: AdCorpusRules.publicKey))
    }

    func testMatchNeedsTheExactContentAndSource() throws {
        let key = Curve25519.Signing.PrivateKey()
        let entries = try XCTUnwrap(AdCorpusRules.verifiedEntries(payload: corpusPayload, signature: try key.signature(for: Data(corpusPayload.utf8)).base64EncodedString(),
                                                                  publicKey: key.publicKey.rawRepresentation.base64EncodedString()))
        let segments = AdCorpusRules.segments(in: entries, content: "tt0000001", source: "ih_abcdef_0")
        XCTAssertEqual(segments, [SkipSegment(kind: .ad, start: 10, end: 40, source: "adcorpus")])
        XCTAssertEqual(AdCorpusRules.segments(in: entries, content: "tt0000001", source: "ih_abcdef_1"), [])
        XCTAssertEqual(AdCorpusRules.segments(in: entries, content: "tt0000009", source: "ih_abcdef_0"), [])
        XCTAssertEqual(AdCorpusRules.segments(in: entries, content: "", source: "ih_abcdef_0"), [])
        XCTAssertEqual(AdCorpusRules.segments(in: entries, content: "tt0000001", source: "rg_grp_1000_title").first?.kind, SkipSegment.Kind.ad)
    }

    func testOnlyHashAndReleaseSourcesAreAccepted() {
        XCTAssertTrue(AdCorpusRules.acceptsSource("ih_x_0"))
        XCTAssertTrue(AdCorpusRules.acceptsSource("rg__0_"))
        XCTAssertFalse(AdCorpusRules.acceptsSource("u_example.com/a"))
    }

    func testCorpusActorReturnsOnlyVerifiedAdSegments() async throws {
        let key = Curve25519.Signing.PrivateKey()
        let publicKey = key.publicKey.rawRepresentation.base64EncodedString()
        let document = try signedDocument(corpusPayload, with: key)
        let corpus = AdCorpus(publicKey: publicKey, load: { document })
        let segments = await corpus.segments(content: "tt0000001", source: "ih_abcdef_0", fresh: true)
        XCTAssertEqual(segments, [SkipSegment(kind: .ad, start: 10, end: 40, source: "adcorpus")])
        let unsupported = await corpus.segments(content: "tt0000002", source: "u_x", fresh: true)
        XCTAssertEqual(unsupported, [])
    }

    func testCorpusActorGivesNothingOnAFailure() async throws {
        let failing = AdCorpus(publicKey: AdCorpusRules.publicKey, load: { throw HarborError(code: "network") })
        let failed = await failing.segments(content: "tt0000001", source: "ih_abcdef_0", fresh: true)
        XCTAssertEqual(failed, [])
        let signer = Curve25519.Signing.PrivateKey()
        let document = try signedDocument(corpusPayload, with: signer)
        let stranger = Curve25519.Signing.PrivateKey().publicKey.rawRepresentation.base64EncodedString()
        let wrongKey = AdCorpus(publicKey: stranger, load: { document })
        let badSignature = await wrongKey.segments(content: "tt0000001", source: "ih_abcdef_0", fresh: true)
        XCTAssertEqual(badSignature, [])
    }

    // MARK: Skip segments and auto-skip

    func testAdSegmentsComeFirstInTheMerge() {
        let ad = SkipSegment(kind: .ad, start: 10, end: 40, source: "adcorpus")
        let intro = SkipSegment(kind: .intro, start: 20, end: 60, source: "aniskip")
        let later = SkipSegment(kind: .recap, start: 70, end: 90, source: "introdb")
        XCTAssertEqual(SkipSegment.merge([[ad], [intro, later]], duration: 600), [ad, later])
    }

    func testAdLabelIsDesktopsLabel() {
        XCTAssertEqual(SkipSegment(kind: .ad, start: 0, end: 30, source: "adcorpus").label, DesktopInterfaceText.value("Skip injected ad?"))
    }

    func testAutoSkipForAdsFollowsTheSetting() {
        let defaults = UserDefaults.standard
        let previous = defaults.object(forKey: "autoSkipAd")
        defer { if let previous { defaults.set(previous, forKey: "autoSkipAd") } else { defaults.removeObject(forKey: "autoSkipAd") } }
        let options = PlaybackOptions()
        let ad = SkipSegment(kind: .ad, start: 10, end: 40, source: "adcorpus")

        defaults.set(false, forKey: "autoSkipAd")
        XCTAssertFalse(options.autoSkips(.ad))
        XCTAssertFalse(options.autoSkipsAnySegment)
        XCTAssertTrue(options.autoSkips(.ad, autoSkipAd: true))
        XCTAssertNil(SkipSegment.autoSkipCandidate(at: 12, in: [ad], options: options, skipped: []))

        defaults.set(true, forKey: "autoSkipAd")
        XCTAssertTrue(options.autoSkips(.ad))
        XCTAssertTrue(options.autoSkipsAnySegment)
        XCTAssertEqual(SkipSegment.autoSkipCandidate(at: 12, in: [ad], options: options, skipped: []), ad)
        XCTAssertNil(SkipSegment.autoSkipCandidate(at: 12, in: [ad], options: options, skipped: [ad.id]))
    }

    // MARK: Settings keys

    func testAdSettingsAreProfileKeys() {
        XCTAssertTrue(ProfileSettingsStore.keys.contains("adSkipEnabled"))
        XCTAssertTrue(ProfileSettingsStore.keys.contains("autoSkipAd"))
        // The report button joined later (AdReportOverlay), so its two keys travel with the profile too.
        XCTAssertTrue(ProfileSettingsStore.keys.contains("adReportAlwaysShow"))
        XCTAssertTrue(ProfileSettingsStore.keys.contains("adReportFirstSeen"))
    }

    // MARK: Report window and button rule

    func testWithinAdWindowBoundaries() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let formatter = ISO8601DateFormatter()
        let exactly = formatter.string(from: now.addingTimeInterval(-150 * 86_400))
        let justPast = formatter.string(from: now.addingTimeInterval(-150 * 86_400 - 1))
        XCTAssertTrue(AdReportRules.withinAdWindow(releaseDate: exactly, releaseInfo: nil, now: now))
        XCTAssertFalse(AdReportRules.withinAdWindow(releaseDate: justPast, releaseInfo: nil, now: now))
    }

    func testWithinAdWindowFallsBackToTheReleaseYear() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let year = calendar.component(.year, from: now)
        XCTAssertTrue(AdReportRules.withinAdWindow(releaseDate: nil, releaseInfo: "\(year - 1)", now: now, calendar: calendar))
        XCTAssertTrue(AdReportRules.withinAdWindow(releaseDate: "not a date", releaseInfo: "\(year)", now: now, calendar: calendar))
        XCTAssertFalse(AdReportRules.withinAdWindow(releaseDate: nil, releaseInfo: "\(year - 2)", now: now, calendar: calendar))
        XCTAssertFalse(AdReportRules.withinAdWindow(releaseDate: "", releaseInfo: nil, now: now, calendar: calendar))
    }

    func testReleaseDatesParseInTheMetadataForms() {
        XCTAssertNotNil(AdReportRules.parseDate("2026-05-01"))
        XCTAssertNotNil(AdReportRules.parseDate("2026-05-01T10:00:00Z"))
        XCTAssertNotNil(AdReportRules.parseDate("2026-05-01T10:00:00.123Z"))
        XCTAssertNil(AdReportRules.parseDate("May 2026"))
    }

    func testShouldShowTruthTable() {
        // A direct stream never shows the button.
        XCTAssertFalse(AdReportRules.shouldShow(enabled: true, alwaysShow: true, isDirectStream: true, recentRelease: true))
        XCTAssertFalse(AdReportRules.shouldShow(enabled: false, alwaysShow: false, isDirectStream: true, recentRelease: true))
        // Always show wins on a P2P stream.
        XCTAssertTrue(AdReportRules.shouldShow(enabled: false, alwaysShow: true, isDirectStream: false, recentRelease: false))
        XCTAssertTrue(AdReportRules.shouldShow(enabled: true, alwaysShow: true, isDirectStream: false, recentRelease: false))
        // Otherwise it needs the setting and a recent release.
        XCTAssertFalse(AdReportRules.shouldShow(enabled: false, alwaysShow: false, isDirectStream: false, recentRelease: true))
        XCTAssertFalse(AdReportRules.shouldShow(enabled: true, alwaysShow: false, isDirectStream: false, recentRelease: false))
        XCTAssertTrue(AdReportRules.shouldShow(enabled: true, alwaysShow: false, isDirectStream: false, recentRelease: true))
    }

    // MARK: Report submission (`submit.ts`)

    func testRangesAreRoundedAndOrdered() {
        let wire = AdReportSubmitter.normalizedRanges([
            AdReportRange(startSec: 10.4, endSec: 5.6),
            AdReportRange(startSec: 2.5, endSec: 2.5),
            AdReportRange(startSec: 3.0, endSec: 1.0),
            AdReportRange(startSec: -2.5, endSec: -1.0),
            AdReportRange(startSec: .nan, endSec: 4)
        ])
        XCTAssertEqual(wire, [AdReportWireRange(start: 6, end: 10), AdReportWireRange(start: 1, end: 3), AdReportWireRange(start: -2, end: -1)])
    }

    func testBodyNeedsAHashOrReleaseSourceAndARange() throws {
        XCTAssertNil(AdReportSubmitter.body(content: "tt1", source: "u_x", ranges: [AdReportRange(startSec: 1, endSec: 5)]))
        XCTAssertNil(AdReportSubmitter.body(content: "tt1", source: "ih_x_0", ranges: [AdReportRange(startSec: 2, endSec: 2)]))
        let body = try XCTUnwrap(AdReportSubmitter.body(content: "tt1", source: "ih_x_0", ranges: [AdReportRange(startSec: 1, endSec: 5)]))
        XCTAssertEqual(body, .object(["content": .string("tt1"), "source": .string("ih_x_0"),
                                      "ranges": .array([.object(["start": .integer(1), "end": .integer(5)])])]))
    }

    func testSubmitPostsToTheReportEndpointAndReportsTheStatus() async {
        let accepted = await AdReportSubmitter.submit(content: "tt1", source: "rg_g_1_t", ranges: [AdReportRange(startSec: 1, endSec: 5)], transport: { url, body in
            XCTAssertEqual(url, "https://bugs.harbor.site/v1/adreport")
            XCTAssertNotNil(body["ranges"].array.first)
            return true
        })
        XCTAssertTrue(accepted)
        let refused = await AdReportSubmitter.submit(content: "tt1", source: "rg_g_1_t", ranges: [AdReportRange(startSec: 1, endSec: 5)], transport: { _, _ in false })
        XCTAssertFalse(refused)
        let failed = await AdReportSubmitter.submit(content: "tt1", source: "rg_g_1_t", ranges: [AdReportRange(startSec: 1, endSec: 5)], transport: { _, _ in throw HarborError(code: "network") })
        XCTAssertFalse(failed)
    }
}

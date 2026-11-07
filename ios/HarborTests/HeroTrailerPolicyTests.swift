import XCTest
@testable import Harbor

/// Desktop's hero and detail trailer rules (`cinema-hero.tsx`, `detail-hero-trailer.tsx`, `settings/defaults.ts`) as applied on iOS.
final class HeroTrailerPolicyTests: XCTestCase {
    private var suiteName = ""

    override func setUp() {
        super.setUp()
        suiteName = "harbor.tests.hero-trailer.\(UUID().uuidString)"
    }

    override func tearDown() {
        UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private func openConditions() -> HeroTrailerPolicy.Conditions {
        HeroTrailerPolicy.Conditions(enabled: true, hasTrailer: true, sceneActive: true, slideActive: true,
                                     reduceMotion: false, lowPowerMode: false, expensiveNetwork: false, constrainedNetwork: false)
    }

    private func trailer(_ id: String) -> MediaDetails.Trailer {
        MediaDetails.Trailer(id: id, title: "Official trailer", url: "https://www.youtube.com/watch?v=\(id)", thumbnail: nil)
    }

    func testOpenConditionsPlay() {
        XCTAssertTrue(HeroTrailerPolicy.shouldPlay(openConditions()))
    }

    func testEachBlockingInputStopsPlaybackOnItsOwn() {
        let blockers: [(String, (inout HeroTrailerPolicy.Conditions) -> Void)] = [
            ("setting off", { $0.enabled = false }),
            ("no trailer", { $0.hasTrailer = false }),
            ("scene in background", { $0.sceneActive = false }),
            ("slide not on screen", { $0.slideActive = false }),
            ("Reduce Motion", { $0.reduceMotion = true }),
            ("Low Power Mode", { $0.lowPowerMode = true }),
            ("metered network", { $0.expensiveNetwork = true }),
            ("Low Data Mode", { $0.constrainedNetwork = true })
        ]
        for (name, block) in blockers {
            var conditions = openConditions()
            block(&conditions)
            XCTAssertFalse(HeroTrailerPolicy.shouldPlay(conditions), name)
        }
    }

    func testPicksFirstValidTrailerAndSkipsInvalidIDs() {
        let trailers = [trailer("bad"), trailer("LY19rHKAaAg"), trailer("R8teZZ-loaI")]
        XCTAssertEqual(HeroTrailerPolicy.trailerID(in: trailers), "LY19rHKAaAg")
    }

    func testNoCandidateWhenListIsEmptyOrAllInvalid() {
        XCTAssertNil(HeroTrailerPolicy.trailerID(in: []))
        XCTAssertNil(HeroTrailerPolicy.trailerID(in: [trailer("short"), trailer("https://example.invalid")]))
    }

    func testYouTubeIDShape() {
        XCTAssertTrue(HeroTrailerPolicy.isValidYouTubeID("LY19rHKAaAg"))
        XCTAssertTrue(HeroTrailerPolicy.isValidYouTubeID("R8teZZ-loaI"))
        XCTAssertFalse(HeroTrailerPolicy.isValidYouTubeID("LY19rHKAaA"), "10 characters")
        XCTAssertFalse(HeroTrailerPolicy.isValidYouTubeID("LY19rHKAaAgX"), "12 characters")
        XCTAssertFalse(HeroTrailerPolicy.isValidYouTubeID("LY19rHKAa/g"), "path separator")
        XCTAssertFalse(HeroTrailerPolicy.isValidYouTubeID("LY19rHKAaA\u{00E9}"), "non-ASCII letter")
    }

    func testEmbedURLUsesNoCookieHostAndMutedAutoplayParameters() throws {
        let muted = try XCTUnwrap(HeroTrailerPolicy.embedURL(videoID: "LY19rHKAaAg", muted: true)).absoluteString
        XCTAssertTrue(muted.hasPrefix("https://www.youtube-nocookie.com/embed/LY19rHKAaAg?"))
        XCTAssertTrue(muted.contains("autoplay=1"))
        XCTAssertTrue(muted.contains("mute=1"))
        XCTAssertTrue(muted.contains("playsinline=1"))
        XCTAssertTrue(muted.contains("loop=1&playlist=LY19rHKAaAg"))

        let audible = try XCTUnwrap(HeroTrailerPolicy.embedURL(videoID: "LY19rHKAaAg", muted: false)).absoluteString
        XCTAssertTrue(audible.contains("mute=0"))
        XCTAssertFalse(audible.contains("mute=1"))
    }

    func testEmbedURLRefusesInvalidID() {
        XCTAssertNil(HeroTrailerPolicy.embedURL(videoID: "../../evil", muted: true))
        XCTAssertNil(HeroTrailerPolicy.embedURL(videoID: "", muted: true))
    }

    func testMutedUnlessAudioSettingIsOn() {
        XCTAssertTrue(HeroTrailerPolicy.muted(audioEnabled: false))
        XCTAssertFalse(HeroTrailerPolicy.muted(audioEnabled: true))
    }

    func testSettingsDefaultsAreOffWhenNothingIsStored() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        XCTAssertEqual(HeroTrailerSettings(defaults: defaults), HeroTrailerSettings())
        XCTAssertFalse(HeroTrailerSettings(defaults: defaults).heroTrailers)
        XCTAssertFalse(HeroTrailerSettings(defaults: defaults).heroTrailerAudio)
        XCTAssertFalse(HeroTrailerSettings(defaults: defaults).detailTrailerAutoplay)
        XCTAssertFalse(HeroTrailerSettings(defaults: defaults).detailTrailerAudio)
    }

    func testStoredSettingsAreReadFromDesktopKeys() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.set(true, forKey: "heroTrailers")
        defaults.set(true, forKey: "detailTrailerAutoplay")
        let settings = HeroTrailerSettings(defaults: defaults)
        XCTAssertTrue(settings.heroTrailers)
        XCTAssertTrue(settings.detailTrailerAutoplay)
        XCTAssertFalse(settings.heroTrailerAudio)
        XCTAssertFalse(settings.detailTrailerAudio)
    }

    func testNonBooleanStoredValueFallsBackToDesktopDefault() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.set("yes", forKey: "heroTrailers")
        XCTAssertFalse(HeroTrailerSettings(defaults: defaults).heroTrailers)
    }
}

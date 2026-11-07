import XCTest
@testable import Harbor

/// Desktop's hero layout settings (`settings/defaults.ts`, `components/hero.tsx`, `views/home.tsx`) as applied on iOS.
final class HeroLayoutPolicyTests: XCTestCase {
    private var suiteName = ""

    override func setUp() {
        super.setUp()
        suiteName = "harbor.tests.hero-layout.\(UUID().uuidString)"
    }

    override func tearDown() {
        UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testDesktopDefaultsWhenNothingIsStored() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let settings = HeroLayoutSettings(defaults: defaults)
        XCTAssertEqual(settings, HeroLayoutSettings())
        XCTAssertEqual(settings.shadowPercent, 100)
        XCTAssertFalse(settings.full)
        XCTAssertTrue(settings.fullQuality)
        XCTAssertEqual(settings.feed, .trending)
    }

    func testStoredValuesAreReadFromDesktopKeys() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.set(40, forKey: "heroShadow")
        defaults.set(true, forKey: "heroFull")
        defaults.set(false, forKey: "heroFullQuality")
        defaults.set("simkl", forKey: "heroFeed")
        let settings = HeroLayoutSettings(defaults: defaults)
        XCTAssertEqual(settings.shadowPercent, 40)
        XCTAssertTrue(settings.full)
        XCTAssertFalse(settings.fullQuality)
        XCTAssertEqual(settings.feed, .simkl)
    }

    func testUnreadableStoredValuesFallBackToDesktopDefaults() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.set("heavy", forKey: "heroShadow")
        defaults.set("yes", forKey: "heroFull")
        defaults.set("no", forKey: "heroFullQuality")
        defaults.set("bogus", forKey: "heroFeed")
        let settings = HeroLayoutSettings(defaults: defaults)
        XCTAssertEqual(settings.shadowPercent, 100)
        XCTAssertFalse(settings.full)
        XCTAssertTrue(settings.fullQuality)
        XCTAssertEqual(settings.feed, .trending)
    }

    func testShadowIsClampedToZeroThroughHundredAndRounded() {
        XCTAssertEqual(HeroLayoutPolicy.shadowPercent(-5), 0)
        XCTAssertEqual(HeroLayoutPolicy.shadowPercent(150), 100)
        XCTAssertEqual(HeroLayoutPolicy.shadowPercent(42.4), 42)
        XCTAssertEqual(HeroLayoutPolicy.shadowPercent(42.6), 43)
        XCTAssertEqual(HeroLayoutPolicy.shadowPercent(.nan), 100)
        XCTAssertEqual(HeroLayoutPolicy.shadowPercent(stored: NSNumber(value: 250)), 100)
        XCTAssertEqual(HeroLayoutPolicy.shadowPercent(stored: nil), 100)
    }

    func testMiddleStopScalesWithShadowAndKeepsClassicLookAtHundred() {
        XCTAssertEqual(HeroLayoutPolicy.middleStopOpacity(shadowPercent: 100), 0.55, accuracy: 0.0001)
        XCTAssertEqual(HeroLayoutPolicy.middleStopOpacity(shadowPercent: 50), 0.275, accuracy: 0.0001)
        XCTAssertEqual(HeroLayoutPolicy.middleStopOpacity(shadowPercent: 0), 0, accuracy: 0.0001)
        XCTAssertEqual(HeroLayoutPolicy.middleStopOpacity(shadowPercent: 400), 0.55, accuracy: 0.0001, "clamped before scaling")
        XCTAssertEqual(HeroLayoutPolicy.topStopOpacity, 0.12, accuracy: 0.0001)
    }

    func testArtworkPixelLimitsFollowFullQuality() {
        XCTAssertEqual(HeroLayoutPolicy.artworkMaxPixels(fullQuality: true), 2160)
        XCTAssertEqual(HeroLayoutPolicy.artworkMaxPixels(fullQuality: false), 1280)
    }

    func testStandardHeightIsUnchangedWhenNotFull() {
        XCTAssertEqual(HeroLayoutPolicy.heroHeight(full: false, container: 900), 410)
        XCTAssertEqual(HeroLayoutPolicy.heroHeight(full: false, container: 300), 410)
    }

    func testFullBannerIsSeventyEightPercentWithFloorOfSixForty() {
        XCTAssertEqual(HeroLayoutPolicy.heroHeight(full: true, container: 1000), 780)
        XCTAssertEqual(HeroLayoutPolicy.heroHeight(full: true, container: 800), 640, "78% is below the floor")
        XCTAssertEqual(HeroLayoutPolicy.heroHeight(full: true, container: .nan), 640)
        XCTAssertEqual(HeroLayoutPolicy.heroHeight(full: true, container: 0), 640)
    }

    func testFeedKnownValuesAreReadAndUnknownValuesFallBackToTrending() {
        XCTAssertEqual(HeroLayoutPolicy.HeroFeed(stored: "trakt"), .trakt)
        XCTAssertEqual(HeroLayoutPolicy.HeroFeed(stored: "classic"), .classic)
        XCTAssertEqual(HeroLayoutPolicy.HeroFeed(stored: "now"), .trending, "Desktop's internal pool key is not a feed value")
        XCTAssertEqual(HeroLayoutPolicy.HeroFeed(stored: 3), .trending)
        XCTAssertEqual(HeroLayoutPolicy.HeroFeed(stored: nil), .trending)
    }

    func testTrendingKeepsTheAutomaticHero() {
        let candidates = [HeroLayoutPolicy.Candidate(title: "Top Movies", hasMetas: true)]
        XCTAssertNil(HeroLayoutPolicy.featuredRailIndex(feed: .trending, candidates: candidates))
    }

    func testClassicUsesFirstRailWithTitles() {
        let candidates = [
            HeroLayoutPolicy.Candidate(title: "Continue Watching", hasMetas: false),
            HeroLayoutPolicy.Candidate(title: "Top Movies", hasMetas: true),
            HeroLayoutPolicy.Candidate(title: "Top Drama", hasMetas: true)
        ]
        XCTAssertEqual(HeroLayoutPolicy.featuredRailIndex(feed: .classic, candidates: candidates), 1)
        XCTAssertNil(HeroLayoutPolicy.featuredRailIndex(feed: .classic, candidates: [HeroLayoutPolicy.Candidate(title: "Empty", hasMetas: false)]))
    }

    func testTraktAndSimklPickTheMatchingRailWithTitles() {
        let candidates = [
            HeroLayoutPolicy.Candidate(title: "Top Movies", hasMetas: true),
            HeroLayoutPolicy.Candidate(title: "Trakt Recommends: Movies", hasMetas: false),
            HeroLayoutPolicy.Candidate(title: "trakt trending", hasMetas: true),
            HeroLayoutPolicy.Candidate(title: "Simkl Trending", hasMetas: true)
        ]
        XCTAssertEqual(HeroLayoutPolicy.featuredRailIndex(feed: .trakt, candidates: candidates), 2, "empty rail skipped, match is case-insensitive")
        XCTAssertEqual(HeroLayoutPolicy.featuredRailIndex(feed: .simkl, candidates: candidates), 3)
        XCTAssertNil(HeroLayoutPolicy.featuredRailIndex(feed: .simkl, candidates: [HeroLayoutPolicy.Candidate(title: "Top Movies", hasMetas: true)]))
    }

    @MainActor func testPreferenceWritesUseDesktopKeysAndAreReadBack() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let preferences = HeroLayoutPreferences(defaults: defaults)
        preferences.shadowStrength = 37.4
        preferences.full = true
        preferences.fullQuality = false
        preferences.feed = .classic
        XCTAssertEqual(defaults.double(forKey: "heroShadow"), 37, accuracy: 0.0001)
        XCTAssertTrue(defaults.bool(forKey: "heroFull"))
        XCTAssertFalse(defaults.bool(forKey: "heroFullQuality"))
        XCTAssertEqual(defaults.string(forKey: "heroFeed"), "classic")
        XCTAssertEqual(preferences.shadowPercent, 37)
        XCTAssertEqual(preferences.feed, .classic)
    }
}

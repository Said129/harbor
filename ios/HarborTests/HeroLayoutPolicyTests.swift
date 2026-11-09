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

    func testHostedFeedsUseDesktopKeysAndKeepAnExplicitlyEmptySource() throws {
        let payload: JSONValue = .object(["sources": .object([
            "now": .array([hostedTitle("now"), hostedTitle("poster-only", background: nil), hostedTitle("bad-art", background: "http://example.com/")]),
            "trakt": .array([hostedTitle("trakt")]),
            "simkl": .array([]),
        ])])
        let pool = try XCTUnwrap(HostedHomeHeroPool.Pool(payload))
        let trending = pool.entries(for: .trending)
        XCTAssertEqual(trending.map { $0.media.id }, ["now"])
        XCTAssertEqual(trending.first?.rank?.label, "Movies")
        XCTAssertEqual(trending.first?.rank?.position, 2)
        XCTAssertEqual(trending.first?.rank?.sources.first?.position, 3)
        XCTAssertNil(trending.first?.media.addonOrigin)
        XCTAssertEqual(pool.entries(for: .trakt).map { $0.media.id }, ["trakt"])
        XCTAssertTrue(pool.entries(for: .simkl).isEmpty)
        XCTAssertTrue(pool.entries(for: .classic).isEmpty)

        let missing = try XCTUnwrap(HostedHomeHeroPool.Pool(.object(["sources": .object([
            "now": .array([hostedTitle("now")]), "trakt": .null,
        ])])))
        XCTAssertEqual(missing.entries(for: .trakt).map { $0.media.id }, ["now"])
        XCTAssertEqual(missing.entries(for: .simkl).map { $0.media.id }, ["now"])
        XCTAssertNil(HostedHomeHeroPool.Pool(.object(["sources": .object(["now": .null])])))
    }

    func testHomeHeroPrefersExplicitArtThenFourHostedCandidatesThenLocal() throws {
        let hosted = try XCTUnwrap(HostedHomeHeroPool.Pool(.object(["sources": .object([
            "now": .array((1...5).map { hostedTitle("hosted\($0)") }),
        ])]))).entries(for: .trending)
        let local = [Media(id: "local", type: "movie", name: "Local")]
        let poster = Media(id: "poster", type: "movie", name: "Poster", poster: "https://example.com/p.jpg")
        let background = Media(id: "background", type: "movie", name: "Background", background: "https://example.com/b.jpg")
        let rail = PageRail.discovery(.init(id: "custom", title: "Trakt", kind: "movie", path: "", metas: [poster, background]))
        let custom = HomeHeroSlides.displayedHome(rails: [rail], defaults: local, heroSourceID: rail.id, hosted: hosted)
        XCTAssertTrue(custom.usesCustomRail)
        XCTAssertEqual(custom.slides.map(\.id), ["background", "poster"])
        XCTAssertTrue(custom.ranks.isEmpty)
        let featured = HomeHeroSlides.displayedHome(rails: [rail], defaults: local, heroSourceID: nil, hosted: hosted)
        XCTAssertFalse(featured.usesCustomRail)
        XCTAssertEqual(featured.slides.map(\.id), (1...4).map { "hosted\($0)" })
        XCTAssertEqual(featured.ranks["hosted1"]?.position, 2)
        let incomplete = HomeHeroSlides.displayedHome(rails: [rail], defaults: local, heroSourceID: nil, hosted: Array(hosted.prefix(3)))
        XCTAssertEqual(incomplete.slides.map(\.id), ["local"])
    }

    func testHostedPoolSharesCacheAndKeepsStaleDataWhenFetchFails() async throws {
        let cache = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: cache) }
        let initialTime = Date(timeIntervalSinceReferenceDate: 10_000)
        let payload = JSONValue.object(["sources": .object(["now": .array([hostedTitle("shared")])])])
        let probe = HostedFetchProbe(payload)
        let initial = HostedHomeHeroPool(cacheURL: cache, fetch: { try await probe.fetch($0) }, now: { initialTime })
        let classic = await initial.load(for: .classic)
        XCTAssertNil(classic)
        async let trending = initial.load(for: .trending)
        async let trakt = initial.load(for: .trakt)
        let (trendingPool, traktPool) = await (trending, trakt)
        XCTAssertEqual(trendingPool?.entries(for: .trending).first?.media.id, "shared")
        XCTAssertEqual(traktPool?.entries(for: .trakt).first?.media.id, "shared")

        let offline = HostedFetchProbe(nil)
        let fresh = HostedHomeHeroPool(cacheURL: cache, fetch: { try await offline.fetch($0) }, now: { initialTime.addingTimeInterval(60) })
        let cached = await fresh.load(for: .simkl)
        let freshRequests = await offline.requests
        XCTAssertEqual(cached?.entries(for: .simkl).first?.media.id, "shared")
        XCTAssertTrue(freshRequests.isEmpty)

        let expired = HostedHomeHeroPool(cacheURL: cache, fetch: { try await offline.fetch($0) }, now: { initialTime.addingTimeInterval(4 * 3600) })
        let fallback = await expired.load(for: .trending)
        _ = await expired.load(for: .simkl)
        let expiredRequests = await offline.requests
        let initialRequests = await probe.requests
        XCTAssertEqual(fallback?.entries(for: .trending).first?.media.id, "shared")
        XCTAssertEqual(initialRequests, [HostedHomeHeroPool.endpoint])
        XCTAssertEqual(expiredRequests, [HostedHomeHeroPool.endpoint])
    }

    private func hostedTitle(_ id: String, background: String? = "https://example.com/backdrop.jpg") -> JSONValue {
        .object([
            "id": .string(id), "name": .string(id), "type": .string("movie"),
            "poster": .string("https://example.com/poster.jpg"),
            "background": background.map(JSONValue.string) ?? .null,
            "rank": .integer(2), "rankLabel": .string("Movies"),
            "sources": .array([.object(["label": .string("TMDB"), "rank": .integer(3)])]),
            "addonOrigin": .object(["id": .string("untrusted-addon")]),
        ])
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

private actor HostedFetchProbe {
    private let payload: JSONValue?
    private(set) var requests: [String] = []

    init(_ payload: JSONValue?) { self.payload = payload }

    func fetch(_ endpoint: String) throws -> JSONValue {
        requests.append(endpoint)
        guard let payload else { throw URLError(.notConnectedToInternet) }
        return payload
    }
}

import XCTest
@testable import Harbor

/// Desktop addon sharing (`manifestToShareUrl` in addon-store.ts, `normalizeInstallUrl` in installer-viewport.tsx)
/// and the "Recommended for you" rule (`recommendedAddons` in addons-store/recommend.ts).
final class AddonSharingTests: XCTestCase {
    private func addon(_ id: String, name: String, url: String, resources: [String] = ["stream"], adult: Bool = false) -> Addon {
        var fields: [String: JSONValue] = [
            "id": .string(id),
            "name": .string(name),
            "types": .array([.string("movie")]),
            "resources": .array(resources.map { JSONValue.string($0) })
        ]
        if adult { fields["behaviorHints"] = .object(["adult": .bool(true)]) }
        return Addon(manifest: .object(fields), transportUrl: url, enabled: true)
    }

    func testShareTextMirrorsDesktopManifestToShareUrl() {
        let https = "https://example.org/config/manifest.json"
        XCTAssertEqual(AddonSharing.shareText(transportUrl: https, scheme: .https), https)
        XCTAssertEqual(AddonSharing.shareText(transportUrl: https, scheme: .stremio), "stremio://example.org/config/manifest.json")
        XCTAssertEqual(AddonSharing.shareText(transportUrl: "HTTP://Example.org/m.json", scheme: .stremio), "stremio://Example.org/m.json")
        XCTAssertEqual(AddonSharing.shareText(transportUrl: "stremio://example.org/m.json", scheme: .stremio), "stremio://example.org/m.json")
    }

    func testShareURLUsesStremioSchemeForInstalledAddon() {
        let value = addon("alpha", name: "Alpha", url: "https://example.org/a/manifest.json")
        XCTAssertEqual(AddonSharing.shareURL(for: value)?.absoluteString, "stremio://example.org/a/manifest.json")
    }

    func testInstallLinkMirrorsDesktopNormalizeInstallUrl() {
        XCTAssertEqual(AddonSharing.installLink(from: "stremio://example.org/a/manifest.json"), "https://example.org/a/manifest.json")
        XCTAssertEqual(AddonSharing.installLink(from: "  https://example.org/a/manifest.json \n"), "https://example.org/a/manifest.json")
        XCTAssertEqual(AddonSharing.installLink(from: "http://example.org/m.json"), "http://example.org/m.json")
        XCTAssertNil(AddonSharing.installLink(from: ""))
        XCTAssertNil(AddonSharing.installLink(from: "   "))
        XCTAssertNil(AddonSharing.installLink(from: "ftp://example.org/m.json"))
        XCTAssertNil(AddonSharing.installLink(from: "example.org/manifest.json"))
        XCTAssertNil(AddonSharing.installLink(from: "STREMIO://example.org/m.json"))
    }

    func testShareLinkRoundTripsThroughInstallLink() {
        let value = addon("alpha", name: "Alpha", url: "https://example.org/a/manifest.json")
        let shared = AddonSharing.shareURL(for: value)?.absoluteString ?? ""
        XCTAssertEqual(AddonSharing.installLink(from: shared), "https://example.org/a/manifest.json")
    }

    func testNormalizedNameDropsDesktopDecorations() {
        XCTAssertEqual(AddonRecommendations.normalizedName("Torrentio | RD [Debrid]"), "torrentio")
        XCTAssertEqual(AddonRecommendations.normalizedName("Cinemeta Official"), "cinemeta")
        XCTAssertEqual(AddonRecommendations.normalizedName("Alpha  Streams!"), "alphastreams")
        XCTAssertEqual(AddonRecommendations.normalizedName(nil), "")
    }

    func testRecommendationsRankInstalledTasteThenSameCategory() {
        let target = addon("target", name: "Target Streams", url: "https://target.example.org/manifest.json")
        let installedSubs = addon("subs-installed", name: "Installed Subs", url: "https://subs.example.org/manifest.json", resources: ["subtitles"])
        let alpha = addon("alpha", name: "Alpha", url: "https://alpha.example.org/manifest.json")
        let subsTwo = addon("subs-two", name: "Subs Two", url: "https://subs2.example.org/manifest.json", resources: ["subtitles"])
        let meta = addon("meta", name: "Meta Catalog", url: "https://meta.example.org/manifest.json", resources: ["catalog"])
        let alphaDuplicate = addon("alpha-dup", name: "Alpha", url: "https://alpha2.example.org/manifest.json")
        let adult = addon("adult-one", name: "Adult One", url: "https://adult.example.org/manifest.json", adult: true)
        let candidates = [alpha, subsTwo, meta, alphaDuplicate, adult, target, installedSubs]
        let result = AddonRecommendations.recommended(
            for: target,
            candidates: candidates,
            installedIDs: ["subs-installed"],
            exclude: []
        )
        // subs-two gets the +30 taste bonus, alpha the +20 same-category bonus, meta scores 0.
        // The duplicate "Alpha", the adult addon, the target itself and the installed addon are dropped.
        XCTAssertEqual(result.map { AddonRecommendations.key($0) }, ["subs-two", "alpha", "meta"])
    }

    func testRecommendationsHonourExcludeAndLimit() {
        let target = addon("target", name: "Target Streams", url: "https://target.example.org/manifest.json")
        let alpha = addon("alpha", name: "Alpha", url: "https://alpha.example.org/manifest.json")
        let subsTwo = addon("subs-two", name: "Subs Two", url: "https://subs2.example.org/manifest.json", resources: ["subtitles"])
        let meta = addon("meta", name: "Meta Catalog", url: "https://meta.example.org/manifest.json", resources: ["catalog"])
        let candidates = [alpha, subsTwo, meta, target]
        let excluded = AddonRecommendations.recommended(for: target, candidates: candidates, installedIDs: [], exclude: ["meta"])
        XCTAssertEqual(excluded.map { AddonRecommendations.key($0) }, ["alpha", "subs-two"])
        let limited = AddonRecommendations.recommended(for: target, candidates: candidates, installedIDs: [], exclude: [], limit: 1)
        XCTAssertEqual(limited.map { AddonRecommendations.key($0) }, ["alpha"])
    }

    func testRecommendationsWithoutInstalledAddonsKeepCatalogOrderWithinScore() {
        let target = addon("target", name: "Target Streams", url: "https://target.example.org/manifest.json")
        let installedSubs = addon("subs-installed", name: "Installed Subs", url: "https://subs.example.org/manifest.json", resources: ["subtitles"])
        let alpha = addon("alpha", name: "Alpha", url: "https://alpha.example.org/manifest.json")
        let subsTwo = addon("subs-two", name: "Subs Two", url: "https://subs2.example.org/manifest.json", resources: ["subtitles"])
        let meta = addon("meta", name: "Meta Catalog", url: "https://meta.example.org/manifest.json", resources: ["catalog"])
        let result = AddonRecommendations.recommended(
            for: target,
            candidates: [alpha, subsTwo, meta, installedSubs, target],
            installedIDs: [],
            exclude: []
        )
        // No taste yet, so only alpha gets the same-category +20; the rest keep catalog order at 0.
        XCTAssertEqual(result.map { AddonRecommendations.key($0) }, ["alpha", "subs-two", "meta", "subs-installed"])
    }
}

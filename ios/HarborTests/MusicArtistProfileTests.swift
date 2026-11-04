import SwiftUI
import UIKit
import XCTest
@testable import Harbor

private actor ProfileFixtureNetwork: HarborNativeNetworkCalling {
    private let bodies: [String: String]
    private(set) var requests: [(url: String, publicOnly: Bool)] = []
    init(bodies: [String: String]) { self.bodies = bodies }
    func perform(_ request: HarborNetworkRequest) async throws -> HarborNetworkResponse {
        requests.append((request.url, request.publicNetworkOnly && !request.allowLocalNetwork))
        guard let body = bodies[Self.key(request.url)] else {
            return .init(status: 404, ok: false, headers: [:], bodyBase64: "", url: request.url)
        }
        return .init(status: 200, ok: true, headers: ["content-length": String(body.utf8.count)], bodyBase64: Data(body.utf8).base64EncodedString(), url: request.url)
    }
    static func key(_ url: String) -> String { URL(string: url)?.absoluteString ?? url }
}

private struct ProfileFixture: Decodable {
    let reference: String
    let program_sha256: String
    let artist_id: String
    let artist: MusicArtistReference
    let language: String
    let musicbrainz: JSONValue
    let responses: [String: JSONValue]
    let expected_parse: MusicArtistProfile
    let expected_profile: MusicArtistProfile
    let requests_in_order: [String]
}

@MainActor private final class ProfileScope { let value = PluginExecutionScope(owner: "owned-profile-" + UUID().uuidString, activation: UUID()) }

@MainActor final class MusicArtistProfileTests: XCTestCase {
    private func fixture() throws -> ProfileFixture {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "music-artist-profile-reference", withExtension: "json", subdirectory: "Fixtures"))
        return try JSONDecoder().decode(ProfileFixture.self, from: Data(contentsOf: url))
    }
    private func bodies(_ fixture: ProfileFixture) throws -> [String: String] {
        try Dictionary(uniqueKeysWithValues: fixture.responses.map { url, value in
            (ProfileFixtureNetwork.key(url), String(decoding: try JSONEncoder().encode(value), as: UTF8.self))
        })
    }

    func testPinnedOriginalProfileParserKeepsLinkKindsIdentitiesAndRejectsUnsafeRelations() async throws {
        let fixture = try fixture(), scope = ProfileScope()
        XCTAssertEqual(fixture.reference, "0834340cec5531650bfe78cd628628702e636987")
        let asset = try MusicArtistAsset.read(); XCTAssertEqual(asset.program.sha256, fixture.program_sha256)
        let client = MusicArtistClient(scope: scope.value, currentScope: { scope.value }, transport: MusicArtistTransport(network: ProfileFixtureNetwork(bodies: [:])))
        defer { client.dispose() }
        let parsed = try await client.query("parseProfile", arguments: ["data": fixture.musicbrainz, "id": .string(fixture.artist_id)], as: MusicArtistProfile?.self)
        XCTAssertEqual(parsed, fixture.expected_parse)
        XCTAssertEqual(parsed?.links.filter { $0.url.contains("qobuz") }.count, 1)
        XCTAssertFalse(parsed?.links.contains { $0.url.contains("127.0.0.1") || $0.url.contains("old.example") || $0.url.contains("play.google") } ?? true)
        XCTAssertEqual(parsed?.genres, ["ambient", "synth", "drone"])
        let wrongIdentity = try await client.query("parseProfile", arguments: ["data": fixture.musicbrainz, "id": .string("44444444-4444-4444-8444-444444444444")], as: MusicArtistProfile?.self)
        XCTAssertNil(wrongIdentity, "A profile is accepted only for the identity it was fetched for")
        let invalid = try await client.query("parseProfile", arguments: ["data": fixture.musicbrainz, "id": .string("not-a-uuid")], as: MusicArtistProfile?.self)
        XCTAssertNil(invalid)
    }

    func testActualWorkerLoadsMusicBrainzThenVerifiedWikidataAndWikipediaWithinThePublicHosts() async throws {
        let fixture = try fixture(), scope = ProfileScope(), network = ProfileFixtureNetwork(bodies: try bodies(fixture))
        let client = MusicArtistClient(scope: scope.value, currentScope: { scope.value }, transport: MusicArtistTransport(network: network))
        defer { client.dispose() }
        let loaded = try await client.profile(fixture.artist, language: fixture.language), profile = try XCTUnwrap(loaded)
        XCTAssertEqual(profile, fixture.expected_profile)
        XCTAssertEqual(profile.biography, "Resumen original del artista de prueba.")
        XCTAssertEqual(profile.biographyUrl, "https://es.wikipedia.org/wiki/Owned_Artist")
        let requests = await network.requests
        XCTAssertEqual(requests.map { ProfileFixtureNetwork.key($0.url) }, fixture.requests_in_order.map(ProfileFixtureNetwork.key))
        XCTAssertTrue(requests.allSatisfy(\.publicOnly))
        _ = try await client.profile(fixture.artist, language: fixture.language)
        let again = await network.requests.count; XCTAssertEqual(again, requests.count, "The original 30-minute cache serves a repeat")
    }

    func testProfileHostPolicyAcceptsOnlyTheOriginalMetadataHostsAndPublicImageAndStoreLinks() {
        for host in ["musicbrainz.org", "api.deezer.com", "ws.audioscrobbler.com", "www.wikidata.org", "es.wikipedia.org", "en.wikipedia.org", "zho.wikipedia.org"] {
            XCTAssertTrue(MusicArtistTransport.allowed(host), host)
        }
        for host in ["wikipedia.org", "abcd.wikipedia.org", "es.wikipedia.org.evil.example", "wikidata.org", "commons.wikimedia.org", "evil.example", ""] {
            XCTAssertFalse(MusicArtistTransport.allowed(host), host)
        }
        XCTAssertNotNil(MusicArtistLinks.imageURL("https://upload.wikimedia.org/a.jpg"))
        XCTAssertNil(MusicArtistLinks.imageURL("http://upload.wikimedia.org/a.jpg"))
        XCTAssertNil(MusicArtistLinks.imageURL("https://evil.example/a.jpg"))
        XCTAssertNil(MusicArtistLinks.imageURL(nil))
        XCTAssertNotNil(MusicArtistLinks.wikipedia("https://es.wikipedia.org/wiki/A"))
        XCTAssertNil(MusicArtistLinks.wikipedia("https://es.wikipedia.org.evil.example/wiki/A"))
        XCTAssertEqual(MusicArtistLinks.bandcampSearch(artist: "Owned Artist", title: "Song & Co")?.absoluteString, "https://bandcamp.com/search?q=Owned%20Artist%20Song%20%26%20Co")
        XCTAssertNil(MusicArtistLinks.bandcampSearch(artist: " ", title: ""))
    }

    func testArtistOverviewRendersProfileFactsLinksAndWhereToBuyOnPhoneTabletAndArabic() async throws {
        let fixture = try fixture(), responses = try bodies(fixture)
        let oldLanguage = UserDefaults.standard.string(forKey: "uiLanguage")
        defer {
            if let oldLanguage { UserDefaults.standard.set(oldLanguage, forKey: "uiLanguage") } else { UserDefaults.standard.removeObject(forKey: "uiLanguage") }
        }
        let track = MusicTrack(id: "owned-about", connectorId: "direct", sourceId: "owned-about", playbackUrl: nil, title: "Owned Song", artist: "Owned Artist", album: nil,
                               artwork: "", durationSeconds: 180, durationLabel: "3:00")
        for (name, size, language, direction) in [
            ("phone", CGSize(width: 390, height: 844), "es", LayoutDirection.leftToRight),
            ("tablet", CGSize(width: 1024, height: 1366), "es", LayoutDirection.leftToRight),
            ("arabic-phone", CGSize(width: 390, height: 844), "ar", LayoutDirection.rightToLeft)
        ] {
            UserDefaults.standard.set(language, forKey: "uiLanguage")
            for key in ["music.artist.about", "music.artist.connections", "music.artist.aroundWeb", "music.buy.title", "music.artist.readMore"] {
                XCTAssertNotEqual(DesktopInterfaceText.value(key, language: language), key, key + " in " + language)
            }
            // A fresh client per capture: its own worker cache must fetch all three sources.
            let scope = ProfileScope(), network = ProfileFixtureNetwork(bodies: responses)
            let client = MusicArtistClient(scope: scope.value, currentScope: { scope.value }, transport: MusicArtistTransport(network: network))
            defer { client.dispose() }
            try await capture(NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        MusicArtistOverviewView(artist: fixture.artist, client: client, catalog: MusicCatalogClient())
                        MusicWhereToBuyView(track: track, artist: fixture.artist, client: client)
                    }.padding(20)
                }
            }.environment(\.layoutDirection, direction).environment(\.locale, Locale(identifier: language)),
                              name: "music-about-" + name, size: size, ready: { await network.requests.count >= 3 })
        }
    }

    private func capture<V: View>(_ view: V, name: String, size: CGSize, ready: @escaping () async -> Bool) async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first { $0.isKeyWindow }, window = UIWindow(windowScene: scene)
        window.frame = CGRect(origin: .zero, size: size)
        let host = UIHostingController(rootView: view.preferredColorScheme(.dark))
        window.rootViewController = host; window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil; previous?.makeKeyAndVisible() }
        host.view.layoutIfNeeded()
        var settled = false
        for _ in 0..<500 { if await ready() { settled = true; break }; try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertTrue(settled, "The profile requests did not complete for " + name)
        try await Task.sleep(for: .milliseconds(700))
        let image = UIGraphicsImageRenderer(size: size).image { _ in host.view.drawHierarchy(in: CGRect(origin: .zero, size: size), afterScreenUpdates: true) }
        let attachment = XCTAttachment(image: image); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}

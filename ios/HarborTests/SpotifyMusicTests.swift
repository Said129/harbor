import Foundation
import XCTest
@testable import Harbor

@MainActor private final class OwnedSpotifyScope { var value = PluginExecutionScope(owner: "owned-spotify-" + UUID().uuidString, activation: UUID()) }
@MainActor final class SpotifyMusicTests: XCTestCase {
    func testNewNativeSourceAndFreeAccountLabelsExistInAllSixteenLanguageBundles() throws {
        let file = try XCTUnwrap(Bundle.main.url(forResource: "NativeInterfaceTranslations", withExtension: "json"))
        let expected = try JSONDecoder().decode([String: [String: String]].self, from: Data(contentsOf: file))
        let keys = ["music.mobile.spotify.remote", "music.mobile.spotify.external", "music.mobile.soundcloud.consent", "music.mobile.spotify.install", "music.mobile.spotify.restricted", "music.mobile.spotify.advertisement"]
        var comparisons = 0
        for language in ["en", "ar", "zh", "fr", "de", "hi", "id", "it", "ja", "ko", "pl", "pt", "ru", "es", "tr", "vi"] {
            for key in keys {
                let translation = try XCTUnwrap(expected[language]?[key])
                XCTAssertEqual(DesktopInterfaceText.value(key, language: language), translation, language + ": " + key)
                XCTAssertFalse(translation.isEmpty); comparisons += 1
            }
        }
        XCTAssertEqual(comparisons, 96)
    }
    func testOnlyOfficialSpotifyLinksAndPlayableURIsAreAccepted() {
        let id = "0123456789ABCDEFGHIJKL"
        XCTAssertEqual(SpotifyMusicLink.uri("https://open.spotify.com/intl-es/track/\(id)?si=owned"), "spotify:track:" + id)
        XCTAssertEqual(SpotifyMusicLink.uri("spotify:playlist:" + id), "spotify:playlist:" + id)
        for input in ["https://open.spotify.com.attacker.invalid/track/" + id, "http://open.spotify.com/track/" + id, "spotify:track:bad", "spotify:unknown:" + id, "spotify:track:" + String(repeating: "é", count: 22)] { XCTAssertNil(SpotifyMusicLink.uri(input)) }
    }
    func testClientConfigurationIsOwnedAndAnUnsolicitedCallbackCannotConnectAnotherProfile() throws {
        let scope = OwnedSpotifyScope(), service = SpotifyMusicService(scope: scope.value, currentScope: { scope.value })
        defer { try? service.forget(); service.dispose() }
        let id = String(repeating: "a", count: 32)
        try service.saveClientID(id)
        let reopened = SpotifyMusicService(scope: scope.value, currentScope: { scope.value })
        XCTAssertEqual(reopened.clientID, id); reopened.dispose()
        let another = OwnedSpotifyScope(), other = SpotifyMusicService(scope: another.value, currentScope: { another.value })
        XCTAssertTrue(other.clientID.isEmpty); other.dispose()
        let callback = try XCTUnwrap(URL(string: SpotifyMusicService.redirect + "#access_token=owned-unrequested-token"))
        XCTAssertTrue(service.accept(callback))
        XCTAssertFalse(service.connected); XCTAssertNil(service.snapshot)
        XCTAssertFalse(service.accept(try XCTUnwrap(URL(string: "harbor-iphone://different-route#access_token=owned"))))
        XCTAssertThrowsError(try service.saveClientID("invalid")); XCTAssertEqual(service.clientID, id)
        let owner = scope.value
        scope.value = .init(owner: "retired", activation: UUID())
        XCTAssertThrowsError(try service.saveClientID(String(repeating: "b", count: 32)))
        XCTAssertFalse(service.connected)
        scope.value = owner
    }
}

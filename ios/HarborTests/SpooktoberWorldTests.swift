import CoreGraphics
import CryptoKit
import ImageIO
import XCTest
@testable import Harbor

@MainActor final class SpooktoberWorldTests: XCTestCase {
    func testAllPackagedOriginalWorldResourcesVerifyAndNativePostersDecodeWithoutHTTP() async throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "SpooktoberWorldAssets", withExtension: "json"))
        let manifest = try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: url))
        XCTAssertEqual(manifest["reference"].string, "0834340cec5531650bfe78cd628628702e636987")
        XCTAssertEqual(manifest["original_files_verified"].integer, 131)
        XCTAssertEqual(manifest["original_fonts_copied"], .bool(false))
        XCTAssertEqual(manifest["files"].objectValue.count, 99)
        for (path, entry) in manifest["files"].objectValue {
            let resource = try await SpooktoberWorldResources.shared.resource(path)
            XCTAssertEqual(resource.data.count, entry["bytes"].integer)
            XCTAssertEqual(SHA256.hash(data: resource.data).map { String(format: "%02x", $0) }.joined(), entry["sha256"].string)
        }
        for name in ["Inter", "Fraunces"] {
            let resource = try await SpooktoberWorldResources.shared.resource("native-fonts/" + name + ".ttf")
            let provider = try XCTUnwrap(CGDataProvider(data: resource.data as CFData)); XCTAssertNotNil(CGFont(provider))
        }
        let poster = try XCTUnwrap(manifest["files"].objectValue.keys.sorted().first { $0.hasPrefix("spooktober/assets/posters/") && ["jpg","png","webp"].contains(URL(fileURLWithPath: $0).pathExtension) })
        let bytes = try await ArtworkStore().data("harbor-spook://world/" + poster)
        XCTAssertGreaterThan(bytes.count, 100)
        XCTAssertNotNil(CGImageSourceCreateWithData(bytes as CFData, nil))
        XCTAssertNil(SpooktoberWorldResources.imagePath("harbor-spook://world/spooktober/native-runtime.js"))
        XCTAssertNil(SpooktoberWorldResources.path(URL(string: "harbor-spook://another/index.html")!))
        do { _ = try await SpooktoberWorldResources.shared.resource("../private.json"); XCTFail("Only declared bundled resources may be served") } catch { }
    }
    func testSixteenExecutedDesktopIntentsAndMusicMappingsRetainIdentityPayloadAndAllowedPlaylists() throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "spooktober-world-reference", withExtension: "json", subdirectory: "Fixtures"))
        let fixture = try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: url))
        XCTAssertEqual(fixture["actual_original_callback_and_music_mappers_executed"], .bool(true))
        XCTAssertEqual(fixture["original_modules"].objectValue.count, 3)
        XCTAssertEqual(Set(fixture["playlists"].array.compactMap(\.string)), SpooktoberWorldIntent.playlists)
        XCTAssertEqual(fixture["cases"].array.count, 16)
        func artwork(_ value: JSONValue) -> String {
            let raw = value.string ?? ""
            return raw.hasPrefix("/spooktober/") ? "harbor-spook://world" + raw : raw
        }
        for row in fixture["cases"].array {
            var fields = row.objectValue; fields["channel"] = .string("harbor-spooktober")
            let actual = SpooktoberWorldIntent.parse(.object(fields)), expected = row["expected"].array.first
            guard let expected else { XCTAssertNil(actual); continue }
            let value = try XCTUnwrap(actual)
            switch (value, expected["kind"].string) {
            case (.media(let media), "media"):
                let source = expected["media"]
                XCTAssertEqual(media.id, source["id"].string); XCTAssertEqual(media.type, source["type"].string)
                XCTAssertEqual(media.name, source["name"].string); XCTAssertEqual(media.releaseInfo, source["releaseInfo"].string)
                XCTAssertEqual(media.poster ?? "", artwork(source["poster"]))
                XCTAssertEqual(media.description ?? "", source["description"].string ?? "")
                XCTAssertEqual(media.genres ?? [], source["genres"].array.compactMap(\.string))
            case (.track(let track), "track"), (.video(let track), "video"):
                let source = expected["track"]
                XCTAssertEqual(track.id, source["id"].string); XCTAssertEqual(track.connectorId, source["connectorId"].string)
                XCTAssertEqual(track.sourceId, source["sourceId"].string); XCTAssertEqual(track.title, source["title"].string)
                XCTAssertEqual(track.artist, source["artist"].string); XCTAssertEqual(track.album, source["album"].string)
                XCTAssertEqual(track.artwork, artwork(source["artwork"])); XCTAssertEqual(Int(track.durationSeconds), source["durationSeconds"].integer)
                XCTAssertEqual(track.durationLabel, source["durationLabel"].string); XCTAssertEqual(track.mediaKind, source["mediaKind"].string)
            case (.playlist(let id), "playlist"): XCTAssertEqual(id, expected["id"].string)
            case (.external(let url), "external"): XCTAssertEqual(url.absoluteString, expected["url"].string)
            case (.back, "back"), (.reload, "reload"): break
            default: XCTFail("Native routing must retain the executed original intent kind")
            }
        }
        XCTAssertNil(SpooktoberWorldIntent.parse(.object(["channel": .string("foreign"), "intent": .string("back")])))
        XCTAssertNil(SpooktoberWorldIntent.externalURL("file:///private/account.json"))
        XCTAssertNil(SpooktoberWorldIntent.externalURL("https://owned-secret@example.org/"))
    }
    func testSeasonalSavedPicksMotionAndTeamPersistPerOwnerAndFailedWritesKeepTheDurableValue() throws {
        let disk = OwnedSpooktoberWorldPersistence()
        let first = SpooktoberWorldStore(owner: "owned-first", persistence: disk), second = SpooktoberWorldStore(owner: "owned-second", persistence: disk)
        XCTAssertTrue(first.ready); XCTAssertTrue(second.ready)
        try first.set("harbor-spookfest-list", value: "[\"tt0077651\"]")
        try first.set("harbor-spookfest-motion", value: "off")
        try first.set("spooktober-twilight-team", value: "jacob")
        let reopened = SpooktoberWorldStore(owner: first.owner, persistence: disk)
        XCTAssertEqual(reopened.values, first.values); XCTAssertTrue(second.values.isEmpty)
        let baseline = first.values; disk.failWrite = true
        XCTAssertThrowsError(try first.set("spooktober-twilight-team", value: "edward")); XCTAssertEqual(first.values, baseline)
        XCTAssertEqual(SpooktoberWorldStore(owner: first.owner, persistence: disk).values, baseline)
        disk.failWrite = false
        XCTAssertThrowsError(try first.set("account-token", value: "must-not-persist"))
        XCTAssertThrowsError(try first.set("harbor-spookfest-list", value: "{\"invalid\":true}"))
        XCTAssertEqual(first.values, baseline)
        disk.failRead = true
        let failed = SpooktoberWorldStore(owner: first.owner, persistence: disk)
        XCTAssertFalse(failed.ready); XCTAssertThrowsError(try failed.set("harbor-spookfest-list", value: "[]"))
        disk.failRead = false; XCTAssertEqual(SpooktoberWorldStore(owner: first.owner, persistence: disk).values, baseline)
    }
}
@MainActor final class OwnedSpooktoberWorldPersistence: SpooktoberWorldPersistence {
    var values: [String: [String: String]] = [:]
    var failRead = false, failWrite = false
    func read(owner: String) throws -> [String: String]? { if failRead { throw HarborError(code: "owned-read") }; return values[owner] }
    func write(_ value: [String: String], owner: String) throws { if failWrite { throw HarborError(code: "owned-write") }; values[owner] = value }
}

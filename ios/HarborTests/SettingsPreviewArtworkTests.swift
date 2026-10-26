import XCTest
import UIKit
import CryptoKit
@testable import Harbor

private actor OwnedSettingsSampleFetch {
    let responses: [String: JSONValue]
    private(set) var paths: [String] = []
    init(_ responses: [String: JSONValue]) { self.responses = responses }
    func get(_ url: String) async throws -> JSONValue {
        paths.append(url); try await Task.sleep(for: .milliseconds(15))
        guard let value = responses[url] else { throw HarborError(code: "owned-offline-preview") }; return value
    }
}

final class SettingsPreviewArtworkTests: XCTestCase {
    func testAllFiveOriginalDesktopImagesAreBundledDecodableAndCannotReadArbitraryFiles() async throws {
        let films = SettingsPreviewArtwork.films; XCTAssertEqual(films.count, 4); XCTAssertEqual(films.first?.name, "The General")
        let manifestURL = try XCTUnwrap(Bundle.main.url(forResource: "source", withExtension: "json", subdirectory: "SettingsPreview"))
        let manifest = try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: manifestURL))
        XCTAssertEqual(manifest["reference"].string, "0834340cec5531650bfe78cd628628702e636987")
        XCTAssertEqual(manifest["unchanged_decoded_pixels"], .bool(true)); XCTAssertEqual(manifest["images"].array.count, 5)
        let urls = Set(films.flatMap { [$0.poster, $0.background].compactMap { $0 } }); XCTAssertEqual(urls.count, 5)
        let store = ArtworkStore()
        for raw in urls {
            let resource = try XCTUnwrap(SettingsPreviewArtwork.resource(raw)), data = try await store.data(raw)
            let record = try XCTUnwrap(manifest["images"].array.first { $0["file"].string == resource.lastPathComponent })
            XCTAssertEqual(SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(), record["sha256"].string)
            let bitmap = try await ArtworkBitmapDecoder.thumbnail(data, maxPixels: 240)
            XCTAssertGreaterThan(bitmap.image.size.width, 0); XCTAssertLessThanOrEqual(max(bitmap.image.size.width, bitmap.image.size.height), 240)
            XCTAssertTrue(SettingsPreviewArtwork.usablePoster(data))
        }
        for raw in ["file:///etc/hosts", "harbor-settings-preview://../Info.plist", "harbor-settings-preview://the-general-poster/../../Info.plist", "https://owned.invalid/the-general-poster"] {
            XCTAssertNil(SettingsPreviewArtwork.resource(raw))
        }
    }
    @MainActor func testLiveSamplesRejectPlaceholdersAdultAndUnratedTitlesCoalesceAndKeepTheVerifiedPoster() async throws {
        let valid = try Data(contentsOf: XCTUnwrap(SettingsPreviewArtwork.resource(SettingsPreviewArtwork.films[0].poster!)))
        let black = UIGraphicsImageRenderer(size: .init(width: 32, height: 32)).pngData { context in UIColor.black.setFill(); context.fill(.init(x: 0, y: 0, width: 32, height: 32)) }
        let white = UIGraphicsImageRenderer(size: .init(width: 32, height: 32)).pngData { context in UIColor.white.setFill(); context.fill(.init(x: 0, y: 0, width: 32, height: 32)) }
        XCTAssertFalse(SettingsPreviewArtwork.usablePoster(black)); XCTAssertFalse(SettingsPreviewArtwork.usablePoster(white))
        func media(_ id: String, rating: String = "8", adult: Bool = false) -> JSONValue {
            .object(["id": .string(id), "name": .string(id), "poster": .string("https://owned.invalid/" + id), "background": .string("https://owned.invalid/wide"), "imdbRating": .string(rating), "adult": .bool(adult)])
        }
        let series = "https://v3-cinemeta.strem.io/catalog/series/top.json", detail = "https://v3-cinemeta.strem.io/meta/series/tt1234567.json"
        var missingBackground = media("empty-background").objectValue; missingBackground["background"] = .string("")
        let fetch = OwnedSettingsSampleFetch([series: .object(["metas": .array([media("unrated", rating: "0"), media("adult", adult: true), .object(missingBackground), media("black"), media("tt1234567")])]),
            detail: .object(["meta": .object(["id": .string("tt1234567"), "name": .string("Owned usable sample"), "description": .string("Full description"), "poster": .string("https://owned.invalid/unverified")])])])
        let service = SettingsPreviewSamples(fetch: { try await fetch.get($0) }, image: { $0.hasSuffix("black") ? black : valid })
        let values = await withTaskGroup(of: [Media].self) { group in
            for _ in 0..<8 { group.addTask { await service.samples() } }
            var result: [[Media]] = []; for await value in group { result.append(value) }; return result
        }
        XCTAssertEqual(values.count, 8)
        XCTAssertTrue(values.allSatisfy { $0.count == 1 && $0[0].name == "Owned usable sample" && $0[0].poster == "https://owned.invalid/tt1234567" && $0[0].description == "Full description" })
        _ = await service.samples()
        let paths = await fetch.paths; XCTAssertEqual(paths, [series, detail])
    }
    func testOfflineAndEmptyProvidersReturnTheOriginalFourSamplesAndDoNotRetryOnEverySettingChange() async {
        let fetch = OwnedSettingsSampleFetch(["https://v3-cinemeta.strem.io/catalog/series/top.json": .object(["metas": .array([])])])
        let service = SettingsPreviewSamples(fetch: { try await fetch.get($0) }, image: { _ in throw HarborError(code: "owned-no-images") })
        let first = await service.samples(), second = await service.samples()
        XCTAssertEqual(first, SettingsPreviewArtwork.films); XCTAssertEqual(second, first)
        let paths = await fetch.paths
        XCTAssertEqual(paths, ["https://v3-cinemeta.strem.io/catalog/series/top.json", "https://v3-cinemeta.strem.io/catalog/movie/top.json"])
    }
}

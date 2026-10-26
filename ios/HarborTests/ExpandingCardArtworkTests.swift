import XCTest
import UIKit
@testable import Harbor

private actor OwnedWideArtworkFetch {
    private(set) var urls: [String] = []
    private(set) var providerCalls = 0
    let responses: [String: Data]
    init(_ responses: [String: Data]) { self.responses = responses }
    func get(_ url: String) async throws -> Data {
        urls.append(url); try await Task.sleep(for: .milliseconds(15))
        guard let value = responses[url] else { throw HarborError(code: "owned-image-missing") }; return value
    }
    func candidates(_ values: [String]) -> [String] { providerCalls += 1; return values }
}

@MainActor final class ExpandingCardArtworkTests: XCTestCase {
    private var configuration: MetadataConfiguration { .init(tmdbKey: "", region: "US", language: "en-US", translateTitles: true) }
    private func png(_ width: CGFloat, _ height: CGFloat) -> Data {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        return UIGraphicsImageRenderer(size: .init(width: width, height: height), format: format).pngData { context in
            UIColor.green.setFill(); context.fill(.init(x: 0, y: 0, width: width, height: height))
        }
    }
    func testActualWideImageMetadataCoalescesEightMountedRequestsAndAvoidsUnnecessaryProviderLookups() async {
        let url = "https://owned.invalid/own-wide.png", fetch = OwnedWideArtworkFetch(["https://owned.invalid/own-wide.png": png(1024, 576)])
        let service = ExpandingCardArtwork(image: { try await fetch.get($0) }, candidates: { _, _ in await fetch.candidates([]) })
        var media = Media(id: "owned-wide", type: "movie", name: "Owned wide"); media.poster = "https://owned.invalid/poster.png"; media.background = url
        let input = media, config = configuration
        let values = await withTaskGroup(of: String?.self) { group in
            for _ in 0..<8 { group.addTask { await service.prepare(input, configuration: config) } }
            var values: [String?] = []; for await value in group { values.append(value) }; return values
        }
        XCTAssertEqual(values.count, 8); XCTAssertTrue(values.allSatisfy { $0 == url })
        _ = await service.prepare(input, configuration: config)
        let urls = await fetch.urls, calls = await fetch.providerCalls
        XCTAssertEqual(urls, [url]); XCTAssertEqual(calls, 0)
    }
    func testRejectsPortraitSmallAndUndecodableCandidatesThenInvalidatesTheFailedMountedImageAndPartitionsPreferences() async {
        let base = "https://owned.invalid/", valid = png(1280, 720)
        let fetch = OwnedWideArtworkFetch([base + "portrait": png(720, 1280), base + "small": png(320, 180), base + "broken": Data("not an image".utf8), base + "wide": valid, base + "second": valid])
        let candidates = ["portrait", "small", "broken", "wide", "wide", "second"].map { base + $0 }
        let service = ExpandingCardArtwork(image: { try await fetch.get($0) }, candidates: { _, _ in await fetch.candidates(candidates) })
        var media = Media(id: "owned-fallback", type: "movie", name: "Owned fallback"); media.poster = base + "portrait"; media.background = base + "portrait"
        let first = await service.prepare(media, configuration: configuration); XCTAssertEqual(first, base + "wide")
        await service.invalidate(key: ExpandingCardArtwork.key(media, configuration), url: base + "wide")
        let second = await service.prepare(media, configuration: configuration); XCTAssertEqual(second, base + "second")
        var changed = configuration; changed.imageLanguages = ["Spanish", "Original"]
        let key = ExpandingCardArtwork.key(media, configuration)
        XCTAssertNotEqual(key, ExpandingCardArtwork.key(media, changed)); XCTAssertFalse(key.contains(media.id))
        _ = await service.prepare(media, configuration: changed)
        let urls = await fetch.urls, calls = await fetch.providerCalls
        XCTAssertFalse(urls.contains(base + "portrait")); XCTAssertEqual(urls.filter { $0 == base + "wide" }.count, 1); XCTAssertEqual(calls, 3)
    }
    func testAnUnusableTitleAttemptsOnlyTheFirstEightUniqueAlternatives() async {
        let fetch = OwnedWideArtworkFetch([:]), candidates = (0..<14).map { "https://owned.invalid/\($0).png" }
        let service = ExpandingCardArtwork(image: { try await fetch.get($0) }, candidates: { _, _ in await fetch.candidates(candidates) })
        let value = await service.prepare(Media(id: "owned-empty", type: "movie", name: "Empty"), configuration: configuration)
        XCTAssertNil(value)
        let urls = await fetch.urls; XCTAssertEqual(urls, Array(candidates.prefix(8)))
    }
}

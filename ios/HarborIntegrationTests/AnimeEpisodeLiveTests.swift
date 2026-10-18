import UIKit
import XCTest
@testable import Harbor

final class AnimeEpisodeLiveTests: XCTestCase {
    func testActualSuperMetadataAndImagesBeyondFourteen() async throws {
        let response = try await HTTPClient().json("https://v3-cinemeta.strem.io/meta/series/tt4644488.json")
        let source = try XCTUnwrap(Media.parse(response["meta"], kind: "series"))
        let episodes = await AnimeEpisodeService().episodes(for: source)
        XCTAssertEqual(Set(episodes.filter { ($0.season ?? 0) > 0 }.compactMap(\.listedSeason)), [1])
        XCTAssertEqual(Set(episodes.filter { ($0.season ?? 0) > 0 }.compactMap(\.listedEpisode)), Set(1...131))
        for number in [15, 77, 131] {
            let episode = try XCTUnwrap(episodes.first { $0.listedEpisode == number && $0.season != 0 })
            let raw = try XCTUnwrap(episode.thumbnail)
            XCTAssertEqual(URL(string: raw)?.host, "artworks.thetvdb.com")
            let data = try await ArtworkStore().data(raw)
            let image = try XCTUnwrap(UIImage(data: data))
            XCTAssertGreaterThan(image.size.width, 100); XCTAssertGreaterThan(image.size.height, 50)
            let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.jpeg")
            attachment.name = "actual-super-episode-\(number)"; attachment.lifetime = .keepAlways; add(attachment)
        }
    }
}

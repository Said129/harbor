import UIKit
import XCTest
@testable import Harbor

final class ContinuationParityLiveTests: XCTestCase {
    func testActualIMDbAnimeMappingAndEpisodeNinetyNinePresentation() async throws {
        let response = try await HTTPClient().json("https://v3-cinemeta.strem.io/meta/series/tt4644488.json")
        var media = try XCTUnwrap(Media.parse(response["meta"], kind: "series"))
        let service = AnimeEpisodeService()
        let matched = await service.hasAnimeIdentity(for: media)
        XCTAssertTrue(matched)
        media.videos = await service.episodes(for: media)
        let target = ResumeTarget(id: media.id, season: 5, episode: 23, videoId: "tt4644488:5:23")
        XCTAssertEqual(EpisodePresentation.coordinates(in: media, target: target)?.caption, "T1 · E99")
        let episode = try XCTUnwrap(EpisodePresentation.episode(in: media, target: target))
        let url = try XCTUnwrap(episode.thumbnail)
        let bytes = try await ArtworkStore().data(url)
        let image = try XCTUnwrap(UIImage(data: bytes))
        XCTAssertGreaterThan(image.size.width, 100)
        let attachment = XCTAttachment(data: bytes, uniformTypeIdentifier: "public.jpeg")
        attachment.name = "actual-super-episode-99"; attachment.lifetime = .keepAlways; add(attachment)
    }
}

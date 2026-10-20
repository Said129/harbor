import XCTest
@testable import Harbor

final class AnimeFranchiseExtraLiveTests: XCTestCase {
    func testActualKitsuMovieKeepsItsDefaultVideoIdentityAndVerifiedIMDbFallback() async throws {
        let entry = AnimeFranchiseEntry(media: Media(id: "kitsu:41046", type: "movie", name: "Dragon Ball Super: Broly"),
            year: 2018, startDate: "2018-12-14", episodeCount: 1, subtype: "movie", current: false, upcoming: false)
        let media = try await AnimeFranchiseEpisodeService.shared.metadata(for: entry, language: "en")
        XCTAssertEqual(media.id, entry.id); XCTAssertEqual(media.type, "movie")
        XCTAssertTrue(AnimeOneOffPresentation.isOneOff(media))
        XCTAssertEqual(media.behaviorHints?.defaultVideoId, entry.id)
        XCTAssertNil(AnimeOneOffPresentation.playbackEpisode(media), "The actual provider uses its movie ID, not a fabricated :1 suffix")
        let ids = StreamRequestPolicy.ids(media, videoID: media.behaviorHints?.defaultVideoId ?? media.id, season: nil, episode: nil)
        XCTAssertEqual(ids.first, entry.id)
        XCTAssertTrue(ids.contains("tt7961060"), "The provider's verified IMDb movie fallback must remain usable by IMDb-only addons")
        let summary = JSONValue.object(["id": .string(media.id), "type": .string(media.type),
            "defaultVideoId": .string(media.behaviorHints?.defaultVideoId ?? ""), "imdb_id": .string(media.imdbID ?? ""),
            "provider_video_ids": .array((media.videos ?? []).map { .string($0.id) }), "stream_ids": .array(ids.map(JSONValue.string))])
        let attachment = XCTAttachment(data: try JSONEncoder().encode(summary), uniformTypeIdentifier: "public.json")
        attachment.name = "actual-public-movie-source-identity"; attachment.lifetime = .keepAlways; add(attachment)
    }
}

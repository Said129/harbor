import UIKit
import XCTest
@testable import Harbor

final class TVDBProxyLiveTests: XCTestCase {
    func testCommunityProxyReturnsSuperSeasonsEpisodesAndAnActualStill() async throws {
        let service = TVDBService()
        let hits = try await service.data(.remote("tt4644488"))
        XCTAssertTrue(hits.array.contains { $0["series"]["id"].integer == 295068 })
        let series = try await service.data(.series(295068))
        XCTAssertEqual(series["id"].integer, 295068)
        XCTAssertTrue(series["seasons"].array.contains { $0["type"]["type"].string == "official" })
        let episodes = try await service.episodes(series: 295068)
        let regular = episodes.filter { $0.season > 0 }
        XCTAssertEqual(regular.count, 131)
        let episode = try XCTUnwrap(regular.first { $0.absolute == 99 })
        XCTAssertEqual(episode.season, 5); XCTAssertEqual(episode.number, 23)
        let url = try XCTUnwrap(episode.image)
        let bytes = try await ArtworkStore().data(url)
        let image = try XCTUnwrap(UIImage(data: bytes))
        XCTAssertGreaterThan(image.size.width, 100); XCTAssertGreaterThan(image.size.height, 50)
        let attachment = XCTAttachment(data: bytes, uniformTypeIdentifier: "public.jpeg")
        attachment.name = "community-tvdb-super-99-original"; attachment.lifetime = .keepAlways; add(attachment)
    }
}

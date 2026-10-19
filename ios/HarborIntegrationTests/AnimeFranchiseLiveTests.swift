import Foundation
import XCTest
@testable import Harbor

final class AnimeFranchiseLiveTests: XCTestCase {
    func testPublicKitsuResourcesAndVerifiedMappingDescribeTheSameAnime() async throws {
        let provider = AnimeFranchiseService.shared
        let mapping = try await provider.response(.mapping("tt4644488"))
        let id = try XCTUnwrap(mapping["mappings"]["kitsu_id"].integer)
        XCTAssertGreaterThan(id, 0)
        let resource = try await provider.response(.kitsu(id))
        let entry = try XCTUnwrap(AnimeFranchiseEntry.kitsu(resource["data"], currentID: id, now: Date()))
        XCTAssertEqual(entry.id, "kitsu:\(id)"); XCTAssertTrue(entry.current); XCTAssertFalse(entry.extra)
        XCTAssertEqual(entry.episodeCount, 131)
        let related = try await provider.response(.related(id))
        guard case .array(let relations) = related["data"] else { return XCTFail("Expected the actual public relationship document") }
        XCTAssertFalse(relations.isEmpty)
        XCTAssertTrue(related["included"].array.contains { $0["type"].string == "anime" })
        let summary: JSONValue = .object(["imdb": .string("tt4644488"), "kitsu": .string(entry.id),
            "title": .string(entry.media.name), "episodes": .integer(Int64(entry.episodeCount ?? 0)), "public_relationship_count": .integer(Int64(relations.count))])
        let data = try JSONEncoder().encode(summary)
        let attachment = XCTAttachment(string: String(decoding: data, as: UTF8.self))
        attachment.name = "anime-franchise-public-metadata-contract"; attachment.lifetime = .keepAlways; add(attachment)
    }
}

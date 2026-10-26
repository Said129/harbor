import XCTest
@testable import Harbor

final class CardArtworkPublicTests: XCTestCase {
    func testActualAnonymousNativeTVDBArtworkRequestReturnsWideArtAndLogosWithoutAnyPersonalAccount() async throws {
        let request = CardArtworkRequest.tvdb(295068)
        let configuration = MetadataConfiguration(tmdbKey: "owned-synthetic-key-never-sent", region: "US", language: "en-US", translateTitles: false)
        XCTAssertFalse(request.credentialed)
        XCTAssertFalse(try request.url(configuration: configuration).contains(configuration.tmdbKey))
        let response = try await CardArtworkHTTPTransport().get(request, configuration: configuration)
        XCTAssertNotNil(response["clearLogos"].array.compactMap { CardArtworkPolicy.image($0.string) }.first)
        XCTAssertNotNil(response["backgrounds"].array.compactMap { CardArtworkPolicy.image($0.string) }.first)
    }
}

import XCTest
@testable import Harbor

final class F3ArtworkResolveTests: XCTestCase {
    func testIMDbTitlesResolveTheirLogoOnlyOnTheTitlePage() {
        XCTAssertTrue(CardArtworkResolver.canResolve(Media(id: "tt1234567", type: "movie", name: "Owned title"), imdbLogo: true))
        XCTAssertTrue(CardArtworkResolver.canResolve(Media(id: "tt1234567", type: "series", name: "Show"), imdbLogo: true))
        XCTAssertFalse(CardArtworkResolver.canResolve(Media(id: "tt1234567", type: "movie", name: "Card")))
    }

    func testTMDBIdsStillResolveTheirLogo() {
        XCTAssertTrue(CardArtworkResolver.canResolve(Media(id: "tmdb:movie:603", type: "movie", name: "The Matrix")))
    }

    func testOtherIdsAndTypesKeepTheMetadataLogo() {
        XCTAssertFalse(CardArtworkResolver.canResolve(Media(id: "tt12", type: "movie", name: "Short id"), imdbLogo: true))
        XCTAssertFalse(CardArtworkResolver.canResolve(Media(id: "tt1234567", type: "channel", name: "Channel"), imdbLogo: true))
        XCTAssertFalse(CardArtworkResolver.canResolve(Media(id: "local-title-1", type: "movie", name: "Local"), imdbLogo: true))
    }
}

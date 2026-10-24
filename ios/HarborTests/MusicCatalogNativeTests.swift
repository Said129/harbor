import XCTest
import UIKit
@testable import Harbor

@MainActor final class MusicCatalogNativeTests: XCTestCase {
    func testConnectionEmptySearchAndRejectedRequestCrossTheActualNativeCatalogABI() async throws {
        let client = MusicCatalogClient()
        let connection = try await client.connection()
        XCTAssertEqual(connection.id, "catalog"); XCTAssertTrue(connection.anonymous); XCTAssertEqual(connection.capabilities, ["search", "browse"])
        let empty = try await client.search("  ", limit: 2)
        XCTAssertTrue(empty.albums.isEmpty && empty.tracks.isEmpty && empty.artists.isEmpty && empty.playlists.isEmpty)
        let rejected = try await HarborNativeNetwork().performMusicCatalog(.init(operation: "search", query: String(repeating: "a", count: 201), limit: 2))
        XCTAssertFalse(rejected.ok); XCTAssertEqual(rejected.status, 503)
        do {
            _ = try await HarborNativeNetwork().performMusicCatalog(.init(operation: "notAnOperation"))
            XCTFail("Unknown native operations must be rejected")
        } catch let failure as HarborError { XCTAssertEqual(failure.code, "music-catalog-request-format") }
    }
    func testActualPublicMusicSearchAlbumTracksAndArtworkKeepTheirProviderIdentity() async throws {
        let client = MusicCatalogClient(), result = try await client.search("Beethoven", limit: 2)
        let album = try XCTUnwrap(result.albums.first)
        XCTAssertEqual(album.connectorId, "catalog"); XCTAssertTrue(album.id.hasPrefix("itunes:album:")); XCTAssertFalse(album.title.isEmpty)
        let tracks = try await client.albumTracks(album)
        XCTAssertFalse(tracks.isEmpty); XCTAssertTrue(tracks.allSatisfy { $0.connectorId == "catalog" && $0.id.hasPrefix("itunes:track:") && $0.playbackUrl == nil })
        let image = try await ArtworkStore.shared.data(album.artwork)
        XCTAssertNotNil(UIImage(data: image), "The actual public cover must decode through the shared bounded artwork loader")
    }
}

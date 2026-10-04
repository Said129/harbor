import XCTest
@testable import Harbor

/// Opt-in network integration. These use the production service and embedded
/// C ABI; no catalog, metadata, stream or player response is substituted.
@MainActor
final class LiveServicesTests: XCTestCase {
    private let service = HarborService()
    private let publicAddon = "https://raw.githubusercontent.com/Stremio/stremio-static-addon-example/master/manifest.json"

    private func requireOptIn() throws {
        guard ProcessInfo.processInfo.environment["HARBOR_LIVE_INTEGRATION"] == "1" else {
            throw XCTSkip("Live integration requires explicit opt-in")
        }
    }

    func testCinemetaCatalogSearchAndMetadataThroughNativeService() async throws {
        try requireOptIn()
        let addon = try await service.install(HarborService.cinemetaManifest)
        let (catalogs, _) = try await service.catalogs([addon])
        XCTAssertFalse(catalogs.isEmpty)
        let preview = try XCTUnwrap(catalogs.flatMap(\.metas).first)
        let metadata = try await service.metadata(preview, addons: [addon])
        XCTAssertEqual(metadata.id, preview.id)
        XCTAssertFalse(metadata.name.isEmpty)
        let (results, _) = try await service.catalogs([addon], search: "Interstellar")
        let count = results.reduce(0) { $0 + $1.metas.count }
        XCTAssertGreaterThan(count, 0)
        XCTAssertTrue(results.flatMap(\.metas).contains { $0.id == "tt0816692" && $0.name == "Interstellar" }, "The real movie query must return its matching metadata identity")
        print("Harbor live Cinemeta: catalogs=\(catalogs.count) searchItems=\(count) metadata=passed")
    }

    func testOfficialAddonCatalogMetadataStreamsAndResolution() async throws {
        try requireOptIn()
        // This addon is installed within the test only; it is not an app default.
        let addon = try await service.install(publicAddon)
        let (catalogs, _) = try await service.catalogs([addon])
        let preview = try XCTUnwrap(catalogs.flatMap(\.metas).first)
        let metadata = try await service.metadata(preview, addons: [addon])
        let videoID = metadata.behaviorHints?.defaultVideoId ?? metadata.id
        let (offers, _) = try await service.streams(metadata, videoID: videoID, addons: [addon])
        let offer = try XCTUnwrap(offers.first)
        let source = try await service.resolve(offer)
        XCTAssertTrue(["http", "https"].contains(URL(string: source.url)?.scheme ?? ""))
        XCTAssertEqual(source.via, "direct")
        print("Harbor live official addon: catalogs=\(catalogs.count) offers=\(offers.count) resolution=passed; media transport unverified")
    }
}

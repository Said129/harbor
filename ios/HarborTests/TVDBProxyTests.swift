import XCTest
@testable import Harbor

private actor TVDBFixtureTransport: TVDBTransport {
    var requests: [TVDBRequest] = []
    var replies: [TVDBRequest: JSONValue]
    var fail = false
    init(_ replies: [TVDBRequest: JSONValue] = [:]) { self.replies = replies }
    func failing(_ value: Bool) { fail = value }
    func count() -> Int { requests.count }
    func replace(_ request: TVDBRequest, with response: JSONValue) { replies[request] = response }
    func get(_ request: TVDBRequest) async throws -> JSONValue {
        requests.append(request)
        try await Task.sleep(for: .milliseconds(20))
        if fail { throw HarborError(code: "http-503") }
        guard let value = replies[request] else { throw HarborError(code: "http-404") }
        return value
    }
}

final class TVDBProxyTests: XCTestCase {
    private func json(_ value: String) throws -> JSONValue { try JSONDecoder().decode(JSONValue.self, from: Data(value.utf8)) }
    private func row(_ id: Int, season: Int, number: Int, absolute: Int, image: String = "/banners/synthetic.jpg") throws -> TVDBEpisodeMetadata {
        try XCTUnwrap(TVDBEpisodeMetadata(json("""
        {"id":\(id),"seasonNumber":\(season),"number":\(number),"absoluteNumber":\(absolute),"image":"\(image)","name":"Synthetic"}
        """)))
    }

    func testOnlyPublicMetadataRoutesUseTheReplacementWithoutAccountHeadersOrBody() throws {
        for endpoint in [TVDBRequest.remote("tt4644488"), .series(295068), .episodes(series: 295068, order: "default", language: "spa", page: 0)] {
            let request = try HTTPClient.tvdbRequest(endpoint)
            XCTAssertEqual(request.url?.scheme, "https"); XCTAssertEqual(request.url?.host, "harborcommunity.site")
            XCTAssertTrue(request.url?.path.hasPrefix("/api/tvdb/v4/") == true)
            XCTAssertEqual(request.httpMethod, "GET"); XCTAssertNil(request.httpBody)
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization")); XCTAssertNil(request.value(forHTTPHeaderField: "Cookie"))
        }
        for bad in [TVDBRequest.remote("tt4644488/../login"), .series(0), .episodes(series: 1, order: "../auth", language: nil, page: 0),
                    .episodes(series: 1, order: "default", language: "spa?apikey=x", page: 0), .episodes(series: 1, order: "default", language: nil, page: 20)] {
            XCTAssertThrowsError(try HTTPClient.tvdbRequest(bad))
        }
    }

    func testConcurrentRequestsShareOneFetchAndInvalidResponsesAreNotCached() async throws {
        let endpoint = TVDBRequest.series(295068)
        let transport = TVDBFixtureTransport([endpoint: try json(#"{"data":{"id":295068}}"#)])
        let service = TVDBService(transport: transport)
        async let one = service.data(endpoint)
        async let two = service.data(endpoint)
        let values = try await [one, two]
        XCTAssertEqual(values.count, 2)
        _ = try await service.data(endpoint)
        let count = await transport.count(); XCTAssertEqual(count, 1)

        let other = TVDBRequest.series(9)
        await transport.replace(other, with: try json(#"{"data":{"id":999}}"#))
        do { _ = try await service.data(other); XCTFail("Wrong series must fail") } catch {}
        await transport.replace(other, with: try json(#"{"data":{"id":9}}"#))
        let recovered = try await service.data(other)
        XCTAssertEqual(recovered["id"].integer, 9)
        let finalCount = await transport.count(); XCTAssertEqual(finalCount, 3)
    }

    func testStillsKeepSeasonsAbsoluteLabelsPlaybackAndWatchedIdentity() throws {
        let rows = try [row(1, season: 5, number: 23, absolute: 99), row(2, season: 5, number: 24, absolute: 100)]
        let source = [Episode(id: "tt4644488:5:23", season: 5, episode: 23, thumbnail: "https://images.metahub.space/old.jpg", displaySeason: 1, displayEpisode: 99),
                      Episode(id: "tt4644488:5:24", season: 5, episode: 24, thumbnail: "https://example.org/keep.jpg", displaySeason: 1, displayEpisode: 100)]
        let result = TVDBEpisodeMetadata.applying(rows, to: source, animeIdentity: false)
        XCTAssertEqual(result.map(\.id), source.map(\.id)); XCTAssertEqual(result.map(\.watchedKey), source.map(\.watchedKey))
        XCTAssertEqual(result.map(\.listedEpisode), [99, 100]); XCTAssertEqual(result.map(\.listedSeason), [1, 1])
        XCTAssertEqual(result.first?.thumbnail, "https://artworks.thetvdb.com/banners/synthetic.jpg")
        XCTAssertEqual(result.last?.thumbnail, source.last?.thumbnail)
        let seasonal = source.map { episode in var value = episode; value.displaySeason = nil; value.displayEpisode = nil; return value }
        let seasons = TVDBEpisodeMetadata.applying(rows, to: seasonal, animeIdentity: false)
        XCTAssertEqual(seasons.map(\.listedSeason), [5, 5]); XCTAssertEqual(seasons.map(\.listedEpisode), [23, 24])
    }

    func testCourLocalNumbersAndAmbiguousCoordinatesCannotBorrowAnotherEpisodesArtwork() throws {
        let rows = try [row(1, season: 1, number: 1, absolute: 1), row(2, season: 2, number: 1, absolute: 2)]
        let local = [Episode(id: "kitsu:99:1", season: 1, episode: 1)]
        XCTAssertNil(TVDBEpisodeMetadata.applying(rows, to: local, animeIdentity: true).first?.thumbnail)
        var mapped = local[0]; mapped.imdbSeason = 2; mapped.imdbEpisode = 1
        XCTAssertNotNil(TVDBEpisodeMetadata.applying(rows, to: [mapped], animeIdentity: true).first?.thumbnail)
        let duplicate = try row(3, season: 2, number: 1, absolute: 3)
        XCTAssertNil(TVDBEpisodeMetadata.applying(rows + [duplicate], to: [mapped], animeIdentity: true).first?.thumbnail)
        for bad in ["//example.org/x", "http://artworks.thetvdb.com/x", "https://artworks.thetvdb.com.evil.example/x", "https://user:pass@artworks.thetvdb.com/x"] {
            XCTAssertNil(TVDBEpisodeMetadata.imageURL(bad))
        }
    }

    func testUnavailableProxyKeepsTheOriginalVariantsAndRetryCanRecover() async throws {
        let request = TVDBRequest.episodes(series: 295068, order: "default", language: nil, page: 0)
        let transport = TVDBFixtureTransport([request: try json(#"{"data":{"episodes":[{"id":1,"seasonNumber":5,"number":23,"absoluteNumber":99,"image":"/banners/synthetic.jpg"}]}}"#)])
        let service = TVDBService(transport: transport)
        let episodes = [Episode(id: "tt4644488:5:23", season: 5, episode: 23)]
        let variants = AnimeEpisodeVariants(seasons: episodes, continuous: episodes, tvdbSeriesID: 295068)
        let media = Media(id: "tt4644488", type: "series", name: "Synthetic", videos: episodes)
        await transport.failing(true)
        let failed = await service.supplement(variants, for: media)
        XCTAssertEqual(failed.seasons, episodes); XCTAssertEqual(failed.continuous, episodes)
        await transport.failing(false)
        let recovered = await service.supplement(variants, for: media)
        XCTAssertNotNil(recovered.seasons.first?.thumbnail)
        let count = await transport.count(); XCTAssertEqual(count, 2)
    }

    func testRepeatingFullPageFailsRatherThanReturningAPartialEpisodeList() async throws {
        let row = #"{"id":1,"seasonNumber":1,"number":1,"absoluteNumber":1}"#
        let response = try json("{\"data\":{\"episodes\":[" + Array(repeating: row, count: 500).joined(separator: ",") + "]}}")
        let transport = TVDBFixtureTransport([
            .episodes(series: 1, order: "default", language: nil, page: 0): response,
            .episodes(series: 1, order: "default", language: nil, page: 1): response])
        do { _ = try await TVDBService(transport: transport).episodes(series: 1); XCTFail("Repeating page must fail") } catch {}
        let count = await transport.count(); XCTAssertEqual(count, 2)
    }
}

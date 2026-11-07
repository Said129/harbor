import XCTest
@testable import Harbor

final class SimklBatchingTests: XCTestCase {
    private actor Requests {
        private var urls: [URL] = []
        func add(_ url: URL) { urls.append(url) }
        func all() -> [URL] { urls }
    }

    private func reply(_ json: String) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))
    }

    func testCardLookupsMadeTogetherShareOneRequest() async throws {
        let requests = Requests()
        let body = try reply(#"{"ratings":{"imdb:tt1":{"rating":8.1},"imdb:tt2":{"rating":7.2}}}"#)
        let ratings = SimklCommunityRatings(fetch: { (url: URL) -> JSONValue in
            await requests.add(url)
            return body
        })
        async let first = ratings.coalescedRating("imdb:tt1")
        async let second = ratings.coalescedRating("imdb:tt2")
        async let third = ratings.coalescedRating("imdb:tt3")
        let values = await [first, second, third]
        XCTAssertEqual(values[0], 8.1)
        XCTAssertEqual(values[1], 7.2)
        XCTAssertNil(values[2])
        let urls = await requests.all()
        XCTAssertEqual(urls.count, 1)
        let text = (urls.first?.absoluteString ?? "").removingPercentEncoding ?? ""
        XCTAssertTrue(text.contains("imdb:tt1"))
        XCTAssertTrue(text.contains("imdb:tt2"))
        XCTAssertTrue(text.contains("imdb:tt3"))
    }

    func testAnAnsweredScoreIsNotAskedAgain() async throws {
        let requests = Requests()
        let body = try reply(#"{"ratings":{"imdb:tt1":{"rating":9.0}}}"#)
        let ratings = SimklCommunityRatings(fetch: { (url: URL) -> JSONValue in
            await requests.add(url)
            return body
        })
        let first = await ratings.coalescedRating("imdb:tt1")
        let second = await ratings.coalescedRating("IMDB:TT1")
        XCTAssertEqual(first, 9.0)
        XCTAssertEqual(second, 9.0)
        let urls = await requests.all()
        XCTAssertEqual(urls.count, 1)
    }

    func testSpecsBeyondTheBatchLimitGoOutInMoreRequests() async throws {
        let requests = Requests()
        let body = try reply(#"{"ratings":{}}"#)
        let ratings = SimklCommunityRatings(fetch: { (url: URL) -> JSONValue in
            await requests.add(url)
            return body
        })
        let specs = (0..<(SimklCommunityRatings.maxBatch + 5)).map { "imdb:tt\($0)" }
        _ = await ratings.ratings(specs)
        let urls = await requests.all()
        XCTAssertEqual(urls.count, 2)
    }
}

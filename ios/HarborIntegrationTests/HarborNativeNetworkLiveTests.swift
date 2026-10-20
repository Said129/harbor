import XCTest
@testable import Harbor

final class HarborNativeNetworkLiveTests: XCTestCase {
    func testPinnedPublicRepositoryUsesActualNativeTLSAndHTTP2() async throws {
        let url = "https://raw.githubusercontent.com/Said129/harbor/0834340cec5531650bfe78cd628628702e636987/package.json"
        var request = HarborNetworkRequest(url: url)
        request.publicNetworkOnly = true; request.strictLimit = true; request.maxResponseBytes = 128 * 1024
        let response = try await HarborNativeNetwork().perform(request)
        XCTAssertEqual(response.status, 200); XCTAssertTrue(response.ok)
        XCTAssertEqual(response.url, url); XCTAssertEqual(response.protocolVersion, "HTTP/2")
        let value = try JSONDecoder().decode(JSONValue.self, from: response.bytes())
        XCTAssertEqual(value["version"].string, "0.9.132")
    }
}

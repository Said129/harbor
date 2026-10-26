import XCTest
@testable import Harbor

private actor OwnedSimklFetch {
    private(set) var calls: [(Int, Date)] = []
    let failure: String?
    init(failure: String? = nil) { self.failure = failure }
    func get(_ id: Int) async throws -> JSONValue {
        calls.append((id, Date())); try await Task.sleep(for: .milliseconds(15))
        if let failure { throw HarborError(code: failure) }
        return .object(["ids": .object(["simkl": .integer(id)])])
    }
}

final class SimklArtworkTests: XCTestCase {
    func testPublicDesktopApplicationIdentityContainsNoPersonalAuthorizationAndRejectsInvalidIDs() throws {
        let request = try HTTPClient.simklArtworkRequest(7)
        let url = try XCTUnwrap(request.url), parts = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(parts.scheme, "https"); XCTAssertEqual(parts.host, "api.simkl.com"); XCTAssertEqual(parts.path, "/anime/7")
        XCTAssertNil(parts.user); XCTAssertNil(parts.password); XCTAssertNil(request.value(forHTTPHeaderField: "Authorization")); XCTAssertNil(request.value(forHTTPHeaderField: "Cookie"))
        let application = request.value(forHTTPHeaderField: "simkl-api-key")
        XCTAssertEqual(application?.count, 64); XCTAssertEqual(parts.queryItems?.first { $0.name == "client_id" }?.value, application)
        XCTAssertEqual(parts.queryItems?.first { $0.name == "app-version" }?.value, "0.9.132")
        XCTAssertEqual(request.cachePolicy, .reloadIgnoringLocalCacheData)
        XCTAssertThrowsError(try HTTPClient.simklArtworkRequest(0)); XCTAssertThrowsError(try HTTPClient.simklArtworkRequest(-1))
    }
    func testConcurrentPublicDetailsCoalesceCacheAndKeepTheOriginalGETSpacing() async throws {
        let fetch = OwnedSimklFetch(), service = SimklArtworkCatalog(fetch: { try await fetch.get($0) })
        let values = try await withThrowingTaskGroup(of: JSONValue.self) { group in
            for _ in 0..<8 { group.addTask { try await service.response(7) } }
            var values: [JSONValue] = []; for try await value in group { values.append(value) }; return values
        }
        XCTAssertEqual(values.count, 8); XCTAssertTrue(values.allSatisfy { $0["ids"]["simkl"].integer == 7 })
        _ = try await service.response(7)
        async let second = service.response(8); async let third = service.response(9)
        _ = try await (second, third)
        let calls = await fetch.calls; XCTAssertEqual(calls.count, 3); XCTAssertEqual(calls.filter { $0.0 == 7 }.count, 1)
        for index in 1..<calls.count { XCTAssertGreaterThanOrEqual(calls[index].1.timeIntervalSince(calls[index - 1].1), 0.10) }
    }
    func testAnHTTP429StopsQueuedCallsDuringTheDesktopCooldownWithoutTouchingTheNetworkAgain() async {
        let fetch = OwnedSimklFetch(failure: "http-429"), service = SimklArtworkCatalog(fetch: { try await fetch.get($0) })
        do { _ = try await service.response(7); XCTFail("The provider must report the original failure") }
        catch let error as HarborError { XCTAssertEqual(error.code, "http-429") }
        catch { XCTFail("Unexpected error: \(error)") }
        do { _ = try await service.response(8); XCTFail("The cooldown must stop the second request") }
        catch let error as HarborError { XCTAssertEqual(error.code, "simkl-cooldown") }
        catch { XCTFail("Unexpected error: \(error)") }
        let calls = await fetch.calls; XCTAssertEqual(calls.map(\.0), [7])
    }
}

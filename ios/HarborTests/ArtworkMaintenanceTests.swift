import Foundation
import XCTest
@testable import Harbor

private final class ArtworkFixtureState: @unchecked Sendable {
    private let lock = NSLock()
    private var counts: [String: Int] = [:]
    private var held = Set<String>()
    private var deliveries: [String: [@Sendable () -> Void]] = [:]
    func hold(_ key: String) { lock.withLock { _ = held.insert(key) } }
    func count(_ key: String) -> Int { lock.withLock { counts[key] ?? 0 } }
    func begin(_ key: String, deliver: @escaping @Sendable () -> Void) {
        let wait = lock.withLock {
            counts[key, default: 0] += 1
            if held.contains(key) { deliveries[key, default: []].append(deliver); return true }
            return false
        }
        if !wait { DispatchQueue.global().async(execute: deliver) }
    }
    func releaseFirst(_ key: String) {
        let action: (@Sendable () -> Void)? = lock.withLock {
            guard var queued = deliveries[key], !queued.isEmpty else { return nil }
            let first = queued.removeFirst(); deliveries[key] = queued; return first
        }
        if let action { DispatchQueue.global().async(execute: action) }
    }
    func releaseAll(_ key: String) {
        let actions = lock.withLock { held.remove(key); return deliveries.removeValue(forKey: key) ?? [] }
        for action in actions { DispatchQueue.global().async(execute: action) }
    }
}

private final class ArtworkFixtureProtocol: URLProtocol, @unchecked Sendable {
    static let state = ArtworkFixtureState()
    static let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGPwbLj0HwAFTAKb1O/v0AAAAABJRU5ErkJggg==")!
    private let lock = NSLock()
    private var canceled = false
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "artwork.fixture.invalid" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let url = request.url else { return }
        Self.state.begin(url.absoluteString) { [self] in
            guard !lock.withLock({ canceled }) else { return }
            let data = url.path.hasSuffix("invalid") ? Data("not an image".utf8) : Self.png
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "image/png", "Cache-Control": "no-store", "Content-Length": String(data.count)])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        }
    }
    override func stopLoading() { lock.withLock { canceled = true } }
}

@MainActor final class ArtworkMaintenanceTests: XCTestCase {
    private func store() -> ArtworkStore {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ArtworkFixtureProtocol.self]
        return ArtworkStore(configuration: configuration)
    }
    private func waitForRequests(_ count: Int, key: String) async -> Bool {
        for _ in 0..<200 {
            if ArtworkFixtureProtocol.state.count(key) >= count { return true }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return false
    }
    func testSharedImageDownloadsAreCachedAndClearingReallyFetchesAgain() async throws {
        let store = store(), key = "https://artwork.fixture.invalid/\(UUID().uuidString)/poster"
        async let first = store.data(key)
        async let second = store.data(key)
        let values = try await (first, second)
        XCTAssertEqual(values.0, ArtworkFixtureProtocol.png); XCTAssertEqual(values.1, values.0)
        XCTAssertEqual(ArtworkFixtureProtocol.state.count(key), 1)
        let before = await store.cachedBytes(); XCTAssertEqual(before, Int64(values.0.count))
        await store.clearCache()
        let cleared = await store.cachedBytes(); XCTAssertEqual(cleared, 0)
        let refreshed = try await store.data(key); XCTAssertEqual(refreshed, values.0)
        XCTAssertEqual(ArtworkFixtureProtocol.state.count(key), 2)
    }
    func testClearingDuringAnImageDownloadKeepsTheNewRequestAndRejectsStaleCacheWrites() async throws {
        let store = store(), key = "https://artwork.fixture.invalid/\(UUID().uuidString)/poster"
        let state = ArtworkFixtureProtocol.state; state.hold(key)
        defer { state.releaseAll(key) }
        let old = Task { try await store.data(key) }
        let oldStarted = await waitForRequests(1, key: key); XCTAssertTrue(oldStarted)
        await store.clearCache()
        let fresh = Task { try await store.data(key) }
        let freshStarted = await waitForRequests(2, key: key); XCTAssertTrue(freshStarted)
        state.releaseFirst(key)
        _ = try await old.value
        let afterOld = await store.cachedBytes(); XCTAssertEqual(afterOld, 0, "An old response cannot refill a cleared cache")
        let coalesced = Task { try await store.data(key) }
        for _ in 0..<30 { if state.count(key) > 2 { break }; try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(state.count(key), 2, "The old task must not erase the pending request from the new generation")
        state.releaseAll(key)
        let newest = try await fresh.value, joined = try await coalesced.value
        XCTAssertEqual(newest, joined)
        let final = await store.cachedBytes(); XCTAssertEqual(final, Int64(newest.count))
    }
    func testEveryCoalescedConsumerRejectsInvalidImageData() async throws {
        let store = store(), key = "https://artwork.fixture.invalid/\(UUID().uuidString)/invalid"
        let state = ArtworkFixtureProtocol.state; state.hold(key)
        defer { state.releaseAll(key) }
        let first = Task { try await store.data(key) }, second = Task { try await store.data(key) }
        let started = await waitForRequests(1, key: key); XCTAssertTrue(started)
        try await Task.sleep(for: .milliseconds(30))
        state.releaseAll(key)
        for task in [first, second] {
            do { _ = try await task.value; XCTFail("Every image consumer must validate the same shared response") }
            catch let error as HarborError { XCTAssertEqual(error.code, "invalid-artwork") }
        }
        let bytes = await store.cachedBytes(); XCTAssertEqual(bytes, 0)
    }
}

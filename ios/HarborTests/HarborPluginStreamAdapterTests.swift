import XCTest
@testable import Harbor

@MainActor final class HarborPluginStreamAdapterTests: XCTestCase {
    private func context(_ value: JSONValue) throws -> HarborPluginStreamContext {
        .init(request: value["req"], addonID: try XCTUnwrap(value["addonId"].string), addonName: try XCTUnwrap(value["addonName"].string),
            addonURL: try XCTUnwrap(value["addonUrl"].string), pluginName: try XCTUnwrap(value["pluginName"].string))
    }
    private var owned: HarborPluginStreamContext {
        .init(request: .object(["type": .string("movie"), "title": .string("Owned movie"), "year": .integer(1999)]),
            addonID: "owned.plugin", addonName: "Owned", addonURL: "harbor-plugin://owned.plugin", pluginName: "Owned")
    }
    func testActualWebKitRunsAllTwentyOriginalStreamAdapterReferenceCases() async throws {
        let adapter = HarborPluginStreamAdapter(); defer { adapter.clear() }
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "plugin-stream-adapter-reference", withExtension: "json", subdirectory: "Fixtures"))
        let fixture = try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: url))
        XCTAssertEqual(fixture["reference"].string, "0834340cec5531650bfe78cd628628702e636987")
        XCTAssertEqual(fixture["cases"].array.count, 20)
        for row in fixture["cases"].array {
            let input = row["input"]
            let actual = try await adapter.mapJSON(XCTUnwrap(input["rawJSON"].string), context: context(input["context"]), blockTrackers: input["blockTrackers"] != .bool(false))
            XCTAssertEqual(JSONValue.array(actual), row["expected"], row["name"].string ?? "Owned adapter case")
        }
    }
    func testConcurrentCallsKeepEachTrackingPolicyAndSubsequentDefaultIndependent() async throws {
        let adapter = HarborPluginStreamAdapter(); defer { adapter.clear() }
        let context = owned, raw = JSONValue.array([.object(["url": .string("https://google-analytics.com/owned")])])
        let results = try await withThrowingTaskGroup(of: (Int, Int).self) { group in
            for index in 0..<12 {
                group.addTask { let value = try await adapter.map(raw, context: context, blockTrackers: index % 2 == 0); return (index, value.count) }
            }
            var results: [(Int, Int)] = []
            for try await value in group { results.append(value) }
            return results
        }
        XCTAssertEqual(results.count, 12)
        for (index, count) in results { XCTAssertEqual(count, index % 2 == 0 ? 0 : 1) }
        let restored = try await adapter.map(raw, context: context)
        XCTAssertTrue(restored.isEmpty)
    }
    func testCancellingOneCallerDoesNotRetireAnotherCallOrTheSharedPureContext() async throws {
        let adapter = HarborPluginStreamAdapter(); defer { adapter.clear() }
        let context = owned, raw = JSONValue.array([.object(["url": .string("https://files.example.org/owned.m3u8")])])
        let normal = Task { try await adapter.map(raw, context: context) }
        let cancelled = Task { try await adapter.map(raw, context: context) }
        await Task.yield()
        cancelled.cancel()
        do { _ = try await cancelled.value; XCTFail("Cancelled conversion returned") } catch { XCTAssertTrue(error is CancellationError) }
        let result = try await normal.value, following = try await adapter.map(raw, context: context)
        XCTAssertEqual(result.count, 1); XCTAssertEqual(result, following)
    }
}

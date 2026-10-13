import Foundation
import XCTest
@testable import Harbor

final class LibraryPerformanceTests: XCTestCase {
    func testLargeLibraryReadsAvoidTheBuild85DateSortingCost() throws {
        let rows = (0..<250).reversed().map { index in
            JSONValue.object(["_id": .string("show-\(index)"), "type": .string("series"), "name": .string("Show \(index)"), "_ctime": .string("2026-10-01T00:00:00Z"), "_mtime": .string(String(format: "2026-10-%02dT%02d:00:00Z", index % 28 + 1, index % 24)), "state": .object(["timeOffset": .integer(120_000), "duration": .integer(3_600_000), "lastWatched": .string("2026-09-01T00:00:00Z")])])
        }
        // Keep the exact old expensive operation as a measured regression
        // baseline: fresh Foundation formatters inside the sort comparator.
        func oldTimestamp(_ value: JSONValue) -> Double {
            guard let value = value.string else { return 0 }
            let fractional = ISO8601DateFormatter(); fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return (fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value))?.timeIntervalSince1970 ?? 0
        }
        func oldActivity(_ row: JSONValue) -> Double { max(oldTimestamp(row["_mtime"]), oldTimestamp(row["state"]["lastWatched"])) }
        let baselineStart = ProcessInfo.processInfo.systemUptime
        let previous = rows.sorted { oldActivity($0) == oldActivity($1) ? ($0["_id"].string ?? "") < ($1["_id"].string ?? "") : oldActivity($0) > oldActivity($1) }.map { $0["_id"].string ?? "" }
        let baseline = ProcessInfo.processInfo.systemUptime - baselineStart
        let buildStart = ProcessInfo.processInfo.systemUptime
        let snapshot = LibrarySnapshot(rows)
        let build = ProcessInfo.processInfo.systemUptime - buildStart
        XCTAssertEqual(snapshot.items.map(\.id), previous, "The optimization must preserve cloud activity ordering")
        let readStart = ProcessInfo.processInfo.systemUptime
        var total = 0
        for _ in 0..<100 {
            total += snapshot.items.count
            total += snapshot.continuing.filter { $0.id != "show-1" }.count
        }
        let reads = ProcessInfo.processInfo.systemUptime - readStart
        XCTAssertEqual(total, 49_900)
        XCTAssertLessThan(build, baseline, "Prepare once instead of reparsing at every comparison")
        XCTAssertLessThan(reads, baseline / 5, "One hundred view reads must be much cheaper than one old redraw")
        let metrics = ["records": 250.0, "build85_single_read_seconds": baseline, "snapshot_prepare_seconds": build, "optimized_100_reads_seconds": reads]
        let attachment = XCTAttachment(data: try JSONSerialization.data(withJSONObject: metrics, options: [.sortedKeys]), uniformTypeIdentifier: "public.json")
        attachment.name = "library-performance-comparison"; attachment.lifetime = .keepAlways; add(attachment)
        print("HARBOR_LIBRARY_PERFORMANCE " + String(decoding: try JSONSerialization.data(withJSONObject: metrics, options: [.sortedKeys]), as: UTF8.self))
    }

    func testPreparedSnapshotPreservesRawFieldsAndUpdatesWithoutMutatingPreviousData() throws {
        let original: JSONValue = .object(["_id": .string("series"), "type": .string("series"), "name": .string("Series"), "providerField": .string("keep"), "_mtime": .string("2026-10-01T12:00:00.123Z"), "state": .object(["lastWatched": .integer(1_791_621_900_000), "timeOffset": .integer(120_000), "duration": .integer(3_600_000)])])
        let first = LibrarySnapshot([original])
        var fields = original.objectValue; fields["name"] = .string("Updated"); fields["_mtime"] = .string("2026-11-01T12:00:00+00:00")
        let next = LibrarySnapshot([.object(fields), .null])
        XCTAssertEqual(first.records, [original]); XCTAssertEqual(first.items.first?.media?.name, "Series")
        XCTAssertEqual(next.items.count, 1); XCTAssertEqual(next.items.first?.media?.name, "Updated")
        XCTAssertEqual(next.items.first?.raw["providerField"].string, "keep")
        XCTAssertGreaterThan(try XCTUnwrap(next.items.first).activityTimestamp, try XCTUnwrap(first.items.first).activityTimestamp)
        XCTAssertEqual(first.continuing.count, 1); XCTAssertEqual(next.continuing.count, 1)
        XCTAssertNotNil(ISO8601DateParser.shared.date("2026-10-01T12:00:00.123Z"))
        XCTAssertNotNil(ISO8601DateParser.shared.date("2026-10-01T12:00:00+02:00"))
    }

    func testContinuationMetadataCoalescesRequestsAndSeparatesAccountsAndSettings() async throws {
        actor Counter {
            var count = 0
            func load(_ media: Media) async throws -> Media { count += 1; try await Task.sleep(for: .milliseconds(20)); return media }
            func value() -> Int { count }
        }
        let media = try XCTUnwrap(Media.parse(.object(["id": .string("local-perf-test"), "name": .string("Title")]), kind: "movie"))
        let configuration = MetadataConfiguration(tmdbKey: "", region: "US", language: "es-ES", translateTitles: true)
        let key = try MediaMetadataStore.key(media, owner: "a", addons: [], configuration: configuration)
        XCTAssertEqual(key, try MediaMetadataStore.key(media, owner: "a", addons: [], configuration: configuration))
        let counter = Counter(), store = MediaMetadataStore()
        try await withThrowingTaskGroup(of: Media.self) { group in
            for _ in 0..<20 { group.addTask { try await store.value(for: key) { try await counter.load(media) } } }
            for try await value in group { XCTAssertEqual(value.identity, media.identity) }
        }
        _ = try await store.value(for: key) { try await counter.load(media) }
        let sharedCount = await counter.value(); XCTAssertEqual(sharedCount, 1)
        let otherAccount = try MediaMetadataStore.key(media, owner: "b", addons: [], configuration: configuration)
        var changed = configuration; changed.language = "en-US"
        let otherSettings = try MediaMetadataStore.key(media, owner: "a", addons: [], configuration: changed)
        let configured = Addon(manifest: .object(["id": .string("test-addon")]), transportUrl: "https://example.invalid/configured/manifest.json", enabled: true)
        let otherAddons = try MediaMetadataStore.key(media, owner: "a", addons: [configured], configuration: configuration)
        XCTAssertEqual(Set([key, otherAccount, otherSettings, otherAddons]).count, 4)
        _ = try await store.value(for: otherAccount) { try await counter.load(media) }
        let isolatedCount = await counter.value(); XCTAssertEqual(isolatedCount, 2)
        do { _ = try await store.value(for: "failed") { throw HarborError(code: "test-error") }; XCTFail("Expected failure") } catch { }
        _ = try await store.value(for: "failed") { try await counter.load(media) }
        let retryCount = await counter.value(); XCTAssertEqual(retryCount, 3, "A failed fetch must not poison the cache")
    }

    @MainActor
    func testColdDetailJoinsTheMetadataRequestAlreadyLoadingForItsCard() async throws {
        actor Counter {
            var count = 0
            func load(_ media: Media) async throws -> Media { count += 1; try await Task.sleep(for: .milliseconds(20)); return media }
            func value() -> Int { count }
        }
        let original = try XCTUnwrap(Media.parse(.object(["id": .string("local-cold-detail"), "name": .string("Library")]), kind: "movie"))
        let resolved = try XCTUnwrap(Media.parse(.object(["id": .string("local-cold-detail"), "name": .string("Ready")]), kind: "movie"))
        let store = MediaMetadataStore(), counter = Counter()
        async let card = store.value(for: "cold-detail") { try await counter.load(resolved) }
        let model = DetailModel(original, service: HarborService())
        await model.load([], owner: "guest", library: LibraryModel()) {
            try await store.value(for: "cold-detail") { try await counter.load(resolved) }
        }
        _ = try await card
        let requests = await counter.value()
        XCTAssertEqual(requests, 1, "A tap during hydration must join the card request")
        XCTAssertEqual(model.media.name, "Ready"); XCTAssertNil(model.error)
        XCTAssertFalse(model.loadingMetadata)
    }

    @MainActor
    func testHydratedContinuationOpensWithoutRepeatingMetadataLoading() async throws {
        let media = try XCTUnwrap(Media.parse(.object(["id": .string("local-perf-no-provider"), "name": .string("Ready"), "type": .string("series"), "videos": .array([.object(["id": .string("local-perf-no-provider:1:1"), "season": .integer(1), "episode": .integer(1)])])]), kind: "series"))
        let model = DetailModel(media, service: HarborService(), metadataLoaded: true)
        await model.load([], owner: "guest", library: LibraryModel())
        XCTAssertFalse(model.loadingMetadata); XCTAssertNil(model.error)
        XCTAssertEqual(model.media.videos?.first?.id, "local-perf-no-provider:1:1")
    }
}

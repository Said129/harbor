import XCTest
import UIKit
@testable import Harbor

@MainActor final class StreamingPreferencesTests: XCTestCase {
    private final class Memory: StreamingPreferencePersistence {
        var documents: [String: [String: Bool]] = [:]
        var rejectRead = false
        var rejectWrite = false
        func load(_ key: String) throws -> [String: Bool]? {
            if rejectRead { throw HarborError(code: "test-read") }; return documents[key]
        }
        func save(_ value: [String: Bool], key: String) throws {
            if rejectWrite { throw HarborError(code: "test-write") }; documents[key] = value
        }
    }
    func testAllOriginalServicesAndAlternateProviderIDsHaveTheDesktopDefaults() throws {
        let all = StreamingServiceDefinition.all
        XCTAssertEqual(all.count, 27); XCTAssertEqual(all.filter(\.enabledByDefault).count, 12)
        XCTAssertEqual(all.first { $0.key == "prime" }?.providers, "9|119")
        XCTAssertEqual(all.first { $0.key == "paramount" }?.providers, "531|582|1715|1854")
        XCTAssertEqual(all.first { $0.key == "hidive" }?.providerIds, [430])
        for service in all { XCTAssertNotNil(UIImage(named: service.asset), "Original logo missing: " + service.key) }
    }
    func testOwnerIsolationPersistenceAndFailedWritesKeepThePublishedSelection() {
        let memory = Memory()
        let alice = StreamingPreferences(owner: "alice", persistence: memory), bob = StreamingPreferences(owner: "bob", persistence: memory)
        XCTAssertTrue(alice.setEnabled(false, for: "netflix")); XCTAssertTrue(bob.isEnabled("netflix"))
        XCTAssertFalse(StreamingPreferences(owner: "alice", persistence: memory).isEnabled("netflix"))
        memory.rejectWrite = true
        XCTAssertFalse(alice.setEnabled(true, for: "netflix")); XCTAssertFalse(alice.isEnabled("netflix")); XCTAssertNotNil(alice.error)
        XCTAssertTrue(bob.isEnabled("netflix"))
    }
    func testUnreadablePreferencesCannotBeOverwrittenByFallbackDefaults() {
        let memory = Memory(); memory.rejectRead = true
        let preferences = StreamingPreferences(owner: "one", persistence: memory)
        XCTAssertFalse(preferences.ready); XCTAssertFalse(preferences.setEnabled(false, for: "netflix")); XCTAssertTrue(memory.documents.isEmpty)
        memory.rejectRead = false; preferences.reload()
        XCTAssertTrue(preferences.ready); XCTAssertTrue(preferences.setEnabled(false, for: "netflix"))
    }
    func testServiceRowsUseRegionAliasesAndAlternateMoviesAndSeriesWithoutDuplicates() throws {
        let service = try XCTUnwrap(StreamingServiceDefinition.all.first { $0.key == "prime" })
        let definition = StreamingCatalog.definition(service, kind: "series", region: "ES")
        XCTAssertEqual(definition.path, "discover/tv"); XCTAssertEqual(definition.parameters["watch_region"], "ES")
        XCTAssertEqual(definition.parameters["with_watch_providers"], "9|119"); XCTAssertEqual(definition.parameters["with_watch_monetization_types"], "flatrate")
        let movies = (0..<15).map { Media(id: "m\($0)", type: "movie", name: "Movie") }, series = (0..<15).map { Media(id: "s\($0)", type: "series", name: "Series") }
        let mixed = StreamingCatalog.interleave(movies, series)
        XCTAssertEqual(mixed.count, 24); XCTAssertEqual(Array(mixed.prefix(4).map(\.id)), ["m0", "s0", "m1", "s1"])
        XCTAssertEqual(StreamingCatalog.interleave(movies, series, perTypeLimit: nil).count, 30, "The full browser must not drop titles after the twelve-item home preview")
        XCTAssertEqual(StreamingCatalog.interleave([movies[0]], [movies[0]]).count, 1)
        XCTAssertTrue(StreamingCatalog.interleave([], []).isEmpty)
    }
}

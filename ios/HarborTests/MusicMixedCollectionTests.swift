import XCTest
@testable import Harbor

@MainActor final class MusicMixedCollectionTests: XCTestCase {
    func testSixtyExecutedOriginalCollectionFiltersSourcesAndRecordingIdentitiesMatchInAppleJavaScriptCore() async throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "music-collection-tools-reference", withExtension: "json", subdirectory: "Fixtures"))
        let fixture = try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: url)), tools = MusicCollectionTools()
        XCTAssertEqual(fixture["reference"].string, "0834340cec5531650bfe78cd628628702e636987")
        XCTAssertEqual(fixture["whole_original_modules_executed"].integer, 4)
        XCTAssertEqual(fixture["cases"].array.count, 60)
        for item in fixture["cases"].array {
            let input = item["input"], name = try XCTUnwrap(item["name"].string)
            switch input["operation"].string {
            case "filter":
                let tracks: [MusicTrack] = try decode(input["tracks"]), filters: MusicCollectionFilters = try decode(input["filters"])
                let dates = input["metadata"]["addedAt"].objectValue.mapValues { $0.string ?? "" }
                var genres: [Int: Set<String>] = [:]
                for (id, values) in input["genreTracks"].objectValue { if let id = Int(id) { genres[id] = Set(values.array.compactMap(\.string)) } }
                let actual = try await tools.filter(.init(tracks: tracks, filters: filters, addedAt: dates, recentFirst: input["metadata"]["recentFirst"] == .bool(true), genreTracks: genres))
                let expected: [MusicTrack] = try decode(item["expected"]); XCTAssertEqual(actual, expected, name)
            case "sources":
                let actual = try await tools.sources(decode(input["tracks"])), expected: [String] = try decode(item["expected"]); XCTAssertEqual(actual, expected, name)
            case "label":
                let actual = try await tools.label(try XCTUnwrap(input["source"].string)); XCTAssertEqual(actual, item["expected"].string, name)
            case "identity":
                let actual = try await tools.identity(decode(input["track"])); XCTAssertEqual(actual, item["expected"].string, name)
            case "addable":
                let actual = try await tools.addable(decode(input["candidates"]), to: decode(input["tracks"]))
                let expected: [MusicTrack] = try decode(item["expected"]); XCTAssertEqual(actual, expected, name)
            default: XCTFail("Unexecuted fixture operation: " + name)
            }
        }
    }
    func testSavedAndRecentCollectionsResolveRemoteMetadataAndGenuineLocalFallbackInOwnedOrder() async throws {
        let owner = "owned-mixed-projection-" + UUID().uuidString
        let file = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "owned-tone", withExtension: "wav", subdirectory: "Fixtures"))
        let imported = try await MusicFileService.shared.importFile(file, owner: owner).record
        do {
            let store = MusicPlaylistStore(owner: owner, persistence: SharedMusicDisk())
            let collections = MusicCollections(persistence: MixedCollectionMemory()), first = SharedMusicPlaybackTests.track("remote:one", source: "one"), second = SharedMusicPlaybackTests.track("remote:two", source: "two")
            XCTAssertTrue(store.remember([first, second]))
            XCTAssertTrue(collections.recordPlayed(imported.id, owner: owner)); XCTAssertTrue(collections.recordPlayed(second.id, owner: owner)); XCTAssertTrue(collections.recordPlayed(first.id, owner: owner))
            let recent = collections.tracks(.recent, store: store, library: [imported], owner: owner)
            XCTAssertEqual(recent.map(\.id), [first.id, second.id, imported.id]); XCTAssertEqual(recent.last, imported.local.track)
            XCTAssertTrue(collections.setLiked(second.id, liked: true, owner: owner)); XCTAssertTrue(collections.setLiked(first.id, liked: true, owner: owner))
            XCTAssertEqual(collections.tracks(.liked, store: store, library: [], owner: owner).map(\.id), [first.id, second.id])
            let another = MusicPlaylistStore(owner: owner + "-other", persistence: SharedMusicDisk())
            XCTAssertTrue(collections.tracks(.recent, store: another, library: [imported], owner: owner).isEmpty)
            let list = try XCTUnwrap(store.create("Owned mixed collection")); XCTAssertNotNil(store.add([first, imported.local.track], to: list.id))
            XCTAssertEqual(store.recordings(in: list.id, local: [imported]).map(\.id), [first.id, imported.id])
            XCTAssertEqual(recent.first?.title, first.title, "Remote metadata remains a recording, without a fabricated local file")
            try await MusicFileService.shared.remove(imported, owner: owner)
        } catch { try? await MusicFileService.shared.remove(imported, owner: owner); throw error }
    }
    func testCancelledFiltersRetainTheLastListeningViewAndResetKeepsTheChosenSort() async throws {
        let model = MusicCollectionModel(), tracks = [SharedMusicPlaybackTests.track("one", source: "one"), SharedMusicPlaybackTests.track("two", source: "two")]
        await model.load(.init(tracks: tracks)); XCTAssertEqual(model.tracks, tracks); XCTAssertFalse(model.failed)
        var filters = MusicCollectionFilters(query: "two", source: "direct", content: .clean, sort: .title, descending: true)
        XCTAssertFalse(filters.canReorder); filters.reset(); XCTAssertFalse(filters.active); XCTAssertEqual(filters.sort, .title); XCTAssertTrue(filters.descending)
        let cancelled = Task { await model.load(.init(tracks: [], filters: filters)) }; cancelled.cancel(); await cancelled.value
        XCTAssertEqual(model.tracks, tracks); XCTAssertFalse(model.loading); XCTAssertFalse(model.failed)
        let limited = MusicCollectionFilters.limitedQuery(String(repeating: "😀", count: 101))
        XCTAssertEqual(limited.utf16.count, 200); XCTAssertEqual(limited.count, 100)
        var invalid = MusicCollectionFilters(); invalid.query = String(repeating: "x", count: 201)
        do { _ = try await MusicCollectionTools().filter(.init(tracks: tracks, filters: invalid)); XCTFail("The source input limit must reject an overlong query") } catch { }
    }
    func testNewMixedCollectionInterfaceLabelsMatchAllSixteenPinnedCatalogs() throws {
        let file = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "music-mixed-collection-labels", withExtension: "json", subdirectory: "Fixtures"))
        let fixture = try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: file))
        var count = 0
        for language in fixture["languages"].array {
            let code = try XCTUnwrap(language["code"].string)
            for (key, value) in language["expected"].objectValue {
                XCTAssertEqual(DesktopInterfaceText.value(key, language: code), try XCTUnwrap(value.string), code + ": " + key); count += 1
            }
        }
        XCTAssertEqual(count, fixture["comparisons"].integer)
    }
    private func decode<T: Decodable>(_ value: JSONValue) throws -> T { try JSONDecoder().decode(T.self, from: JSONEncoder().encode(value)) }
}
@MainActor private final class MixedCollectionMemory: MusicCollectionsPersistence {
    var documents: [String: MusicCollectionsDocument] = [:]
    func read(owner: String) throws -> MusicCollectionsDocument? { documents[owner] }
    func write(_ value: MusicCollectionsDocument, owner: String) throws { documents[owner] = value }
}

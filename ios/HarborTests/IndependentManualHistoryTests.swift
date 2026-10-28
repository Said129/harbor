import XCTest
@testable import Harbor

@MainActor final class IndependentManualHistoryTests: XCTestCase {
    private func makeLibrary(root: URL, owner: String, service: OwnedRetirementOfflineService) async -> LibraryModel {
        let library = LibraryModel(service: service, writeQueue: .init(service: service, directory: root), cache: .init(directory: root))
        await library.setSession(nil, personalOwner: owner, guestOwner: owner, synchronize: false)
        return library
    }
    private func history(_ library: LibraryModel) throws -> LibraryHistoryModel {
        let account = TraktAccountStore(owner: library.personalOwner, persistence: OwnedTraktPersistence()); try account.load()
        XCTAssertNil(account.session)
        return .init(library: library, account: account, store: .init(owner: library.personalOwner, disk: OwnedTraktLibraryDisk()),
            client: .init(transport: { _ in throw HarborError(code: "unexpected-independent-history-request") }), active: { true })
    }
    func testLocalEpisodeMarkEntersHistoryAndUnmarkWithdrawsItWithoutPlaybackOrAccounts() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("owned-manual-history-" + UUID().uuidString), owner = root.lastPathComponent
        defer { try? FileManager.default.removeItem(at: root) }
        let service = OwnedRetirementOfflineService(), library = await makeLibrary(root: root, owner: owner, service: service)
        let model = try history(library), episode = Episode(id: "owned:show:1:2", season: 1, episode: 2)
        var media = Media(id: "owned:show", type: "series", name: "Owned Show"); media.videos = [episode]
        await model.refresh(); XCTAssertTrue(model.entries.isEmpty)
        await library.toggleEpisode(media, episode: episode)
        let entry = try XCTUnwrap(model.entries.first); XCTAssertEqual(entry.id, media.id); XCTAssertTrue(entry.watched)
        XCTAssertFalse(entry.record.bookmarked); XCTAssertEqual(entry.progress, 0); XCTAssertNil(entry.episodeHint)
        XCTAssertEqual(entry.record.raw["state"]["timeOffset"].numericValue, 0)
        let restarted = await makeLibrary(root: root, owner: owner, service: service), restored = try history(restarted)
        XCTAssertEqual(restored.entries.map(\.id), [media.id])
        await restarted.toggleEpisode(media, episode: episode); XCTAssertTrue(restored.entries.isEmpty)
        let requests = await service.requests; XCTAssertEqual(requests, 0)
    }
    func testManualMovieAndWholeSeriesHistoryCanBeRemovedAndReopenedWithinTheirOwner() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("owned-manual-history-" + UUID().uuidString), owner = root.lastPathComponent
        defer { try? FileManager.default.removeItem(at: root) }
        let service = OwnedRetirementOfflineService(), library = await makeLibrary(root: root, owner: owner, service: service)
        let movie = Media(id: "owned:film", type: "movie", name: "Owned Film")
        var series = Media(id: "owned:show", type: "series", name: "Owned Show")
        series.videos = [.init(id: "owned:show:1:1", season: 1, episode: 1)]
        await library.toggleWatched(movie); await library.toggleWatched(series)
        let model = try history(library); XCTAssertEqual(Set(model.entries.map(\.id)), [movie.id, series.id]); XCTAssertTrue(model.entries.allSatisfy(\.watched))
        let entry = try XCTUnwrap(model.entries.first { $0.id == series.id }), state = entry.record.raw["state"]
        let removed = await library.removeHistory(entry.record, owner: owner, personalOwner: owner); XCTAssertTrue(removed)
        let saved = try await LibraryCache(directory: root).readSnapshot(owner: owner)
        XCTAssertEqual(saved.items.first { $0.id == series.id }?.raw["state"], state)
        let restarted = await makeLibrary(root: root, owner: owner, service: service); XCTAssertEqual(try history(restarted).entries.map(\.id), [movie.id])
        await restarted.setSession(nil, personalOwner: "foreign", guestOwner: "foreign", synchronize: false)
        XCTAssertTrue(try history(restarted).entries.isEmpty)
        let requests = await service.requests; XCTAssertEqual(requests, 0)
    }
    func testNativeHistoryExtensionKeepsAllOriginalFilterScenariosAndIgnoresFalseOrMalformedManualFlags() throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "library-history-reference", withExtension: "json", subdirectory: "Fixtures"))
        let reference = try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: url))
        XCTAssertEqual(reference["reference"].string, "0834340cec5531650bfe78cd628628702e636987")
        XCTAssertEqual(reference["cases"].array.count, 8)
        for row in reference["cases"].array {
            let records = row["local"].array.map { LibraryRecord(raw: $0) }.filter(LibraryHistoryEntry.eligible)
            XCTAssertEqual(Set(records.map(\.id)), Set(row["filteredIDs"].array.compactMap(\.string)))
        }
        for decision in [JSONValue.bool(false), .string("true"), .integer(1), .null] {
            var fields = LibraryRecord.new(.init(id: "owned:unwatched", type: "series", name: "Owned"))
            var state = (fields["state"] ?? .null).objectValue
            state["nativeManualMovie"] = decision; state["nativeManualEpisodes"] = .object(["1:1": decision]); fields["state"] = .object(state)
            XCTAssertFalse(LibraryHistoryEntry.eligible(.init(raw: .object(fields))))
        }
    }
}

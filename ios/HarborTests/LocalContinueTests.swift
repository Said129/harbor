import XCTest
@testable import Harbor

private actor OwnedLocalContinueGate {
    private(set) var calls = 0
    private var held: CheckedContinuation<Bool, Never>?
    var waiting: Bool { held != nil }
    func current() async -> Bool {
        calls += 1
        if calls == 2 { return await withCheckedContinuation { held = $0 } }
        return true
    }
    func release() { held?.resume(returning: true); held = nil }
}
@MainActor private final class OwnedLocalContinueScope { var active = true }

@MainActor final class LocalContinueTests: XCTestCase {
    private func directory() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("owned-local-cw-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true); return root
    }
    private func entry(_ id: String, source: LocalContinueSource = .library, position: Double = 400_000, t: UInt64 = 1_700_000_000_123) -> LocalContinueEntry {
        .init(id: id, type: "movie", name: "Owned " + id, source: source, positionMs: position, durationMs: 1_000_000, t: t)
    }
    private func decode<T: Decodable>(_ value: JSONValue, as: T.Type = T.self) throws -> T { try JSONDecoder().decode(T.self, from: JSONEncoder().encode(value)) }
    private func object(_ value: JSONValue) throws -> NSDictionary { try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? NSDictionary) }
    private func raw(_ value: LibraryRecord) -> JSONValue {
        var fields = value.raw.objectValue; fields.removeValue(forKey: "nativeSource"); return .object(fields)
    }
    private func snapshot(_ position: Double = 400_000, t: UInt64 = 1_700_000_000_123) -> ResumeSnapshot {
        .init(positionMs: position, durationMs: 1_000_000, timestampMs: t, exiting: true)
    }
    func testThirteenExecutedDesktopHistoriesPreserveOwnersLimitsOrderingThresholdsAndRecordFields() async throws {
        let file = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "local-continue-reference", withExtension: "json", subdirectory: "Fixtures"))
        let fixture = try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: file))
        XCTAssertEqual(fixture["actual_original_typescript_executed"], .bool(true)); XCTAssertEqual(fixture["provider_network_requests"].integer, 0)
        XCTAssertEqual(fixture["cases"].array.count, 13)
        for row in fixture["cases"].array {
            let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
            let store = LocalContinueStore(root: root)
            for operation in row["operations"].array {
                let owner = operation["owner"].string
                let shared = owner == "separate" ? "separate" : "primary"
                if operation["kind"].string == "clear" {
                    _ = try await store.clear(try XCTUnwrap(operation["id"].string), personalOwner: try XCTUnwrap(owner), sharedOwner: shared, current: { true })
                } else {
                    let value: LocalContinueEntry = try decode(operation["entry"])
                    if let owner { _ = try await store.recordPlayback(value, personalOwner: owner, sharedOwner: shared, includeShared: operation["shared"] != .bool(false), current: { true }) }
                    else { try await store.absorbShared([value], sharedOwner: shared, current: { true }) }
                }
            }
            // Reopen the actual files with a fresh actor: cached objects alone
            // cannot prove that a restart preserves either ownership scope.
            let restarted = LocalContinueStore(root: root)
            for owner in ["primary", "sibling", "separate"] {
                let expected = row["expected"][owner]
                let actual = try await restarted.snapshot(personalOwner: owner, sharedOwner: owner == "separate" ? owner : "primary")
                let personal: [LocalContinueEntry] = try decode(expected["personal"]), shared: [LocalContinueEntry] = try decode(expected["shared"])
                XCTAssertEqual(actual.personal.sorted, personal, row["name"].string ?? "")
                XCTAssertEqual(actual.shared.sorted, shared, row["name"].string ?? "")
                for (record, expected) in zip(actual.personalRecords, expected["personalRecords"].array) { XCTAssertEqual(try object(raw(record)), try object(expected)) }
                for (record, expected) in zip(actual.sharedRecords, expected["sharedRecords"].array) { XCTAssertEqual(try object(raw(record)), try object(expected)) }
            }
        }
    }
    func testCorruptionAndWriteFailuresKeepDiskAndLastCommittedMemory() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let store = LocalContinueStore(root: root), value = entry("film")
        _ = try await store.recordPlayback(value, personalOwner: "person", sharedOwner: "account", current: { true })
        let file = root.appendingPathComponent(EBookShelf.hash("private:person") + ".json"), backup = file.appendingPathExtension("previous")
        let original = try Data(contentsOf: file)
        try FileManager.default.moveItem(at: file, to: backup); try FileManager.default.createDirectory(at: file, withIntermediateDirectories: false)
        do { _ = try await store.recordPlayback(entry("film", position: 600_000), personalOwner: "person", sharedOwner: "account", current: { true }); XCTFail("Write over a directory must fail") } catch { }
        let saved = try await store.snapshot(personalOwner: "person", sharedOwner: "account")
        XCTAssertEqual(saved.personal.sorted, [value]); XCTAssertEqual(saved.shared.sorted, [value]); XCTAssertEqual(try Data(contentsOf: backup), original)
        try FileManager.default.removeItem(at: file); try FileManager.default.moveItem(at: backup, to: file)
        for bad in [Data("broken-json".utf8), Data(#"{"version":2,"entries":{},"order":[]}"#.utf8)] {
            try bad.write(to: file)
            let reopened = LocalContinueStore(root: root)
            do { _ = try await reopened.snapshot(personalOwner: "person", sharedOwner: "account"); XCTFail("Corrupt history must remain unavailable") } catch { }
            do { _ = try await reopened.recordPlayback(value, personalOwner: "person", sharedOwner: "account", current: { true }); XCTFail("A save must not erase corrupt history") } catch { }
            XCTAssertEqual(try Data(contentsOf: file), bad)
        }
    }
    func testFifteenExecutedCloudAnimeImportsKeepCoordinatesRecencyAndSharedOnlyOwnership() async throws {
        let file = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "local-continue-reference", withExtension: "json", subdirectory: "Fixtures"))
        let fixture = try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: file))
        XCTAssertEqual(fixture["absorptionCases"].array.count, 15)
        let now = try XCTUnwrap(fixture["absorptionNow"].numericValue)
        for row in fixture["absorptionCases"].array {
            let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
            let store = LocalContinueStore(root: root)
            let previous: LocalContinueEntry? = row["existing"] == .null ? nil : try decode(row["existing"])
            if let previous { _ = try await store.recordPlayback(previous, personalOwner: "person", sharedOwner: "account", current: { true }) }
            let records = row["dismissed"] == .bool(true) ? [] : [LibraryRecord(raw: row["raw"])]
            try await store.absorbCloudAnime(records, sharedOwner: "account", now: now, current: { true })
            let actual = try await LocalContinueStore(root: root).snapshot(personalOwner: "person", sharedOwner: "account")
            let writes: [LocalContinueEntry] = try decode(row["expectedWrites"])
            XCTAssertEqual(actual.personal.sorted, previous.map { [$0] } ?? [], row["name"].string ?? "")
            XCTAssertEqual(actual.shared.sorted, writes.isEmpty ? previous.map { [$0] } ?? [] : writes, row["name"].string ?? "")
        }
    }
    func testSuspendedOwnershipLeaseSerializesWritesAndRejectsCancelledOperations() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let store = LocalContinueStore(root: root), gate = OwnedLocalContinueGate()
        let older = entry("same", position: 200_000, t: 10), newer = entry("same", position: 600_000, t: 20)
        let first = Task { try await store.recordPlayback(older, personalOwner: "person", sharedOwner: "account", current: { await gate.current() }) }
        for _ in 0..<100 { if await gate.waiting { break }; try await Task.sleep(for: .milliseconds(10)) }
        let waiting = await gate.waiting; XCTAssertTrue(waiting)
        let second = Task { try await store.recordPlayback(newer, personalOwner: "person", sharedOwner: "account", current: { await gate.current() }) }
        try await Task.sleep(for: .milliseconds(50))
        let callsWhileHeld = await gate.calls; XCTAssertEqual(callsWhileHeld, 2, "Later writes cannot leapfrog a suspended shared write")
        await gate.release(); _ = try await first.value; _ = try await second.value
        let final = try await LocalContinueStore(root: root).snapshot(personalOwner: "person", sharedOwner: "account")
        XCTAssertEqual(final.personal.sorted, [newer]); XCTAssertEqual(final.shared.sorted, [newer])
        do { _ = try await store.recordPlayback(entry("cancelled"), personalOwner: "person", sharedOwner: "account", current: { false }); XCTFail("Expired owner must cancel") } catch { XCTAssertTrue(error is CancellationError) }
        do { try await store.absorbShared([entry("cancelled-cloud")], sharedOwner: "account", current: { false }); XCTFail("Expired import must cancel") } catch { XCTAssertTrue(error is CancellationError) }
        do { _ = try await store.clear("same", personalOwner: "person", sharedOwner: "account", current: { false }); XCTFail("Expired dismissal must cancel") } catch { XCTAssertTrue(error is CancellationError) }
        let unchanged = try await store.snapshot(personalOwner: "person", sharedOwner: "account")
        XCTAssertEqual(unchanged.personal.sorted, final.personal.sorted); XCTAssertEqual(unchanged.shared.sorted, final.shared.sorted)
    }
    func testProductionPlaybackCommitRestoresStreamingAndDownloadsWithoutACloudWrite() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let owner = "owned-local-cw-" + UUID().uuidString, person = owner + "-person", shared = owner + "-source"
        defer { try? KeychainStore().remove(LibraryPresentation.key(owner: owner)) }
        let local = LocalContinueStore(root: root), library = LibraryModel(localContinue: local)
        let session = AccountSession(authKey: "owned-offline-no-request", user: .init(id: owner, email: nil, fullname: nil))
        await library.setSession(session, personalOwner: person, synchronize: false)
        await library.bindLocalContinuing(sharedOwner: shared, scope: owner, active: { true })
        let resume = ResumeStore(fileURL: root.appendingPathComponent("resume.json")); try await resume.load()
        for via in ["addon", "download"] {
            let media = Media(id: "owned-" + via, type: "movie", name: "Owned " + via), target = ResumeTarget(id: "owned-" + via)
            let playback = PlaybackSession(source: .init(url: "https://owned.invalid/video", headers: nil, subtitles: nil, via: via), target: target, startMs: 0, storageWarning: nil, progressEnabled: true, owner: owner, personalOwner: person, resumeStore: resume)
            let committed = try await PlaybackProgressCommit.save(snapshot(), session: playback, resume: resume, media: media, library: library)
            XCTAssertTrue(committed)
        }
        XCTAssertTrue(library.items.isEmpty, "Local playback must not create a bookmark or require a Stremio write")
        XCTAssertEqual(Set(library.continuing.map(\.id)), ["owned-addon", "owned-download"])
        let saved = try await local.snapshot(personalOwner: person, sharedOwner: shared)
        XCTAssertEqual(saved.personal.sorted.count, 2); XCTAssertEqual(saved.shared.sorted.count, 2)
        XCTAssertEqual(saved.personal.entries["owned-download"]?.source, .local); XCTAssertEqual(saved.personal.entries["owned-addon"]?.source, .library)
        let reopened = LibraryModel(localContinue: LocalContinueStore(root: root))
        await reopened.setSession(session, personalOwner: person, synchronize: false)
        await reopened.bindLocalContinuing(sharedOwner: shared, scope: owner, active: { true })
        XCTAssertEqual(Set(reopened.continuing.map(\.id)), ["owned-addon", "owned-download"])
        let restored = await reopened.resume(for: .init(id: "owned-download"), refresh: false); XCTAssertEqual(restored?.entry.ms, 400_000)
        let resumeAgain = ResumeStore(fileURL: root.appendingPathComponent("resume.json")); try await resumeAgain.load()
        let checkpoint = try await resumeAgain.entry(.init(id: "owned-addon")); XCTAssertEqual(checkpoint?.ms, 400_000)
    }
    func testSourceMasksAndExpiredProfileLeaseRemoveCachedCardsAndRejectLatePersonalWrites() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let owner = "owned-local-source-" + UUID().uuidString, other = owner + "-other"
        defer { try? KeychainStore().remove(LibraryPresentation.key(owner: owner)); try? KeychainStore().remove(LibraryPresentation.key(owner: other)) }
        let store = LocalContinueStore(root: root), scope = OwnedLocalContinueScope()
        _ = try await store.recordPlayback(entry("stream"), personalOwner: owner, sharedOwner: owner, current: { true })
        _ = try await store.recordPlayback(entry("download", source: .local), personalOwner: owner, sharedOwner: owner, current: { true })
        let library = LibraryModel(localContinue: store)
        await library.setSession(nil, personalOwner: owner, guestOwner: owner, synchronize: false)
        await library.bindLocalContinuing(sharedOwner: owner, scope: owner, active: { scope.active })
        XCTAssertEqual(library.continuing.count, 2)
        var sources = ContinueWatchingSources(); sources.library = false; library.setContinueSources(sources)
        XCTAssertEqual(library.continuing.map(\.id), ["download"])
        sources.local = false; library.setContinueSources(sources); XCTAssertTrue(library.continuing.isEmpty)
        sources.library = true; library.setContinueSources(sources); XCTAssertEqual(library.continuing.map(\.id), ["stream"])
        scope.active = false; XCTAssertTrue(library.continuing.isEmpty, "Cached cards cannot survive an invalid profile lease")
        scope.active = true; XCTAssertEqual(library.continuing.count, 1)
        await library.setSession(nil, personalOwner: other, guestOwner: owner, synchronize: false)
        await library.bindLocalContinuing(sharedOwner: other, scope: other, active: { true })
        let media = Media(id: "late", type: "movie", name: "Owned late")
        await library.saveLocalProgress(media, target: .init(id: media.id), snapshot: snapshot(), source: .library, owner: owner, personalOwner: owner)
        let untouched = try await store.snapshot(personalOwner: other, sharedOwner: other)
        XCTAssertTrue(untouched.personal.entries.isEmpty); XCTAssertTrue(untouched.shared.entries.isEmpty); XCTAssertTrue(library.continuing.isEmpty)
    }
    func testProductionCachedAnimeAbsorptionUsesSharedHistoryAndTheDesktopDownloadSourceMask() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let owner = "owned-cloud-anime-" + UUID().uuidString, person = owner + "-person"
        defer { try? KeychainStore().remove(LibraryPresentation.key(owner: owner)) }
        let now = Date().ISO8601Format(.init(includingFractionalSeconds: true))
        let raw: JSONValue = .object(["_id": .string("kitsu:owned-8"), "type": .string("series"), "name": .string("Owned anime"), "_mtime": .string(now),
            "state": .object(["video_id": .string("kitsu:owned-8:99"), "timeOffset": .integer(400_000), "duration": .integer(1_000_000)])])
        try await LibraryCache().save([raw], owner: owner)
        let local = LocalContinueStore(root: root), library = LibraryModel(localContinue: local)
        await library.setSession(nil, personalOwner: person, guestOwner: owner, synchronize: false)
        await library.bindLocalContinuing(sharedOwner: owner, scope: owner, active: { true })
        let saved = try await local.snapshot(personalOwner: person, sharedOwner: owner)
        XCTAssertTrue(saved.personal.entries.isEmpty); XCTAssertEqual(saved.shared.sorted.map(\.id), ["kitsu:owned-8"])
        XCTAssertEqual(library.continuing.first?.playbackCoordinates.episode, 99)
        var sources = ContinueWatchingSources(); sources.local = false; library.setContinueSources(sources)
        XCTAssertTrue(library.continuing.isEmpty, "Desktop's absorbed anime is a local source, never a duplicate unfiltered cloud card")
        sources.local = true; library.setContinueSources(sources)
        let card = try XCTUnwrap(library.continuing.first); library.hideContinuing(card, owner: owner)
        XCTAssertTrue(library.continuing.isEmpty); library.showContinuing(card); XCTAssertEqual(library.continuing.count, 1)
    }
    func testRejectedOrFailedResumeCheckpointCannotCreateLocalViewingHistory() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let owner = "owned-rejected-local-" + UUID().uuidString
        defer { try? KeychainStore().remove(LibraryPresentation.key(owner: owner)) }
        let store = LocalContinueStore(root: root), library = LibraryModel(localContinue: store)
        await library.setSession(nil, personalOwner: owner, guestOwner: owner, synchronize: false)
        await library.bindLocalContinuing(sharedOwner: owner, scope: owner, active: { true })
        let resume = ResumeStore(fileURL: root.appendingPathComponent("resume.json")), media = Media(id: "film", type: "movie", name: "Owned film")
        var playback = PlaybackSession(source: .init(url: "https://owned.invalid/video", headers: nil, subtitles: nil, via: "addon"), target: .init(id: media.id), startMs: 0, storageWarning: nil, progressEnabled: true, owner: owner, personalOwner: owner, resumeStore: resume)
        do { _ = try await PlaybackProgressCommit.save(snapshot(), session: playback, resume: resume, media: media, library: library); XCTFail("Unavailable resume must fail") } catch { }
        try await resume.load()
        let zero = try await PlaybackProgressCommit.save(snapshot(0), session: playback, resume: resume, media: media, library: library); XCTAssertFalse(zero)
        playback = .init(source: playback.source, target: playback.target, startMs: 0, storageWarning: nil, progressEnabled: false, owner: owner, personalOwner: owner)
        let disabled = try await PlaybackProgressCommit.save(snapshot(), session: playback, resume: resume, media: media, library: library); XCTAssertFalse(disabled)
        let saved = try await store.snapshot(personalOwner: owner, sharedOwner: owner)
        XCTAssertTrue(saved.personal.entries.isEmpty); XCTAssertTrue(saved.shared.entries.isEmpty); XCTAssertTrue(library.continuing.isEmpty)
    }
}

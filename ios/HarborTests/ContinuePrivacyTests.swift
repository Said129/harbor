import XCTest
@testable import Harbor

@MainActor private final class OwnedContinueDismissals: ContinueDismissalPersistence {
    var state: ContinueDismissalState?
    var old: [String: [String: ContinueDismissal]] = [:]
    var failRead = false, failWrite = false
    func read() throws -> ContinueDismissalState? { if failRead { throw HarborError(code: "owned-read") }; return state }
    func write(_ value: ContinueDismissalState) throws { if failWrite { throw HarborError(code: "owned-write") }; state = value }
    func legacy(_ owner: String) throws -> [String: ContinueDismissal] { old[owner] ?? [:] }
}
@MainActor private final class OwnedContinueSettings: ProfileSettingsPersistence {
    var state = ProfileSettingsState()
    func readProfileSettings() throws -> ProfileSettingsState? { state }
    func writeProfileSettings(_ value: ProfileSettingsState) throws { state = value }
}
private actor OwnedPrivateLibrary: LibraryServing {
    private(set) var reads = 0
    let value: JSONValue
    init(_ value: JSONValue) { self.value = value }
    func records(_ session: AccountSession) async throws -> [JSONValue] { reads += 1; return [value] }
    func record(_ id: String, session: AccountSession) async throws -> JSONValue? { reads += 1; return value }
    func save(_ record: JSONValue, session: AccountSession) async throws { throw HarborError(code: "unexpected-cloud-write") }
}

@MainActor final class ContinuePrivacyTests: XCTestCase {
    private func fixture() throws -> JSONValue {
        let file = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "continue-privacy-reference", withExtension: "json", subdirectory: "Fixtures"))
        let value = try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: file))
        XCTAssertEqual(value["actual_original_typescript_executed"], .bool(true)); XCTAssertEqual(value["provider_network_requests"].integer, 0); return value
    }
    private func directory() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("owned-private-cw-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true); return root
    }
    private func decode<T: Decodable>(_ value: JSONValue, as: T.Type = T.self) throws -> T { try JSONDecoder().decode(T.self, from: JSONEncoder().encode(value)) }
    private func legacy(_ raw: JSONValue) throws -> [String: ContinueDismissal] {
        try raw.objectValue.mapValues { value in
            var fields: [String: JSONValue] = ["timestampMs": value["t"], "progress": value["p"] == .null ? .integer(0) : value["p"]]
            for (old, new) in [("v", "videoID"), ("s", "season"), ("e", "episode")] where value[old] != .null { fields[new] = value[old] }
            return try decode(.object(fields))
        }
    }
    private func profile(_ raw: JSONValue) throws -> DeviceHouseholdProfile {
        let id = try XCTUnwrap(raw["id"].string)
        let desktop = try DesktopHouseholdProfile(.object(["syncId": .string("owned-" + id), "name": .string("Owned " + id), "color": .string("#7dd3fc"),
            "isPrimary": raw["isPrimary"] == .bool(true) ? .bool(true) : .bool(false), "settingsLinked": raw["settingsLinked"] == .bool(false) ? .bool(false) : .bool(true)]))
        return .init(id: id, desktop: desktop, shareStremioWith: raw["shareStremioWith"].string, localDataOwner: id)
    }
    func testEighteenExecutedDesktopScopesReadTheRequestedDocumentInsteadOfThePreviousMirror() throws {
        let rows = try fixture()["scopeCases"].array; XCTAssertEqual(rows.count, 18)
        for row in rows {
            let suite = "owned-cw-settings-" + UUID().uuidString, defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let memory = OwnedContinueSettings()
            for (key, raw) in row["settings"].objectValue {
                let owner = key.replacingOccurrences(of: "harbor.settings.", with: "")
                var document = ProfileSettingsDocument()
                document.values["cwPerProfile"] = try PropertyListSerialization.data(fromPropertyList: ["value": raw["cwPerProfile"] == .bool(true)], format: .binary, options: 0)
                memory.state.documents[owner] = document
            }
            let settings = ProfileSettingsStore(defaults: defaults, persistence: memory)
            try settings.activate(owner: "previous-person", sharedOwner: "previous-person", migrateLegacy: false)
            defaults.set(row["expected"]["private"] != .bool(true), forKey: "cwPerProfile")
            let profiles = try row["profiles"].array.map(profile), active = try XCTUnwrap(profiles.first { $0.id == row["activeId"].string })
            let preference = try settings.continuePreferences(owner: active.desktop.settingsLinked ? "shared" : active.id, sharedOwner: "shared")
            let route = HouseholdProfileRouting(profile: active, profiles: profiles, scope: .local(owner: "owned"), cwPerProfile: preference.perProfile)
            XCTAssertEqual(route.privateContinuing, row["expected"]["private"] == .bool(true), row["name"].string ?? "")
            XCTAssertEqual(route.stremioSourceID, row["expected"]["sharedId"].string)
            XCTAssertEqual(route.personal, row["expected"]["profileId"].string)
        }
    }
    func testUnsavedActiveSettingsAndMissingIndependentDocumentUseTheSameSharedFallbackAsDesktop() throws {
        let suite = "owned-live-cw-settings-" + UUID().uuidString, defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = ProfileSettingsStore(defaults: defaults, persistence: OwnedContinueSettings())
        try settings.activate(owner: "shared", sharedOwner: "shared", migrateLegacy: false)
        defaults.set(true, forKey: "cwPerProfile")
        var sources = ContinueWatchingSources(); sources.local = false; defaults.set(sources.rawValue, forKey: "cwSources")
        let current = try settings.continuePreferences(owner: "shared", sharedOwner: "shared")
        let missing = try settings.continuePreferences(owner: "not-created-yet", sharedOwner: "shared")
        XCTAssertTrue(current.perProfile); XCTAssertTrue(missing.perProfile); XCTAssertFalse(current.sources.local); XCTAssertFalse(missing.sources.local)
    }
    func testFiveExecutedDesktopMigrationsPreserveExplicitPrivateChoicesAndNeverSeedNewProfiles() throws {
        let rows = try fixture()["migrations"].array; XCTAssertEqual(rows.count, 5)
        for row in rows {
            let memory = OwnedContinueDismissals(); memory.old["shared"] = try legacy(row["initial"]["harbor.cw.dismissed.v1"])
            var initial = ContinueDismissalState()
            for id in ["a", "b"] where row["initial"]["harbor.cw.dismissed.private.v1." + id] != .null { initial.documents[id] = try legacy(row["initial"]["harbor.cw.dismissed.private.v1." + id]) }
            memory.state = initial; memory.failWrite = row["name"].string == "failed-write"
            let store = ContinueDismissalStore(persistence: memory)
            do { try store.migrate(scope: "owned", existingOwners: ["a": "shared", "b": "shared"]); XCTAssertFalse(memory.failWrite) }
            catch { XCTAssertTrue(memory.failWrite) }
            if row["name"].string == "new-profile" { try store.migrate(scope: "owned", existingOwners: ["a": "shared", "b": "shared", "d": "shared"]) }
            XCTAssertEqual(memory.state?.migrations.contains("owned"), row["expected"]["marker"] != .null)
            for id in ["a", "b", "d"] {
                let expected = row["expected"]["documents"][id], actual = memory.state?.documents[id]
                if expected == .null { XCTAssertNil(actual) }
                else { XCTAssertEqual(try JSONValue.encoded(try XCTUnwrap(actual)), try JSONValue.encoded(legacy(expected))) }
            }
            if memory.failWrite { XCTAssertThrowsError(try store.requireMigration(scope: "owned")) }
        }
    }
    func testFourExecutedResumeOwnershipCasesMatchActualPlaybackMirroringCloudImportsAndRestart() async throws {
        let rows = try fixture()["resumeCases"].array; XCTAssertEqual(rows.count, 4)
        for row in rows {
            let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
            let sharedFile = root.appendingPathComponent("shared.json"), personalFile = root.appendingPathComponent("personal.json")
            let shared = ResumeStore(fileURL: sharedFile), personal = ResumeStore(fileURL: personalFile)
            try await shared.load(); try await personal.load()
            let now = UInt64(try XCTUnwrap(row["now"].numericValue)), name = row["name"].string
            let stores = PlaybackProgressStores(personalOwner: "a", sharedOwner: "source", personal: personal, shared: shared)
            let primary = name == "shared-playback" ? shared : personal
            let session = PlaybackSession(source: .init(url: "https://owned.invalid/video", headers: nil, subtitles: nil, via: "addon"), target: .init(id: "film"), startMs: 0, storageWarning: nil, progressEnabled: true, owner: "source", personalOwner: "a", progressStores: stores)
            if name != "cloud-only" {
                let success = try await PlaybackProgressCommit.save(.init(positionMs: 400_000, durationMs: 1_000_000, timestampMs: now, exiting: true), session: session, resume: primary, media: nil, library: nil); XCTAssertTrue(success)
            }
            let cloud: ResumeEntry = try decode(row["expected"]["shared"]["cloud"])
            _ = try await shared.importRemote(.init(id: "cloud"), entry: cloud, current: { true })
            if name == "start-over" { try await PlaybackProgressCommit.restart(session: session, resume: primary, timestampMs: now + 20) }
            for (file, key) in [(sharedFile, "shared"), (personalFile, "personal")] {
                let document = FileManager.default.fileExists(atPath: file.path) ? try JSONDecoder().decode(ResumeDocument.self, from: Data(contentsOf: file)) : .init()
                let expected: [String: ResumeEntry] = try decode(row["expected"][key]); XCTAssertEqual(document.entries, expected)
            }
        }
    }
    func testPrivateProjectionAndResumeExcludeNewerSharedCloudAndOtherProfilesAndKeepDismissalsSeparate() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let account = "owned-private-library-" + UUID().uuidString, person = account + "-a", other = account + "-b"
        defer { try? KeychainStore().remove(LibraryPresentation.key(owner: account)) }
        let local = LocalContinueStore(root: root), memory = OwnedContinueDismissals(), dismissals = ContinueDismissalStore(persistence: memory)
        try dismissals.migrate(scope: "owned", existingOwners: [person: account, other: account])
        for (owner, position, t) in [(person, 400_000.0, UInt64(10)), (other, 600_000.0, UInt64(20))] {
            _ = try await local.recordPlayback(.init(id: "film", type: "movie", name: "Owned film", source: .library, positionMs: position, durationMs: 1_000_000, t: t), personalOwner: owner, sharedOwner: "source", current: { true })
        }
        let cloud: JSONValue = .object(["_id": .string("film"), "type": .string("movie"), "name": .string("Owned film"), "_mtime": .integer(1000), "state": .object(["timeOffset": .integer(800_000), "duration": .integer(1_000_000)])])
        try await LibraryCache().save([cloud], owner: account)
        let service = OwnedPrivateLibrary(cloud), library = LibraryModel(localContinue: local, privateDismissals: dismissals, service: service)
        let session = AccountSession(authKey: "owned-no-provider-request", user: .init(id: account, email: nil, fullname: nil))
        await library.setSession(session, personalOwner: person, synchronize: false)
        library.setContinuePrivacy(true, migratedScope: "owned")
        await library.bindLocalContinuing(sharedOwner: "source", scope: "owned", active: { true })
        XCTAssertEqual(library.continuing.first?.progress, 0.4)
        let ownResume = await library.resume(for: .init(id: "film")); XCTAssertEqual(ownResume?.entry.ms, 400_000)
        let providerReads = await service.reads; XCTAssertEqual(providerReads, 0, "A private resume read must never query shared cloud progress")
        let own = try XCTUnwrap(library.continuing.first); library.hideContinuing(own, owner: account); XCTAssertTrue(library.continuing.isEmpty)
        library.setContinuePrivacy(false); XCTAssertEqual(library.continuing.first?.progress, 0.8)
        await library.setSession(session, personalOwner: other, synchronize: false)
        library.setContinuePrivacy(true, migratedScope: "owned")
        await library.bindLocalContinuing(sharedOwner: "source", scope: "other", active: { true })
        XCTAssertEqual(library.continuing.first?.progress, 0.6, "The other profile must not inherit the first profile's hidden title")
        let otherCard = try XCTUnwrap(library.continuing.first); library.hideContinuing(otherCard, owner: account)
        library.noteLocalProgress(.init(id: "film"), snapshot: .init(positionMs: 700_000, durationMs: 1_000_000, timestampMs: UInt64(Date().timeIntervalSince1970 * 1_000) + 10_000, exiting: true), owner: account, personalOwner: person)
        XCTAssertTrue(library.continuing.isEmpty, "A closing player from another profile cannot undo this profile's private dismissal")
        library.showContinuing(otherCard)
        await library.setSession(session, personalOwner: person, synchronize: false)
        library.setContinuePrivacy(true, migratedScope: "owned")
        await library.bindLocalContinuing(sharedOwner: "source", scope: "owned", active: { true })
        XCTAssertTrue(library.continuing.isEmpty); XCTAssertEqual(library.hiddenContinuing.count, 1)
        library.showContinuing(own); XCTAssertEqual(library.continuing.first?.progress, 0.4)
        let sharedResume = ResumeStore(fileURL: root.appendingPathComponent("shared-resume.json")), personalResume = ResumeStore(fileURL: root.appendingPathComponent("personal-resume.json"))
        try await sharedResume.load(); try await personalResume.load()
        library.bindPlaybackProgress(.init(personalOwner: person, sharedOwner: "source", personal: personalResume, shared: sharedResume))
        let playback = PlaybackSession(source: .init(url: "https://owned.invalid/video", headers: nil, subtitles: nil, via: "download"), target: .init(id: "film"), startMs: 0, storageWarning: nil, progressEnabled: true, owner: account, personalOwner: person, progressStores: library.playbackProgressStores)
        let committed = try await PlaybackProgressCommit.save(.init(positionMs: 700_000, durationMs: 1_000_000, timestampMs: 1_700_000_000_000, exiting: true), session: playback, resume: personalResume, media: .init(id: "film", type: "movie", name: "Owned film"), library: library)
        XCTAssertTrue(committed); XCTAssertEqual(library.continuing.first?.progress, 0.7)
        let a = try await personalResume.entry(playback.target), sharedEntry = try await sharedResume.entry(playback.target)
        let otherHistory = try await local.snapshot(personalOwner: other, sharedOwner: "source")
        XCTAssertEqual(a?.ms, 700_000); XCTAssertEqual(sharedEntry?.ms, 700_000)
        XCTAssertEqual(otherHistory.personal.entries["film"]?.positionMs, 600_000); XCTAssertEqual(otherHistory.shared.entries["film"]?.positionMs, 700_000)
    }
    func testUnavailablePrivateMigrationCannotFallBackToSharedCardsAndFailedDismissalKeepsPreviousChoices() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let owner = "owned-unavailable-private-" + UUID().uuidString
        defer { try? KeychainStore().remove(LibraryPresentation.key(owner: owner)) }
        let local = LocalContinueStore(root: root), memory = OwnedContinueDismissals(), dismissals = ContinueDismissalStore(persistence: memory)
        _ = try await local.recordPlayback(.init(id: "film", type: "movie", name: "Owned film", source: .library, positionMs: 400_000, durationMs: 1_000_000, t: 10), personalOwner: owner, sharedOwner: owner, current: { true })
        let library = LibraryModel(localContinue: local, privateDismissals: dismissals)
        await library.setSession(nil, personalOwner: owner, guestOwner: owner, synchronize: false)
        await library.bindLocalContinuing(sharedOwner: owner, scope: owner, active: { true })
        library.setContinuePrivacy(true, migratedScope: "not-migrated"); XCTAssertTrue(library.continuing.isEmpty); XCTAssertNotNil(library.presentationError)
        try dismissals.migrate(scope: owner, existingOwners: [owner: owner]); library.setContinuePrivacy(true, migratedScope: owner)
        let card = try XCTUnwrap(library.continuing.first); memory.failWrite = true
        library.hideContinuing(card, owner: owner)
        XCTAssertEqual(library.continuing.count, 1); XCTAssertTrue(try dismissals.values(owner: owner).isEmpty); XCTAssertNotNil(library.presentationError)
        let corruptMemory = OwnedContinueDismissals(); corruptMemory.state = .init(version: 2)
        let unavailable = LibraryModel(localContinue: local, privateDismissals: ContinueDismissalStore(persistence: corruptMemory))
        await unavailable.setSession(nil, personalOwner: owner, guestOwner: owner, synchronize: false)
        await unavailable.bindLocalContinuing(sharedOwner: owner, scope: owner, active: { true })
        XCTAssertEqual(unavailable.continuing.count, 1)
        unavailable.setContinuePrivacy(true)
        XCTAssertTrue(unavailable.continuing.isEmpty); XCTAssertNotNil(unavailable.presentationError)
    }
    func testLegacyOwnerMappingResolvesTheProfilesActualSharedSource() async throws {
        let context = ActivationMemory().context(); try context.prepare()
        let primary = try XCTUnwrap(context.profiles.active), other = try context.profiles.create(name: "Owned other")
        let account = "owned-migration-account-" + UUID().uuidString
        let session = AccountSession(authKey: "owned-offline", user: .init(id: account, email: nil, fullname: nil))
        try context.save(.init(account: SavedAccount(session: session, collection: .init(addons: [], records: [])), guestAddons: []))
        let primaryOwner = HouseholdProfileRouting(profile: primary, profiles: context.profiles.profiles, scope: context.profiles.scope, cwPerProfile: false).personal
        let otherOwner = HouseholdProfileRouting(profile: other, profiles: context.profiles.profiles, scope: context.profiles.scope, cwPerProfile: false).personal
        let owners = try context.continuingLegacyOwners()
        XCTAssertEqual(owners[primaryOwner], account); XCTAssertEqual(owners[otherOwner], account)
    }
    func testFailedPersonalResumeMirrorReportsFailureAndPreservesItsPreviousDiskCheckpoint() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let shared = ResumeStore(fileURL: root.appendingPathComponent("shared.json")), personalFile = root.appendingPathComponent("personal.json")
        let personal = ResumeStore(fileURL: personalFile); try await shared.load(); try await personal.load()
        let previous = ResumeSnapshot(positionMs: 200_000, durationMs: 1_000_000, timestampMs: 1_700_000_000_000, exiting: true)
        _ = try await personal.save(.init(id: "film"), snapshot: previous)
        let backup = personalFile.appendingPathExtension("previous"), original = try Data(contentsOf: personalFile)
        try FileManager.default.moveItem(at: personalFile, to: backup); try FileManager.default.createDirectory(at: personalFile, withIntermediateDirectories: false)
        let stores = PlaybackProgressStores(personalOwner: "person", sharedOwner: "source", personal: personal, shared: shared)
        let session = PlaybackSession(source: .init(url: "https://owned.invalid/video", headers: nil, subtitles: nil, via: "addon"), target: .init(id: "film"), startMs: 0, storageWarning: nil, progressEnabled: true, owner: "source", personalOwner: "person", progressStores: stores)
        do { _ = try await PlaybackProgressCommit.save(.init(positionMs: 400_000, durationMs: 1_000_000, timestampMs: previous.timestampMs + 1, exiting: true), session: session, resume: shared, media: nil, library: nil); XCTFail("A failed mirror must be reported") } catch { XCTAssertEqual((error as? HarborError)?.code, "resume-write-failed") }
        let kept = try await personal.entry(session.target), accepted = try await shared.entry(session.target)
        XCTAssertEqual(kept?.ms, 200_000); XCTAssertEqual(accepted?.ms, 400_000); XCTAssertEqual(try Data(contentsOf: backup), original)
    }
    func testProfileChangesReuseLiveFileActorsAndRejectLateOlderCheckpoints() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let registry = PlaybackProgressStoreRegistry { ResumeStore(fileURL: root.appendingPathComponent(EBookShelf.hash($0) + ".json")) }
        let closingPlayer = registry.store(owner: "shared-source")
        try await closingPlayer.load()
        let nextProfile = registry.store(owner: "shared-source")
        XCTAssertTrue(closingPlayer === nextProfile)
        XCTAssertFalse(nextProfile === registry.store(owner: "private-person-b"))
        _ = try await nextProfile.save(.init(id: "film"), snapshot: .init(positionMs: 600_000, durationMs: 1_000_000, timestampMs: 200, exiting: true))
        _ = try await closingPlayer.save(.init(id: "film"), snapshot: .init(positionMs: 400_000, durationMs: 1_000_000, timestampMs: 100, exiting: true))
        let actual = try await nextProfile.entry(.init(id: "film")); XCTAssertEqual(actual?.ms, 600_000)
    }
}

import XCTest
@testable import Harbor

@MainActor final class OwnedRetirementMemory: HouseholdProfilePersistence, HouseholdSessionPersistence, LegacyProfileLoading, LegacySourceRetirementPersistence {
    var households: [String: HouseholdProfileState] = [:]
    var sessions: HouseholdSessionState?
    var legacy = LegacyProfileConfiguration(configuration: .init(account: nil, guestAddons: []))
    var archive: LocalSourceArchive?
    var failSessionWrite = false, failArchive = false, failRemoval = false
    func readHousehold(_ key: String) throws -> HouseholdProfileState? { households[key] }
    func writeHousehold(_ value: HouseholdProfileState, key: String) throws { households[key] = value }
    func readHouseholdSessions() throws -> HouseholdSessionState? { sessions }
    func writeHouseholdSessions(_ value: HouseholdSessionState) throws { if failSessionWrite { throw HarborError(code: "owned-session-write") }; sessions = value }
    func loadLegacyProfile() throws -> LegacyProfileConfiguration { legacy }
    func readLegacy() throws -> SavedAccount? { legacy.configuration.account }
    func archive(_ value: LocalSourceArchive) throws { if failArchive { throw HarborError(code: "owned-archive-write") }; archive = value }
    func removeLegacySession() throws { if failRemoval { throw HarborError(code: "owned-legacy-remove") }; legacy = .init(configuration: .init(account: nil, guestAddons: [])) }
}
actor OwnedRetirementOfflineService: LibraryServing {
    private(set) var requests = 0
    func records(_ session: AccountSession) throws -> [JSONValue] { requests += 1; throw HarborError(code: "owned-offline") }
    func record(_ id: String, session: AccountSession) throws -> JSONValue? { requests += 1; throw HarborError(code: "owned-offline") }
    func save(_ record: JSONValue, session: AccountSession) throws { requests += 1; throw HarborError(code: "owned-offline") }
}

@MainActor final class LocalSourceMigrationTests: XCTestCase {
    private func account() -> SavedAccount {
        let addon = Addon(manifest: .object(["id": .string("owned-addon"), "unknown": .object(["preserved": .bool(true)])]), transportUrl: "https://owned.invalid/manifest.json", enabled: false)
        return .init(session: .init(authKey: "owned-retired-access-token", user: .init(id: "owned-retired-user", email: nil, fullname: "Owned profile")),
            collection: .init(addons: [addon], records: [.object(["transportUrl": .string(addon.transportUrl), "manifest": addon.manifest, "unknownFlags": .array([.integer(7)])])]))
    }
    private func context(_ memory: OwnedRetirementMemory) throws -> AppProfileContext {
        let context = AppProfileContext(profiles: HouseholdProfileStore(scope: .local(owner: "owned-retirement-device"), persistence: memory),
            sessions: HouseholdSessionVault(persistence: memory), legacy: memory)
        try context.prepare(); return context
    }
    private func root() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("owned-source-retirement-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true); return root
    }
    private func record(_ id: String, time: Int64) -> JSONValue {
        .object(["_id": .string(id), "type": .string("movie"), "name": .string("Owned film"), "removed": .bool(false), "temp": .bool(false),
            "_mtime": .integer(time), "state": .object(["timeOffset": .integer(400_000), "duration": .integer(1_000_000), "unknownWatched": .string("keep")])])
    }
    func testRetirementKeepsOwnerAliasesCompleteAddonRecordsPendingHistoryAndSharedProfileRoutingWithoutNetwork() async throws {
        let memory = OwnedRetirementMemory(), account = account(); memory.legacy = .init(configuration: .init(account: account, guestAddons: []))
        let context = try context(memory), before = try XCTUnwrap(context.binding), second = try context.profiles.create(name: "Owned second profile")
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        let cache = LibraryCache(directory: root), service = OwnedRetirementOfflineService(), queue = LibraryWriteQueue(service: service, directory: root)
        let older = record("tt1234567", time: 1_700_000_000_000), pending = record("tt1234567", time: 1_700_000_001_000)
        try await cache.save([older], owner: account.session.user.id)
        _ = try await queue.put(pending, session: account.session)
        try await context.retireStremioAccounts(using: .init(cache: cache, queue: queue))
        XCTAssertEqual(context.binding, before); XCTAssertNil(context.configuration?.account)
        XCTAssertEqual(context.configuration?.dataOwner, account.session.user.id)
        XCTAssertEqual(try JSONValue.encoded(context.configuration?.guestAddons), try JSONValue.encoded(account.collection.addons))
        XCTAssertEqual(context.configuration?.localSource?.collection.records, account.collection.records)
        let restored = try await LibraryCache(directory: root).read(owner: account.session.user.id), remaining = try await LibraryWriteQueue(service: service, directory: root).pending(owner: account.session.user.id)
        XCTAssertEqual(restored, [pending]); XCTAssertTrue(remaining.isEmpty)
        let library = LibraryModel(service: service, writeQueue: queue, cache: cache)
        await library.setSession(nil, personalOwner: before.personalOwner, guestOwner: before.progressOwner, synchronize: false)
        let media = try XCTUnwrap(LibraryRecord(raw: pending).media)
        XCTAssertFalse(library.hasCloudSession); XCTAssertTrue(library.bookmarked(media))
        await library.toggleBookmark(media); XCTAssertFalse(library.bookmarked(media)); XCTAssertNil(library.error)
        await library.toggleBookmark(media); XCTAssertTrue(library.bookmarked(media)); XCTAssertNil(library.error)
        let restart = LibraryModel(service: service, writeQueue: queue, cache: LibraryCache(directory: root))
        await restart.setSession(nil, personalOwner: before.personalOwner, guestOwner: before.progressOwner, synchronize: false)
        XCTAssertTrue(restart.bookmarked(media)); XCTAssertFalse(restart.hasCloudSession)
        let recovered = await restart.resume(for: .init(id: media.id), refresh: false)
        XCTAssertEqual(recovered?.entry.ms, 400_000)
        let requests = await service.requests; XCTAssertEqual(requests, 1, "Only test setup attempted an owned offline write; migration must never contact an account")
        let encoded = try JSONEncoder().encode(context.configuration)
        XCTAssertFalse(String(decoding: encoded, as: UTF8.self).contains(account.session.authKey))
        XCTAssertEqual(memory.sessions?.identityOwner, before.identityOwner)
        let selected = try await context.select(second.id); XCTAssertTrue(selected)
        XCTAssertEqual(context.binding?.progressOwner, before.progressOwner); XCTAssertNotEqual(context.binding?.personalOwner, before.personalOwner)
        XCTAssertNil(context.configuration?.account); XCTAssertEqual(context.configuration?.dataOwner, account.session.user.id)
        let reopened = try self.context(memory); XCTAssertNil(reopened.configuration?.account); XCTAssertEqual(reopened.binding?.progressOwner, before.progressOwner)
    }
    func testUnavailableLocalLibraryCannotDiscardTheSessionOrAnySavedSource() async throws {
        let memory = OwnedRetirementMemory(); memory.legacy = .init(configuration: .init(account: account(), guestAddons: []))
        let context = try context(memory), previous = context.configuration
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        let blocked = root.appendingPathComponent("not-a-directory"); try Data("owned-blocker".utf8).write(to: blocked)
        do { try await context.retireStremioAccounts(using: .init(cache: LibraryCache(directory: blocked), queue: LibraryWriteQueue(directory: root))); XCTFail("Unavailable local storage") } catch { }
        XCTAssertEqual(context.configuration, previous)
        XCTAssertEqual(memory.sessions?.sources.values.first?.configuration, previous)
    }
    func testFailedVaultCommitPreservesAuthenticationAndRetriesFromTheAlreadyDurableLocalLibrary() async throws {
        let memory = OwnedRetirementMemory(), account = account(); memory.legacy = .init(configuration: .init(account: account, guestAddons: []))
        let context = try context(memory), previous = context.configuration
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        let cache = LibraryCache(directory: root), queue = LibraryWriteQueue(service: OwnedRetirementOfflineService(), directory: root)
        let pending = record("tt1234567", time: 1_700_000_001_000); _ = try await queue.put(pending, session: account.session)
        memory.failSessionWrite = true
        do { try await context.retireStremioAccounts(using: .init(cache: cache, queue: queue)); XCTFail("Rejected vault write") } catch { }
        XCTAssertEqual(context.configuration, previous)
        let copied = try await cache.read(owner: account.session.user.id); XCTAssertEqual(copied, [pending])
        memory.failSessionWrite = false
        try await context.retireStremioAccounts(using: .init(cache: cache, queue: queue))
        XCTAssertNil(context.configuration?.account)
        let final = try await cache.read(owner: account.session.user.id); XCTAssertEqual(final, [pending])
    }
    func testRetirementRejectsALateConfigurationChangeAndNeverOverwritesTheReplacement() async throws {
        let memory = OwnedRetirementMemory(); memory.legacy = .init(configuration: .init(account: account(), guestAddons: []))
        let context = try context(memory), profile = try XCTUnwrap(context.profiles.active)
        let vault = context.sessions, lease = try vault.bind(profile: profile, profiles: context.profiles.profiles, scope: context.profiles.scope)
        let replacement = HouseholdSourceAccount(account: nil, guestAddons: [])
        do {
            try await vault.retireStremioAccounts { _ in try await MainActor.run { try vault.save(replacement, using: lease) } }
            XCTFail("Changed configuration must invalidate the retirement transaction")
        } catch { }
        XCTAssertEqual(vault.current, replacement)
    }
    func testGuestChoicesEmptySourcesAndExistingRetiredArchivesAreIdempotent() async throws {
        let memory = OwnedRetirementMemory(), context = try context(memory), before = context.configuration
        try await context.sessions.retireStremioAccounts { _ in XCTFail("A fresh local profile has no session to retire") }
        XCTAssertEqual(context.configuration, before); XCTAssertTrue(context.configuration?.guestAddons?.isEmpty == true)
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        try await context.retireStremioAccounts(using: .init(cache: LibraryCache(directory: root), queue: LibraryWriteQueue(directory: root)))
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
        let archive = LocalSourceArchive(owner: "owned-alias", collection: account().collection)
        let value = HouseholdSourceAccount(account: nil, guestAddons: [], localSource: archive)
        XCTAssertEqual(try JSONDecoder().decode(HouseholdSourceAccount.self, from: JSONEncoder().encode(value)), value)
    }
    func testLegacyArchiveFailureNeverRemovesTheTokenAndRemovalFailureCanSafelyRetry() throws {
        let memory = OwnedRetirementMemory(), account = account(); memory.legacy = .init(configuration: .init(account: account, guestAddons: []))
        memory.failArchive = true; XCTAssertThrowsError(try LegacySourceRetirement.run(memory)); XCTAssertNotNil(try memory.readLegacy()); XCTAssertNil(memory.archive)
        memory.failArchive = false; memory.failRemoval = true
        XCTAssertThrowsError(try LegacySourceRetirement.run(memory)); XCTAssertNotNil(try memory.readLegacy())
        XCTAssertEqual(memory.archive?.collection.records, account.collection.records)
        memory.failRemoval = false; try LegacySourceRetirement.run(memory); XCTAssertNil(try memory.readLegacy())
        try LegacySourceRetirement.run(memory)
        XCTAssertEqual(memory.archive?.owner, account.session.user.id)
    }
    func testActualOwnedKeychainRetirementPreservesConfigurationWithoutKeepingTheSession() throws {
        let suffix = UUID().uuidString, legacy = "owned-legacy-source-" + suffix, prefix = "owned-local-source-" + suffix
        let account = account(), persistence = KeychainLegacySourceRetirement(legacyKey: legacy, archivePrefix: prefix)
        let archiveKey = prefix + EBookShelf.hash(account.session.user.id)
        defer { try? KeychainStore().remove(legacy); try? KeychainStore().remove(archiveKey) }
        try KeychainStore().write(account, key: legacy); try LegacySourceRetirement.run(persistence)
        XCTAssertNil(try KeychainStore().read(legacy, as: SavedAccount.self))
        let archive = try XCTUnwrap(KeychainStore().read(archiveKey, as: LocalSourceArchive.self))
        XCTAssertEqual(archive.owner, account.session.user.id); XCTAssertEqual(archive.collection.records, account.collection.records)
        XCTAssertFalse(String(decoding: try JSONEncoder().encode(archive), as: UTF8.self).contains(account.session.authKey))
    }
    func testEveryDesktopLanguageHasAccountIndependentSourceAndPrivateHistoryGuidance() {
        XCTAssertEqual(Set(LocalProfileText.translations.keys), Set(InterfaceLanguage.all.map(\.code)))
        XCTAssertEqual(Set(LocalProfileText.serverNotes.keys), Set(InterfaceLanguage.all.map(\.code)))
        for language in InterfaceLanguage.all {
            XCTAssertEqual(LocalProfileText.translations[language.code]?.count, 2)
            XCTAssertNotNil(LocalProfileText.serverNotes[language.code])
            for key in LocalProfileText.Key.allCases {
                let text = LocalProfileText.value(key, language: language.code)
                XCTAssertFalse(text.isEmpty); XCTAssertFalse(text.contains("Stremio"))
                if key != .serverAccount { XCTAssertTrue(text.contains("Harbor")) }
            }
        }
        XCTAssertTrue(LocalProfileText.value(.serverAccount, language: "en").contains("original service closed"))
        XCTAssertTrue(LocalProfileText.value(.serverAccount, language: "es").contains("servicio original cerró"))
    }
}

import XCTest
import Observation
@testable import Harbor

@MainActor private final class LaunchRosterMemory: HouseholdProfilePersistence {
    var value: HouseholdProfileState?
    func readHousehold(_ key: String) throws -> HouseholdProfileState? { value }
    func writeHousehold(_ value: HouseholdProfileState, key: String) throws { self.value = value }
}
@MainActor private final class LaunchSettingsMemory: ProfileSettingsPersistence {
    var value: ProfileSettingsState?
    var failRead = false
    var failWrite = false
    var writes = 0
    func readProfileSettings() throws -> ProfileSettingsState? {
        if failRead { throw HarborError(code: "synthetic-launch-read") }; return value
    }
    func writeProfileSettings(_ value: ProfileSettingsState) throws {
        if failWrite { throw HarborError(code: "synthetic-launch-write") }; self.value = value; writes += 1
    }
}
@MainActor private final class LaunchPlayback: ProfilePlaybackControlling { func close() {} }

@MainActor final class ProfileLaunchTests: XCTestCase {
    private func rows() throws -> [DeviceHouseholdProfile] {
        let store = HouseholdProfileStore(scope: .local(owner: "synthetic-launch"), persistence: LaunchRosterMemory())
        return [try store.create(name: "One"), try store.create(name: "Two")]
    }
    private func defaults() throws -> (UserDefaults, String) {
        let name = "synthetic-launch-" + UUID().uuidString
        return (try XCTUnwrap(UserDefaults(suiteName: name)), name)
    }
    private func locked(_ row: DeviceHouseholdProfile) -> DeviceHouseholdProfile {
        var result = row
        result.credential = DeviceProfileCredential(version: 1, salt: Data(repeating: 1, count: 32), rounds: 600_000, digest: Data(repeating: 2, count: 32))
        return result
    }
    func testStartupChoicesRespectOneProfileAndNeverBypassTheSelectedPIN() throws {
        let people = try rows()
        let selected = people[0].id
        for interval in ProfileLaunchPreferences.Interval.allCases {
            let settings = ProfileLaunchPreferences(interval: interval)
            XCTAssertEqual(settings.launchAction(profiles: [people[0]], selectedID: selected, selectedUnlocked: true, lastSelected: 0, now: 5_000), .resume)
            XCTAssertEqual(settings.launchAction(profiles: [locked(people[0])], selectedID: selected, selectedUnlocked: false, lastSelected: 4_999, now: 5_000), .choose)
            XCTAssertEqual(settings.launchAction(profiles: people, selectedID: "missing", selectedUnlocked: true, lastSelected: 4_999, now: 5_000), .choose)
        }
        XCTAssertEqual(ProfileLaunchPreferences().launchAction(profiles: people, selectedID: selected, selectedUnlocked: true, lastSelected: 4_999, now: 5_000), .choose)
        XCTAssertEqual(ProfileLaunchPreferences(interval: .never).launchAction(profiles: people, selectedID: selected, selectedUnlocked: true, lastSelected: 0, now: 5_000), .resume)
    }
    func testTimedPromptsUseTheLastExplicitSelectionAndTheExactReferenceIntervals() throws {
        let people = try rows()
        for (interval, seconds) in [(ProfileLaunchPreferences.Interval.fifteenMinutes, 900.0), (.thirtyMinutes, 1_800.0)] {
            let preferences = ProfileLaunchPreferences(interval: interval)
            XCTAssertFalse(preferences.promptOnReturn(profiles: people, lastSelected: 1_000, now: 1_000 + seconds - 0.01))
            XCTAssertTrue(preferences.promptOnReturn(profiles: people, lastSelected: 1_000, now: 1_000 + seconds))
            XCTAssertFalse(preferences.promptOnReturn(profiles: [people[0]], lastSelected: 0, now: 10_000))
            XCTAssertFalse(preferences.promptOnReturn(profiles: people, lastSelected: 1_000, now: 999))
            XCTAssertFalse(preferences.promptOnReturn(profiles: people, lastSelected: 0, now: .infinity))
            XCTAssertEqual(preferences.launchAction(profiles: people, selectedID: people[0].id, selectedUnlocked: true, lastSelected: 1_000, now: 1_000 + seconds - 1), .resume)
            XCTAssertEqual(preferences.launchAction(profiles: people, selectedID: people[0].id, selectedUnlocked: true, lastSelected: 1_000, now: 1_000 + seconds), .choose)
        }
        for interval in [ProfileLaunchPreferences.Interval.launch, .never] {
            XCTAssertFalse(ProfileLaunchPreferences(interval: interval).promptOnReturn(profiles: people, lastSelected: 0, now: 10_000))
        }
    }
    func testDefaultIsAlwaysUnprotectedAndDoesNotSuppressLaterTimedPrompts() throws {
        let people = try rows()
        var settings = ProfileLaunchPreferences(interval: .fifteenMinutes, defaultID: people[1].id)
        XCTAssertEqual(settings.launchAction(profiles: people, selectedID: people[0].id, selectedUnlocked: false, lastSelected: 0, now: 10_000), .useDefault(people[1].id))
        XCTAssertTrue(settings.promptOnReturn(profiles: people, lastSelected: 0, now: 10_000))
        XCTAssertNil(settings.defaultProfile(in: [people[0], locked(people[1])]))
        XCTAssertEqual(settings.launchAction(profiles: [people[0], locked(people[1])], selectedID: people[1].id, selectedUnlocked: false, lastSelected: 9_999, now: 10_000), .choose)
        settings.defaultID = "removed"
        XCTAssertNil(settings.defaultProfile(in: people))
    }
    func testSelectionClockRestartsAndKeepsHouseholdsAndInvalidTimestampsSeparate() throws {
        let (storage, suite) = try defaults(); defer { storage.removePersistentDomain(forName: suite) }
        let one = ProfileSelectionClock(scope: .local(owner: "one"), storage: storage)
        let two = ProfileSelectionClock(scope: .local(owner: "two"), storage: storage)
        let remote = ProfileSelectionClock(scope: .harbor(account: "one"), storage: storage)
        XCTAssertEqual(one.lastSelected, 0); one.recordSelection(at: 2_000)
        XCTAssertEqual(ProfileSelectionClock(scope: .local(owner: "one"), storage: storage).lastSelected, 2_000)
        XCTAssertEqual(two.lastSelected, 0); XCTAssertEqual(remote.lastSelected, 0)
        one.recordSelection(at: .infinity); one.recordSelection(at: -1)
        XCTAssertEqual(one.lastSelected, 2_000)
    }
    func testStartupPreferencesReadAndWriteTheSharedDocumentWithoutChangingIndependentSettings() throws {
        let (storage, suite) = try defaults(); defer { storage.removePersistentDomain(forName: suite) }
        let memory = LaunchSettingsMemory(), store = ProfileSettingsStore(defaults: storage, persistence: memory)
        storage.set("es", forKey: "uiLanguage")
        try store.activate(owner: "shared", sharedOwner: "shared", migrateLegacy: true)
        try store.setLaunchPreferences(.init(interval: .thirtyMinutes, defaultID: "one"), sharedOwner: "shared", expectedOwner: "shared")
        try store.activate(owner: "independent", sharedOwner: "shared", migrateLegacy: false)
        storage.set("never", forKey: "profilePromptInterval"); storage.set("fr", forKey: "uiLanguage")
        XCTAssertTrue(store.saveCurrent())
        XCTAssertEqual(try store.launchPreferences(sharedOwner: "shared").interval, .thirtyMinutes)
        try store.setLaunchPreferences(.init(interval: .fifteenMinutes, defaultID: "two"), sharedOwner: "shared", expectedOwner: "independent")
        XCTAssertEqual(storage.string(forKey: "profilePromptInterval"), "never"); XCTAssertEqual(storage.string(forKey: "uiLanguage"), "fr")
        let restarted = ProfileSettingsStore(defaults: storage, persistence: memory)
        XCTAssertEqual(try restarted.launchPreferences(sharedOwner: "shared"), .init(interval: .fifteenMinutes, defaultID: "two"))
        try restarted.activate(owner: "independent", sharedOwner: "shared", migrateLegacy: false)
        XCTAssertEqual(storage.string(forKey: "profilePromptInterval"), "never")
        try restarted.activate(owner: "shared", sharedOwner: "shared", migrateLegacy: false)
        XCTAssertEqual(storage.string(forKey: "profilePromptInterval"), "15m"); XCTAssertEqual(storage.string(forKey: "uiLanguage"), "es")
    }
    func testFailedOrStaleStartupWritesPreserveTheCommittedDocumentAndPublishedMirror() throws {
        let (storage, suite) = try defaults(); defer { storage.removePersistentDomain(forName: suite) }
        let memory = LaunchSettingsMemory(), store = ProfileSettingsStore(defaults: storage, persistence: memory)
        try store.activate(owner: "shared", sharedOwner: "shared", migrateLegacy: true)
        try store.setLaunchPreferences(.init(interval: .never, defaultID: "one"), sharedOwner: "shared", expectedOwner: "shared")
        let before = memory.value, writes = memory.writes
        memory.failWrite = true
        XCTAssertThrowsError(try store.setLaunchPreferences(.init(interval: .launch), sharedOwner: "shared", expectedOwner: "shared"))
        XCTAssertEqual(memory.value, before); XCTAssertEqual(storage.string(forKey: "profilePromptInterval"), "never")
        memory.failWrite = false
        XCTAssertThrowsError(try store.setLaunchPreferences(.init(interval: .launch), sharedOwner: "shared", expectedOwner: "stale"))
        XCTAssertThrowsError(try store.setLaunchPreferences(.init(defaultID: String(repeating: "x", count: 257)), sharedOwner: "shared", expectedOwner: "shared"))
        XCTAssertEqual(memory.writes, writes)
    }
    func testAnUnknownOrUnreadableStartupDocumentNeverCopiesAnotherHouseholdsMirror() throws {
        let (storage, suite) = try defaults(); defer { storage.removePersistentDomain(forName: suite) }
        storage.set("never", forKey: "profilePromptInterval"); storage.set("private-person", forKey: "defaultProfileId")
        let memory = LaunchSettingsMemory(), store = ProfileSettingsStore(defaults: storage, persistence: memory)
        XCTAssertEqual(try store.launchPreferences(sharedOwner: "different-household"), ProfileLaunchPreferences())
        XCTAssertEqual(memory.writes, 0)
        memory.failRead = true
        let failed = ProfileSettingsStore(defaults: storage, persistence: memory)
        XCTAssertThrowsError(try failed.launchPreferences(sharedOwner: "different-household")); XCTAssertEqual(memory.writes, 0)
    }
    func testPlaybackRegistrationAndRemovalAreObservableForDeferredPrompts() {
        let registry = ProfilePlaybackRegistry(), player = LaunchPlayback()
        let registered = expectation(description: "observe playback registration")
        withObservationTracking { _ = registry.hasActivePlayback } onChange: { registered.fulfill() }
        XCTAssertTrue(registry.register(player, generation: registry.generation))
        XCTAssertEqual(XCTWaiter.wait(for: [registered], timeout: 1), .completed); XCTAssertTrue(registry.hasActivePlayback)
        let removed = expectation(description: "observe playback dismissal")
        withObservationTracking { _ = registry.hasActivePlayback } onChange: { removed.fulfill() }
        registry.remove(player)
        XCTAssertEqual(XCTWaiter.wait(for: [removed], timeout: 1), .completed); XCTAssertFalse(registry.hasActivePlayback)
    }
    func testPrepareAnExpiredOrdinaryDeviceSelectionClockForStartupReturnUI() {
        let clock = ProfileSelectionClock(scope: AppProfileContext.shared.profiles.scope)
        clock.recordSelection(at: 0)
        XCTAssertEqual(clock.lastSelected, 0)
    }
}

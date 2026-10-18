import XCTest
@testable import Harbor

@MainActor private final class ProfileSettingsMemory: ProfileSettingsPersistence {
    var state: ProfileSettingsState?
    var failRead = false
    var failWrite = false
    var writes = 0
    func readProfileSettings() throws -> ProfileSettingsState? {
        if failRead { throw HarborError(code: "synthetic-read") }; return state
    }
    func writeProfileSettings(_ value: ProfileSettingsState) throws {
        if failWrite { throw HarborError(code: "synthetic-write") }; state = value; writes += 1
    }
}
@MainActor final class ProfileSettingsTests: XCTestCase {
    private func defaults() throws -> (UserDefaults, String) {
        let name = "synthetic-profile-settings-" + UUID().uuidString
        return (try XCTUnwrap(UserDefaults(suiteName: name)), name)
    }
    func testLinkedAndIndependentRolesPreserveTypedSettingsAndForkTheSharedValues() throws {
        let (defaults, suite) = try defaults(); defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("ja", forKey: "uiLanguage"); defaults.set(true, forKey: "hideSpoilers")
        let data = Data([0, 1, 2, 255]); defaults.set(data, forKey: "iphone.player-options.v1")
        let memory = ProfileSettingsMemory(), store = ProfileSettingsStore(defaults: defaults, persistence: memory)
        try store.activate(owner: "shared", sharedOwner: "shared", migrateLegacy: true)
        try store.activate(owner: "one", sharedOwner: "shared", migrateLegacy: false)
        XCTAssertEqual(defaults.string(forKey: "uiLanguage"), "ja"); XCTAssertEqual(defaults.data(forKey: "iphone.player-options.v1"), data)
        defaults.set("fr", forKey: "uiLanguage"); defaults.set(false, forKey: "hideSpoilers")
        try store.activate(owner: "shared", sharedOwner: "shared", migrateLegacy: false)
        XCTAssertEqual(defaults.string(forKey: "uiLanguage"), "ja"); XCTAssertTrue(defaults.bool(forKey: "hideSpoilers"))
        defaults.set("es", forKey: "uiLanguage")
        try store.activate(owner: "two", sharedOwner: "shared", migrateLegacy: false)
        XCTAssertEqual(defaults.string(forKey: "uiLanguage"), "es")
        try store.activate(owner: "one", sharedOwner: "shared", migrateLegacy: false)
        XCTAssertEqual(defaults.string(forKey: "uiLanguage"), "fr"); XCTAssertFalse(defaults.bool(forKey: "hideSpoilers"))
    }
    func testASecondHouseholdNeverSeedsItselfFromAnotherHouseholdsMirror() throws {
        let (defaults, suite) = try defaults(); defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("private-custom-preset", forKey: "iphone.theme.preset")
        defaults.set("kept-device-consent", forKey: "harbor-sports-consent")
        let memory = ProfileSettingsMemory(), store = ProfileSettingsStore(defaults: defaults, persistence: memory)
        try store.activate(owner: "household-a", sharedOwner: "household-a", migrateLegacy: true)
        try store.activate(owner: "household-b", sharedOwner: "household-b", migrateLegacy: false)
        XCTAssertNil(defaults.object(forKey: "iphone.theme.preset")); XCTAssertNil(defaults.object(forKey: "uiLanguage"))
        XCTAssertEqual(defaults.string(forKey: "harbor-sports-consent"), "kept-device-consent")
        try store.activate(owner: "household-a", sharedOwner: "household-a", migrateLegacy: false)
        XCTAssertEqual(defaults.string(forKey: "iphone.theme.preset"), "private-custom-preset")
    }
    func testFailedSwitchKeepsThePublishedOwnerAndMirrorAndRetrySavesTheLastEdits() throws {
        let (defaults, suite) = try defaults(); defer { defaults.removePersistentDomain(forName: suite) }
        let memory = ProfileSettingsMemory(), store = ProfileSettingsStore(defaults: defaults, persistence: memory)
        try store.activate(owner: "shared", sharedOwner: "shared", migrateLegacy: true)
        defaults.set(25.0, forKey: "ebook.fontSize"); memory.failWrite = true
        XCTAssertThrowsError(try store.activate(owner: "second", sharedOwner: "shared", migrateLegacy: false))
        XCTAssertEqual(store.owner, "shared"); XCTAssertEqual(defaults.double(forKey: "ebook.fontSize"), 25)
        XCTAssertFalse(store.saveCurrent()); XCTAssertNotNil(store.error)
        memory.failWrite = false
        try store.activate(owner: "second", sharedOwner: "shared", migrateLegacy: false)
        XCTAssertEqual(defaults.double(forKey: "ebook.fontSize"), 25); XCTAssertNil(store.error)
    }
    func testRestartLoadsTheSavedRoleInsteadOfAnInterruptedPreviousMirror() throws {
        let (defaults, suite) = try defaults(); defer { defaults.removePersistentDomain(forName: suite) }
        let memory = ProfileSettingsMemory(), store = ProfileSettingsStore(defaults: defaults, persistence: memory)
        defaults.set("ja", forKey: "uiLanguage")
        try store.activate(owner: "shared", sharedOwner: "shared", migrateLegacy: true)
        try store.activate(owner: "one", sharedOwner: "shared", migrateLegacy: false)
        defaults.set("fr", forKey: "uiLanguage"); XCTAssertTrue(store.saveCurrent())
        defaults.set("interrupted-mirror", forKey: "uiLanguage")
        let restart = ProfileSettingsStore(defaults: defaults, persistence: memory)
        try restart.activate(owner: "one", sharedOwner: "shared", migrateLegacy: false)
        XCTAssertEqual(defaults.string(forKey: "uiLanguage"), "fr")
        let writes = memory.writes; XCTAssertTrue(restart.saveCurrent()); XCTAssertEqual(memory.writes, writes)
    }
    func testUnreadableOrUnknownStoredFieldsCannotOverwriteTheActiveDefaults() throws {
        let (defaults, suite) = try defaults(); defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("ja", forKey: "uiLanguage")
        let memory = ProfileSettingsMemory(); memory.failRead = true
        let failed = ProfileSettingsStore(defaults: defaults, persistence: memory)
        XCTAssertFalse(failed.ready); XCTAssertThrowsError(try failed.activate(owner: "one", sharedOwner: "shared", migrateLegacy: false))
        XCTAssertEqual(defaults.string(forKey: "uiLanguage"), "ja"); XCTAssertEqual(memory.writes, 0)
        memory.failRead = false
        memory.state = ProfileSettingsState(documents: ["one": ProfileSettingsDocument(values: ["private-session": Data()])])
        let invalid = ProfileSettingsStore(defaults: defaults, persistence: memory)
        XCTAssertFalse(invalid.ready); XCTAssertEqual(memory.writes, 0)
    }
    func testPlaybackReloadReadsTheSelectedMirrorWithoutRewritingUnknownOrUnreadableSavedFields() throws {
        let (defaults, suite) = try defaults(); defer { defaults.removePersistentDomain(forName: suite) }
        let data = try JSONSerialization.data(withJSONObject: ["speed": 1.25, "future-field": ["keep": true]])
        defaults.set(data, forKey: "iphone.player-options.v1")
        let preferences = PlaybackPreferences(storage: defaults)
        XCTAssertEqual(preferences.options.speed, 1.25)
        preferences.reloadPreferences()
        XCTAssertEqual(defaults.data(forKey: "iphone.player-options.v1"), data)
        let unreadable = Data([0, 1, 255]); defaults.set(unreadable, forKey: "iphone.player-options.v1")
        preferences.reloadPreferences()
        XCTAssertEqual(preferences.options.speed, PlaybackOptions().speed)
        XCTAssertEqual(defaults.data(forKey: "iphone.player-options.v1"), unreadable)
    }
}

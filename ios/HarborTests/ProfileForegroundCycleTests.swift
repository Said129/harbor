import XCTest
@testable import Harbor

final class ProfileForegroundCycleTests: XCTestCase {
    func testInitialActivationNeverCountsAsReturnRegardlessOfColdSceneOrdering() {
        var activeLaunch = ProfileForegroundCycle()
        XCTAssertFalse(activeLaunch.observe(active: true)); XCTAssertFalse(activeLaunch.observe(active: true))
        var inactiveLaunch = ProfileForegroundCycle()
        XCTAssertFalse(inactiveLaunch.observe(active: false)); XCTAssertFalse(inactiveLaunch.observe(active: false))
        XCTAssertFalse(inactiveLaunch.observe(active: true)); XCTAssertFalse(inactiveLaunch.observe(active: true))
    }
    func testOnlyASubsequentDepartureAndActivationCanConsumeOneReturn() {
        var cycle = ProfileForegroundCycle()
        XCTAssertFalse(cycle.observe(active: true))
        for _ in 0..<3 {
            XCTAssertFalse(cycle.observe(active: false)); XCTAssertFalse(cycle.observe(active: false))
            XCTAssertTrue(cycle.observe(active: true)); XCTAssertFalse(cycle.observe(active: true))
        }
    }
    @MainActor func testPrepareOrdinaryExpiredDefaultProfileForTheFailedPhoneReturnJourney() async throws {
        // Necessary fresh-device setup, not a replay of the approved creation UI.
        let context = AppProfileContext.shared
        try context.prepare()
        let row: DeviceHouseholdProfile
        if let existing = context.profiles.profiles.first(where: { $0.desktop.name == "Inicio iPhone" }) { row = existing }
        else { row = try context.profiles.create(name: "Inicio iPhone") }
        let selected = try await context.select(row.id); XCTAssertTrue(selected)
        try context.save(HouseholdSourceAccount(account: nil, guestAddons: []))
        let settings = ProfileSettingsStore.shared
        let owner = try XCTUnwrap(context.binding?.settingsOwner)
        try settings.activate(owner: owner, sharedOwner: context.householdSettingsOwner, migrateLegacy: false)
        try settings.setLaunchPreferences(.init(interval: .fifteenMinutes, defaultID: row.id), sharedOwner: context.householdSettingsOwner, expectedOwner: owner)
        let clock = ProfileSelectionClock(scope: context.profiles.scope); clock.recordSelection(at: 0)
        XCTAssertEqual(clock.lastSelected, 0)
        XCTAssertEqual(try settings.launchPreferences(sharedOwner: context.householdSettingsOwner).defaultID, row.id)
        XCTAssertEqual(context.profiles.active?.desktop.name, "Inicio iPhone")
    }
}

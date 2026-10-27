import XCTest
@testable import Harbor

final class ContinuePrivacyHomeSeedTests: XCTestCase {
    @MainActor func testPrepareActualPrivateHistoriesForTwoOwnedProfilesOnOneGuestSource() async throws {
        let prepared = try ContinuePrivacyInterfaceSeedTests.prepareOwnedSharedGuest()
        let context = AppProfileContext.shared, binding = prepared.binding
        let otherOwner = HouseholdProfileRouting(profile: prepared.other, profiles: context.profiles.profiles,
            scope: context.profiles.scope, cwPerProfile: false).personal
        let now = UInt64(Date().timeIntervalSince1970 * 1_000)
        for (suffix, owner, title, t) in [("a", binding.personalOwner, "Owned private A", now - 1), ("b", otherOwner, "Owned private B", now)] {
            let entry = LocalContinueEntry(id: "owned-private-home-" + suffix, type: "movie", name: title, isAnime: false, source: .local,
                positionMs: 400_000, durationMs: 1_000_000, t: t)
            _ = try await LocalContinueStore.shared.recordPlayback(entry, personalOwner: owner, sharedOwner: binding.progressOwner, current: { true })
        }
        let a = try await LocalContinueStore.shared.snapshot(personalOwner: binding.personalOwner, sharedOwner: binding.progressOwner)
        let b = try await LocalContinueStore.shared.snapshot(personalOwner: otherOwner, sharedOwner: binding.progressOwner)
        XCTAssertEqual(a.personal.sorted.map(\.id), ["owned-private-home-a"]); XCTAssertEqual(b.personal.sorted.map(\.id), ["owned-private-home-b"])
        XCTAssertEqual(a.shared.sorted.count, 2)
        UserDefaults.standard.set(true, forKey: "cwPerProfile")
        XCTAssertTrue(ProfileSettingsStore.shared.saveCurrent())
    }
}

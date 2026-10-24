import XCTest
@testable import Harbor

@MainActor final class PageCustomizationScopeTests: XCTestCase {
    func testIndependentProfileInheritsOnlyExplicitSharedLayoutAndItsFirstEditNeverChangesThatSharedLayout() throws {
        let owners = owned(); defer { clean(owners) }
        var shared = PageLayout(); shared.order = ["shared-row"]
        try KeychainStore().write(shared, key: key(owners[0]))
        let personal = PageCustomization(owner: owners[1], page: "anime", inheritedOwner: owners[0])
        XCTAssertTrue(personal.ready); XCTAssertEqual(personal.layout.order, shared.order)
        XCTAssertNil(try KeychainStore().read(key(owners[1]), as: PageLayout.self), "Reading inherited settings must not create a private override")
        personal.change { $0.order = ["personal-row"] }
        let reopened = PageCustomization(owner: owners[1], page: "anime", inheritedOwner: owners[0])
        XCTAssertEqual(reopened.layout.order, ["personal-row"])
        XCTAssertEqual(try KeychainStore().read(key(owners[0]), as: PageLayout.self)?.order, ["shared-row"])
        let second = PageCustomization(owner: owners[2], page: "anime", inheritedOwner: owners[0]); XCTAssertEqual(second.layout.order, shared.order)
    }
    func testLegacyLayoutMigratesOnceWithoutOverwritingTheOriginalOrCopyingToAnotherProfile() throws {
        let owners = owned(); defer { clean(owners) }
        var original = PageLayout(); original.order = ["discovery-anime-airing"]; original.renamed = ["discovery-anime-airing": "Owned title"]
        try KeychainStore().write(original, key: key(owners[0]))
        let primary = PageCustomization(owner: owners[1], page: "anime", legacyOwner: owners[0])
        XCTAssertTrue(primary.ready); XCTAssertEqual(primary.layout.order, original.order); XCTAssertEqual(primary.layout.renamed, original.renamed)
        let other = PageCustomization(owner: owners[2], page: "anime", legacyOwner: owners[0])
        XCTAssertTrue(other.ready); XCTAssertTrue(other.layout.order.isEmpty); XCTAssertTrue(other.layout.renamed.isEmpty)
        let stored = try KeychainStore().read(key(owners[0]), as: PageLayout.self); XCTAssertEqual(stored?.renamed, original.renamed)
        let marker = try KeychainStore().read(migration(owners[0]), as: String.self); XCTAssertEqual(marker, owners[1])
    }
    func testAnIndependentProfileDoesNotReadLegacyAccountLayoutUnlessMigrationWasExplicitlyAuthorized() throws {
        let owners = owned(); defer { clean(owners) }
        var legacy = PageLayout(); legacy.hidden = ["discovery-anime-popular"]
        try KeychainStore().write(legacy, key: key(owners[0]))
        let personal = PageCustomization(owner: owners[1], page: "anime")
        XCTAssertTrue(personal.ready); XCTAssertTrue(personal.layout.hidden.isEmpty)
        personal.change { $0.renamed = ["discovery-anime-airing": "Personal title"] }
        let reopened = PageCustomization(owner: owners[1], page: "anime")
        XCTAssertEqual(reopened.layout.renamed["discovery-anime-airing"], "Personal title")
        let other = PageCustomization(owner: owners[2], page: "anime"); XCTAssertTrue(other.layout.renamed.isEmpty)
    }
    func testExistingDestinationChoicesWinOverLegacyAndRetryingACopyUsesOnlyItsClaimedOwner() throws {
        let owners = owned(); defer { clean(owners) }
        var legacy = PageLayout(); legacy.cwTop = true
        var local = PageLayout(); local.order = ["owned-current-choice"]
        try KeychainStore().write(legacy, key: key(owners[0])); try KeychainStore().write(local, key: key(owners[1]))
        let existing = PageCustomization(owner: owners[1], page: "anime", legacyOwner: owners[0])
        XCTAssertEqual(existing.layout.order, local.order); XCTAssertFalse(existing.layout.cwTop)
        try KeychainStore().remove(key(owners[1])); try KeychainStore().write(owners[1], key: migration(owners[0]))
        let retry = PageCustomization(owner: owners[1], page: "anime", legacyOwner: owners[0]); XCTAssertTrue(retry.ready); XCTAssertTrue(retry.layout.cwTop)
        let unrelated = PageCustomization(owner: owners[2], page: "anime", legacyOwner: owners[0]); XCTAssertFalse(unrelated.layout.cwTop)
    }
    func testMalformedLegacyLayoutIsPreservedAndNeverReplacedWithDefaultsOrClaimed() throws {
        let owners = owned(); defer { clean(owners) }
        var invalid = PageLayout(); invalid.version = 2
        try KeychainStore().write(invalid, key: key(owners[0]))
        let target = PageCustomization(owner: owners[1], page: "anime", legacyOwner: owners[0])
        XCTAssertFalse(target.ready); XCTAssertNotNil(target.error)
        XCTAssertNil(try KeychainStore().read(key(owners[1]), as: PageLayout.self))
        XCTAssertNil(try KeychainStore().read(migration(owners[0]), as: String.self))
        XCTAssertEqual(try KeychainStore().read(key(owners[0]), as: PageLayout.self)?.version, 2)
    }
    private func owned() -> [String] { (0..<3).map { "owned-page-scope-" + UUID().uuidString + "-" + String($0) } }
    private func key(_ owner: String) -> String { "page-layout-" + EBookShelf.hash(owner + "|anime") }
    private func migration(_ owner: String) -> String { "page-layout-migration-" + EBookShelf.hash(owner + "|anime") }
    private func clean(_ owners: [String]) { for owner in owners { try? KeychainStore().remove(key(owner)); try? KeychainStore().remove(migration(owner)) } }
}

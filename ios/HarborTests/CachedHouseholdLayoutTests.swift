import XCTest
@testable import Harbor

@MainActor private final class OwnedProjectionJournal: PageSyncPersistence {
    var record: PageSyncRecord?
    var remaining: Int?
    func read(_ key: String) throws -> PageSyncRecord? { record }
    func write(_ value: PageSyncRecord, key: String) throws {
        if let remaining {
            guard remaining > 0 else { throw HarborError(code: "owned-journal-failure") }
            self.remaining = remaining - 1
        }
        record = value
    }
}

@MainActor final class CachedHouseholdLayoutTests: XCTestCase {
    private func rail() -> PageRail {
        let url = "https://addon.example/private-config/manifest.json"
        let addon = Addon(manifest: .object(["id": .string("org.owned.catalog")]), transportUrl: url, enabled: true)
        let definition = CatalogDefinition(id: "anime", type: "series", name: "Owned", extra: [])
        return .catalog(CatalogRow(plan: .init(key: "private-request", url: url, title: "Owned", kind: "series",
            addon: addon, addonPriority: 0, timeoutMs: 1_000, catalog: definition), metas: []))
    }
    private func page(_ name: String) -> JSONValue {
        .object(["order": .array([.string("org.owned.catalog-series-anime"), .string("cm-drama")]),
            "hidden": .array([.string("org.owned.catalog-series-anime")]),
            "renamed": .object(["cm-drama": .string(name), "org.owned.catalog-series-anime": .string(name + " addon")]),
            "numerals": .array([.string("org.owned.catalog-series-anime")]),
            "heroSource": .string("org.owned.catalog-series-anime"), "future": .string(name)])
    }
    private func state(_ value: JSONValue) -> JSONValue {
        .object(["rev": .integer(10), "docs": .array([.object(["key": .string("desktop-primary:home"), "rev": .integer(10), "value": value])])])
    }
    private func accepted() -> JSONValue { .object(["results": .array([.object(["ok": .bool(true), "rev": .integer(11)])])]) }

    func testDeferredAddonRowsUseTheLastSharedProjectionWithoutRevertingKnownRowsOrUploading() async throws {
        let h = try OwnedHouseholdLayouts(); defer { h.close() }
        h.set("desktop-primary", "home", page("Earlier")); h.set("linked-other", "home", page("Latest"), rev: 11)
        let a = try h.active(); try await h.run(a)
        let row = rail(); a.home.preferences.setEditingRails([row])
        XCTAssertEqual(a.home.preferences.layout.renamed["discovery-cm-drama"], "Latest")
        XCTAssertEqual(a.home.preferences.layout.renamed[row.id], "Latest addon")
        XCTAssertEqual(a.home.preferences.layout.order.first, row.id)
        XCTAssertTrue(a.home.preferences.layout.hidden.contains(row.id)); XCTAssertTrue(a.home.preferences.layout.numerals.contains(row.id))
        XCTAssertEqual(a.home.preferences.layout.heroSource, row.id)
        try await h.run(a)
        XCTAssertTrue(h.packets.isEmpty); XCTAssertFalse(a.home.hasPendingChanges)
        XCTAssertEqual(a.home.preferences.wireProjection?["future"], .string("Latest"))
    }
    func testEditingEachSharedSectionPreservesTheLatestOtherProfilesOpaqueFieldsAndOnlyDirtiesTheEditor() async throws {
        let h = try OwnedHouseholdLayouts(); defer { h.close() }
        for profile in ["desktop-primary", "linked-other"] {
            let opaque = profile == "desktop-primary" ? "Earlier" : "Latest"
            var nav = h.navigation("Same").objectValue; nav["future"] = .string(opaque)
            h.set(profile, "nav", .object(nav)); h.set(profile, "home", page(opaque))
            h.set(profile, "anime", .object(["future": .string(opaque)]))
            h.set(profile, "services", .object(["netflix": .bool(true), "future": .object(["value": .string(opaque)])]))
        }
        let a = try h.active(); try await h.run(a)
        a.navigation.preferences.change { $0.renamed["anime"] = "My nav" }
        a.home.preferences.change { $0.cwTop = true }
        a.anime.preferences.change { $0.renamed["continueWatching"] = "My anime" }
        XCTAssertTrue(a.services.preferences.setEnabled(false, for: "netflix"))
        try await h.run(a)
        XCTAssertEqual(h.packets.count, 4)
        for packet in h.packets {
            let write = try XCTUnwrap(packet["writes"].array.first), key = try XCTUnwrap(write["key"].string)
            XCTAssertTrue(key.hasPrefix("desktop-primary:"))
            let opaque = key.hasSuffix(":services") ? write["value"]["future"]["value"] : write["value"]["future"]
            XCTAssertEqual(opaque, .string("Latest"))
            let wire = String(decoding: try JSONEncoder().encode(write), as: UTF8.self)
            for privateField in ["_nativeLayoutProjection", "_nativeLocalLayoutEditor", "private-config", "private-request"] { XCTAssertFalse(wire.contains(privateField)) }
        }
        XCTAssertFalse(h.engine.hasPendingChanges)
    }
    func testDeferredMappingAfterAnAcknowledgedLocalEditDoesNotCreateAnotherWrite() async throws {
        let h = try OwnedHouseholdLayouts(); defer { h.close() }
        h.set("desktop-primary", "home", page("Original"))
        let a = try h.active(); try await h.run(a)
        a.home.preferences.change { $0.renamed["discovery-cm-drama"] = "Acknowledged edit" }
        try await h.run(a); XCTAssertEqual(h.packets.count, 1)
        let row = rail(); a.home.preferences.setEditingRails([row])
        try await h.run(a)
        XCTAssertEqual(h.packets.count, 1, "Mapping a late server row must not invent a second local edit")
        XCTAssertEqual(a.home.preferences.layout.renamed["discovery-cm-drama"], "Acknowledged edit")
        XCTAssertEqual(a.home.preferences.layout.renamed[row.id], "Original addon"); XCTAssertFalse(a.home.hasPendingChanges)
    }
    func testOfflineIndependentSelectionInheritsCachedSharedSectionsAndDeferredRowsWithoutCreatingPrivateRecords() async throws {
        let h = try OwnedHouseholdLayouts(); defer { h.close() }
        h.set("desktop-primary", "home", page("Cached")); h.set("desktop-primary", "nav", h.navigation("Cached nav"))
        h.set("desktop-primary", "anime", .object(["renamed": .object(["continueWatching": .string("Cached anime")])]))
        h.set("desktop-primary", "services", .object(["netflix": .bool(false)]))
        try await h.run(h.active()); try await h.select("inherits")
        let offline = try h.active()
        try HarborHouseholdLayoutSync.bindCached(account: h.account, context: h.context, active: offline)
        let row = rail(); offline.home.preferences.setEditingRails([row])
        XCTAssertEqual(offline.home.preferences.layout.renamed[row.id], "Cached addon")
        XCTAssertEqual(offline.navigation.preferences.value.renamed["anime"], "Cached nav")
        XCTAssertEqual(offline.anime.preferences.layout.renamed["continueWatching"], "Cached anime")
        XCTAssertFalse(offline.services.preferences.isEnabled("netflix")); XCTAssertTrue(h.packets.isEmpty)
        let scope = offline.home.preferences.scope
        XCTAssertNil(try KeychainStore().read("page-layout-scope-" + EBookShelf.hash(scope.key + "|home"), as: PageLayout.self), "Reading an inherited layout must not create a private override")
    }
    func testOfflineSelectionPreservesExplicitPrivateAndDeviceLocalChoices() async throws {
        let h = try OwnedHouseholdLayouts(); defer { h.close() }
        h.set("desktop-primary", "home", page("Shared")); h.set("independent", "home", page("Private"))
        h.set("desktop-primary", "services", .object(["netflix": .bool(false)]))
        try await h.run(h.active()); try await h.select("independent")
        let offline = try h.active()
        offline.services.preferences.bind(.local(owner: offline.services.preferences.owner))
        XCTAssertTrue(offline.services.preferences.setEnabled(false, for: "disney"))
        try HarborHouseholdLayoutSync.bindCached(account: h.account, context: h.context, active: offline)
        XCTAssertEqual(offline.home.preferences.layout.renamed["discovery-cm-drama"], "Private")
        XCTAssertFalse(offline.services.preferences.isEnabled("disney"))
        XCTAssertTrue(offline.services.preferences.isEnabled("netflix"), "An explicit device record must not inherit the shared disabled value")
        XCTAssertTrue(h.packets.isEmpty)
    }
    func testCachedSelectionRejectsAnotherAccountBeforeRebindingAnyVisiblePreference() throws {
        let h = try OwnedHouseholdLayouts(); defer { h.close() }
        let active = try h.active(), before = active.home.preferences.scope
        XCTAssertThrowsError(try HarborHouseholdLayoutSync.bindCached(account: "foreign-account", context: h.context, active: active))
        XCTAssertEqual(active.home.preferences.scope, before); XCTAssertEqual(active.navigation.preferences.scope, before)
        XCTAssertTrue(h.packets.isEmpty)
    }
    func testTheIdentityFacadeRestoresCachedLayoutsWithoutContactingARetiredServerAndRecoversAnEditAfterHydration() async throws {
        let h = try OwnedHouseholdLayouts(); defer { h.close() }
        h.set("desktop-primary", "home", page("Cached")); try await h.run(h.active())
        let identityKey = "harbor-identity-" + EBookShelf.hash(h.account)
        try KeychainStore().write(JSONValue.object(["session": .object(["id": .string(h.account), "username": .string("Owned"),
            "token": .string("retired-owned-token"), "refresh": .string("retired-owned-refresh")])]), key: identityKey)
        var networkCalls = 0
        let cloud = HarborProfileSync(owner: h.account, profile: ProfilePreferences.forOwner(h.account), transport: { _, _, _, _ in networkCalls += 1; return .null })
        defer { cloud.suspendForProfileChange(); try? KeychainStore().remove(identityKey) }
        let binding = try XCTUnwrap(h.context.binding)
        cloud.bindHouseholdContext(h.context) {}
        cloud.bindLayoutOwner(binding.settingsOwner, profileID: "desktop-primary", primary: true)
        InterfacePreferences.shared.navigation.bind(.local(owner: binding.settingsOwner))
        cloud.page("home").preferences.bind(.local(owner: binding.settingsOwner))
        cloud.bindCachedLayouts()
        XCTAssertTrue(cloud.serverRetired); XCTAssertFalse(cloud.hydrated); XCTAssertEqual(networkCalls, 0)
        XCTAssertEqual(cloud.page("home").preferences.layout.renamed["discovery-cm-drama"], "Cached")
        cloud.page("home").preferences.change { $0.cwTop = true }
        XCTAssertFalse(cloud.page("home").hasPendingChanges, "Cached binding must not arm an unauthenticated writer")
        let resumed = try h.active(); try await h.run(resumed)
        XCTAssertTrue(resumed.home.preferences.layout.cwTop)
        XCTAssertEqual(h.packets.count, 1); XCTAssertEqual(h.packets.first?["writes"].array.first?["key"], .string("desktop-primary:home"))
        XCTAssertEqual(networkCalls, 0)
    }
    func testAQueueWriteFailureAndLateCatalogMappingCannotEraseALocallySavedEditAfterReopening() async throws {
        let h = try OwnedHouseholdLayouts(); defer { h.close() }
        let preferences = try h.active().home.preferences, memory = OwnedProjectionJournal(), raw = page("Saved")
        let engine = HarborPageSync(preferences: preferences, persistence: memory), profile = try XCTUnwrap(h.context.profiles.active?.desktop.raw)
        defer { engine.unbind() }
        try await engine.synchronize(state: state(raw), account: h.account, profile: profile) { _ in XCTFail("No default upload"); return .null }
        memory.remaining = 0
        preferences.change { $0.renamed["discovery-cm-drama"] = "Device edit" }
        let row = rail(); preferences.setEditingRails([row])
        XCTAssertEqual(preferences.layout.renamed["discovery-cm-drama"], "Device edit")
        XCTAssertNotNil(engine.error); engine.unbind(); memory.remaining = nil
        let reopened = PageCustomization(owner: preferences.owner, page: "home"); reopened.bind(preferences.scope); reopened.setEditingRails([row])
        let resumed = HarborPageSync(preferences: reopened, persistence: memory); defer { resumed.unbind() }
        var sends = 0
        try await resumed.synchronize(state: state(raw), account: h.account, profile: profile) { packet in
            sends += 1; let value = try XCTUnwrap(packet["writes"].array.first?["value"])
            XCTAssertEqual(value["renamed"]["cm-drama"], .string("Device edit"))
            XCTAssertEqual(value["renamed"]["org.owned.catalog-series-anime"], .string("Saved addon"))
            XCTAssertEqual(value["future"], .string("Saved")); return self.accepted()
        }
        XCTAssertEqual(sends, 1); XCTAssertFalse(resumed.hasPendingChanges)
    }
    func testAnInterruptedAdoptionCannotReplaceANewerSharedProjectionWithTheSameVisibleFields() async throws {
        let h = try OwnedHouseholdLayouts(); defer { h.close() }
        let preferences = try h.active().home.preferences, memory = OwnedProjectionJournal(), raw = h.page("Same")
        let engine = HarborPageSync(preferences: preferences, persistence: memory), profile = try XCTUnwrap(h.context.profiles.active?.desktop.raw)
        defer { engine.unbind() }
        memory.remaining = 1
        do { try await engine.synchronize(state: state(raw), account: h.account, profile: profile) { _ in XCTFail("No upload"); return .null }; XCTFail("Journal completion fails") } catch {}
        XCTAssertNotNil(memory.record?.adoption)
        var latest = raw.objectValue; latest["future"] = .string("Newest shared opaque field")
        try preferences.apply(preferences.layout, to: preferences.scope, projection: .object(latest))
        engine.unbind(); memory.remaining = nil
        let reopened = PageCustomization(owner: preferences.owner, page: "home")
        let resumed = HarborPageSync(preferences: reopened, persistence: memory); defer { resumed.unbind() }
        try await resumed.synchronize(state: state(raw), account: h.account, profile: profile) { _ in XCTFail("A shared projection is not a local edit"); return .null }
        XCTAssertEqual(reopened.wireProjection?["future"], .string("Newest shared opaque field"))
        XCTAssertNil(memory.record?.adoption); XCTAssertFalse(resumed.hasPendingChanges)
    }
}

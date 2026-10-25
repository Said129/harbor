import XCTest
@testable import Harbor

@MainActor private final class OwnedHouseholdLayouts {
    let memory: ActivationMemory
    let context: AppProfileContext
    var engine: HarborHouseholdLayoutSync
    var documents: [JSONValue] = []
    var packets: [JSONValue] = []
    var failNetwork = false
    var beforeSend: (@MainActor () async throws -> Void)?
    private var surfaces: [HarborHouseholdLayoutSync.Active] = []
    private var revision: Int64 = 100
    var account: String { memory.identity }
    init() throws {
        let memory = ActivationMemory(); self.memory = memory
        context = memory.context(); engine = HarborHouseholdLayoutSync(account: memory.identity)
        try context.prepare()
        var linked = memory.remote("linked-other", primary: false).objectValue; linked["settingsLinked"] = .bool(true)
        let roster = memory.document([memory.remote(), .object(linked), memory.remote("independent", primary: false), memory.remote("inherits", primary: false)])
        try context.activateHarbor(account: memory.identity, document: roster)
    }
    func set(_ profile: String, _ section: String, _ value: JSONValue, rev: Int64 = 10) {
        let key = profile + ":" + section
        let document = JSONValue.object(["key": .string(key), "rev": .integer(rev), "value": value])
        if let index = documents.firstIndex(where: { $0["key"].string == key }) { documents[index] = document }
        else { documents.append(document) }
        revision = max(revision, rev)
    }
    func page(_ name: String) -> JSONValue {
        .object(["order": .array([.string("cm-drama")]), "renamed": .object(["cm-drama": .string(name)]), "future": .string("keep-desktop-value")])
    }
    func navigation(_ name: String) -> JSONValue {
        .object(["order": .array([.string("anime"), .string("home")]), "renamed": .object(["anime": .string(name)]), "future": .string("keep-desktop-value")])
    }
    func active() throws -> HarborHouseholdLayoutSync.Active {
        let binding = try XCTUnwrap(context.binding), row = try XCTUnwrap(context.profiles.active)
        let scope = NavigationScope.harbor(owner: binding.settingsOwner, account: account, profile: row.syncID, linked: row.desktop.settingsLinked)
        let navigation = ScopedNavigationPreferences(); navigation.bind(scope)
        let services = StreamingPreferences(owner: binding.settingsOwner); services.bind(scope)
        let home = PageCustomization(owner: binding.settingsOwner, page: "home"); home.bind(scope)
        let anime = PageCustomization(owner: binding.settingsOwner, page: "anime"); anime.bind(scope)
        let interface = InterfacePreferences.shared
        let result = HarborHouseholdLayoutSync.Active(navigation: HarborNavigationSync(owner: binding.settingsOwner, preferences: navigation,
                defaultOrder: interface.defaultNavigationOrder, knownIDs: Set(HarborSection.allCases.map(\.rawValue)).subtracting(["search"])),
            services: HarborStreamingSync(owner: binding.settingsOwner, preferences: services), home: HarborPageSync(preferences: home), anime: HarborPageSync(preferences: anime))
        surfaces.append(result); return result
    }
    func select(_ syncID: String) async throws {
        let row = try XCTUnwrap(context.profiles.profiles.first { $0.syncID == syncID })
        let changed = try await context.select(row.id); XCTAssertTrue(changed)
    }
    func run(_ active: HarborHouseholdLayoutSync.Active) async throws {
        let state = JSONValue.object(["rev": .integer(revision), "docs": .array(documents)])
        try await engine.synchronize(state: state, context: context, active: active, requestSync: {}, send: { body in
            self.packets.append(body)
            if self.failNetwork { throw HarborError(code: "network") }
            if let action = self.beforeSend { self.beforeSend = nil; try await action() }
            let write = try XCTUnwrap(body["writes"].array.first), key = try XCTUnwrap(write["key"].string)
            let previous = self.documents.first { $0["key"].string == key }
            XCTAssertEqual(write["baseRev"].numericValue, previous?["rev"].numericValue ?? 0)
            self.revision += 1
            let accepted = JSONValue.object(["key": .string(key), "rev": .integer(self.revision), "value": write["value"]])
            if let index = self.documents.firstIndex(where: { $0["key"].string == key }) { self.documents[index] = accepted }
            else { self.documents.append(accepted) }
            return .object(["results": .array([.object(["key": .string(key), "ok": .bool(true), "rev": .integer(self.revision)])])])
        }, check: {})
    }
    func close() {
        beforeSend = nil; engine.invalidate()
        for surface in surfaces { surface.navigation.unbind(); surface.services.unbind(); surface.home.unbind(); surface.anime.unbind() }
        guard let binding = context.binding else { return }
        for row in context.profiles.profiles {
            let personal = HouseholdProfileRouting(profile: row, profiles: context.profiles.profiles, scope: context.profiles.scope, cwPerProfile: false).personal
            let owner = row.desktop.settingsLinked ? binding.sharedSettingsOwner : personal
            let scope = NavigationScope.harbor(owner: owner, account: account, profile: row.syncID, linked: row.desktop.settingsLinked)
            var keys = [scope.key, NavigationScope.local(owner: owner).key, "scoped-streaming-" + EBookShelf.hash(scope.key), "native-streaming-" + EBookShelf.hash(owner)]
            keys.append("navigation-sync-" + EBookShelf.hash(scope.key + "|" + row.syncID + ":nav"))
            let bytes = try! JSONEncoder().encode([scope.key, row.syncID + ":services"])
            keys.append("streaming-sync-" + EBookShelf.hash(String(decoding: bytes, as: UTF8.self)))
            for page in ["home", "anime"] {
                keys += ["page-layout-" + EBookShelf.hash(owner + "|" + page), "page-layout-scope-" + EBookShelf.hash(scope.key + "|" + page),
                    "page-layout-sync-" + EBookShelf.hash(scope.key + "|" + row.syncID + ":" + page)]
            }
            keys.append("mobile-profile-" + EBookShelf.hash(context.profiles.appearanceOwner(row)))
            for key in keys { try? KeychainStore().remove(key) }
        }
    }
}

@MainActor final class HouseholdLayoutHydrationTests: XCTestCase {
    func testIncomingInactiveSectionsPopulateTheSharedAndIndependentStoresWithoutUploadingDefaults() async throws {
        let h = try OwnedHouseholdLayouts(); defer { h.close() }
        h.set("desktop-primary", "nav", h.navigation("Shared first"))
        h.set("linked-other", "nav", h.navigation("Shared last"), rev: 11)
        h.set("independent", "nav", h.navigation("Private nav"))
        h.set("desktop-primary", "home", h.page("Shared first home"))
        h.set("linked-other", "home", h.page("Shared last home"), rev: 11)
        h.set("independent", "home", h.page("Private home"))
        h.set("linked-other", "anime", .object(["renamed": .object(["continueWatching": .string("Shared anime")])]))
        h.set("independent", "services", .object(["netflix": .bool(false)]))
        h.set("unknown-profile", "home", .array([]))
        let active = try h.active(); try await h.run(active)
        XCTAssertEqual(active.navigation.preferences.value.renamed["anime"], "Shared last")
        XCTAssertEqual(active.home.preferences.layout.renamed["discovery-cm-drama"], "Shared last home")
        XCTAssertEqual(active.anime.preferences.layout.renamed["continueWatching"], "Shared anime")
        try await h.select("independent"); let independent = try h.active()
        XCTAssertEqual(independent.navigation.preferences.value.renamed["anime"], "Private nav")
        XCTAssertEqual(independent.home.preferences.layout.renamed["discovery-cm-drama"], "Private home")
        XCTAssertFalse(independent.services.preferences.isEnabled("netflix"))
        try await h.select("inherits"); let inherited = try h.active(); try await h.run(inherited)
        XCTAssertEqual(inherited.home.preferences.layout.renamed["discovery-cm-drama"], "Shared last home")
        XCTAssertEqual(inherited.navigation.preferences.value.renamed["anime"], "Shared last")
        let owner = try XCTUnwrap(h.context.binding?.settingsOwner)
        let inheritedScope = NavigationScope.harbor(owner: owner, account: h.account, profile: "inherits", linked: false)
        XCTAssertNil(try KeychainStore().read("page-layout-scope-" + EBookShelf.hash(inheritedScope.key + "|home"), as: PageLayout.self))
        XCTAssertTrue(h.packets.isEmpty); XCTAssertFalse(h.engine.hasPendingChanges)
    }
    func testAnIdenticalFullPullDoesNotRevertSharedValuesToAnEarlierProfilesDocumentOrEchoThem() async throws {
        let h = try OwnedHouseholdLayouts(); defer { h.close() }
        h.set("desktop-primary", "home", h.page("Earlier")); h.set("linked-other", "home", h.page("Last"), rev: 11)
        h.set("desktop-primary", "nav", h.navigation("Earlier")); h.set("linked-other", "nav", h.navigation("Last"), rev: 11)
        let active = try h.active(); try await h.run(active); try await h.run(active)
        XCTAssertEqual(active.home.preferences.layout.renamed["discovery-cm-drama"], "Last")
        XCTAssertEqual(active.navigation.preferences.value.renamed["anime"], "Last")
        XCTAssertTrue(h.packets.isEmpty); XCTAssertFalse(active.home.hasPendingChanges)
    }
    func testSwitchingLinkedProfilesBeforeAFlushPublishesOnlyTheProfileThatOwnedTheLocalEdit() async throws {
        let h = try OwnedHouseholdLayouts(); defer { h.close() }
        h.set("desktop-primary", "home", h.page("Original")); h.set("linked-other", "home", h.page("Original"))
        let a = try h.active(); try await h.run(a)
        a.home.preferences.change { $0.renamed["discovery-cm-drama"] = "Owned on A" }
        XCTAssertTrue(a.home.hasPendingChanges)
        try await h.select("linked-other"); let b = try h.active(); try await h.run(b)
        XCTAssertEqual(h.packets.map { $0["writes"].array.first?["key"].string }, ["desktop-primary:home"])
        XCTAssertEqual(b.home.preferences.layout.renamed["discovery-cm-drama"], "Owned on A")
        let raw = try XCTUnwrap(h.packets.first?["writes"].array.first?["value"])
        XCTAssertEqual(raw["future"].string, "keep-desktop-value")
        let wire = String(decoding: try JSONEncoder().encode(raw), as: UTF8.self)
        for secret in ["_nativeLocalLayoutEditor", "owned-stremio-secret", "localDataOwner", "artworkServer"] { XCTAssertFalse(wire.contains(secret)) }
        XCTAssertFalse(b.home.hasPendingChanges); XCTAssertFalse(h.engine.hasPendingChanges)
    }
    func testAnInactiveProfilesQueueSurvivesNetworkFailureAndACompletelyNewCoordinator() async throws {
        let h = try OwnedHouseholdLayouts(); defer { h.close() }
        h.set("desktop-primary", "home", h.page("Original")); h.set("linked-other", "home", h.page("Original"))
        let a = try h.active(); try await h.run(a)
        a.home.preferences.change { $0.renamed["discovery-cm-drama"] = "Offline edit" }
        try await h.select("linked-other"); let b = try h.active(); h.failNetwork = true
        do { try await h.run(b); XCTFail("The simulated network is disconnected") } catch { XCTAssertEqual((error as? HarborError)?.code, "network") }
        XCTAssertTrue(h.engine.hasPendingChanges)
        h.engine = HarborHouseholdLayoutSync(account: h.account); h.failNetwork = false
        let reopened = try h.active(); try await h.run(reopened)
        XCTAssertEqual(h.packets.count, 2)
        XCTAssertTrue(h.packets.allSatisfy { $0["writes"].array.first?["key"].string == "desktop-primary:home" })
        XCTAssertEqual(reopened.home.preferences.layout.renamed["discovery-cm-drama"], "Offline edit")
        XCTAssertFalse(h.engine.hasPendingChanges)
    }
    func testAChangedLinkedServerDocumentKeepsTheDisplacedPendingVersionRecoverable() async throws {
        let h = try OwnedHouseholdLayouts(); defer { h.close() }
        h.set("linked-other", "home", h.page("Original"), rev: 9); h.set("desktop-primary", "home", h.page("Original"))
        let active = try h.active(); try await h.run(active)
        active.home.preferences.change { $0.renamed["discovery-cm-drama"] = "Recoverable device choice" }
        h.set("linked-other", "home", h.page("New Desktop choice"), rev: 120)
        try await h.run(active)
        XCTAssertEqual(active.home.preferences.layout.renamed["discovery-cm-drama"], "New Desktop choice")
        XCTAssertTrue(active.home.hasParkedVersion); XCTAssertFalse(active.home.hasPendingChanges)
        active.home.restoreMyVersion(); try await h.run(active)
        XCTAssertEqual(active.home.preferences.layout.renamed["discovery-cm-drama"], "Recoverable device choice")
        XCTAssertFalse(active.home.hasParkedVersion)
    }
    func testASelectionChangedDuringTheRequestCannotConsumeALateAcknowledgementOrItsQueue() async throws {
        let h = try OwnedHouseholdLayouts(); defer { h.close() }
        h.set("desktop-primary", "home", h.page("Original")); h.set("independent", "home", h.page("Independent"))
        let a = try h.active(); try await h.run(a)
        a.home.preferences.change { $0.renamed["discovery-cm-drama"] = "Awaiting acknowledgement" }
        h.beforeSend = { try await h.select("independent") }
        do { try await h.run(a); XCTFail("The old selection is retired") } catch { XCTAssertEqual((error as? HarborError)?.code, "account-changed") }
        XCTAssertTrue(a.home.hasPendingChanges)
        let independent = try h.active(); XCTAssertEqual(independent.home.preferences.layout.renamed["discovery-cm-drama"], "Independent")
        try await h.select("desktop-primary"); let reopened = try h.active(); try await h.run(reopened)
        XCTAssertEqual(h.packets.count, 1, "The next pull recognizes the uncertain accepted write")
        XCTAssertFalse(reopened.home.hasPendingChanges)
    }
    func testAMalformedSectionDoesNotPreventOtherProfilesAndSectionsFromHydrating() async throws {
        let h = try OwnedHouseholdLayouts(); defer { h.close() }
        h.set("desktop-primary", "nav", .array([])); h.set("linked-other", "nav", h.navigation("Still available"))
        h.set("independent", "home", h.page("Private remains available"))
        let active = try h.active()
        do { try await h.run(active); XCTFail("One section is malformed") } catch { XCTAssertEqual((error as? HarborError)?.code, "navigation-sync-value") }
        XCTAssertEqual(active.navigation.preferences.value.renamed["anime"], "Still available")
        try await h.select("independent"); let independent = try h.active()
        XCTAssertEqual(independent.home.preferences.layout.renamed["discovery-cm-drama"], "Private remains available")
        XCTAssertTrue(h.packets.isEmpty)
    }
    func testAllFourSectionsUseTheOriginStampWhenASecondLinkedProfileBecomesActive() async throws {
        let h = try OwnedHouseholdLayouts(); defer { h.close() }
        for profile in ["desktop-primary", "linked-other"] {
            h.set(profile, "nav", h.navigation("Original")); h.set(profile, "home", h.page("Original"))
            h.set(profile, "anime", .object(["renamed": .object(["continueWatching": .string("Original")])]))
            h.set(profile, "services", .object(["netflix": .bool(true)]))
        }
        let a = try h.active(); try await h.run(a)
        a.navigation.preferences.change { $0.renamed["anime"] = "My nav" }
        a.home.preferences.change { $0.renamed["discovery-cm-drama"] = "My home" }
        a.anime.preferences.change { $0.renamed["continueWatching"] = "My anime" }
        XCTAssertTrue(a.services.preferences.setEnabled(false, for: "netflix"))
        try await h.select("linked-other"); let b = try h.active(); try await h.run(b)
        let keys = Set(h.packets.compactMap { $0["writes"].array.first?["key"].string })
        XCTAssertEqual(keys, Set(["services", "nav", "home", "anime"].map { "desktop-primary:" + $0 }))
        XCTAssertEqual(b.navigation.preferences.value.renamed["anime"], "My nav")
        XCTAssertEqual(b.home.preferences.layout.renamed["discovery-cm-drama"], "My home")
        XCTAssertEqual(b.anime.preferences.layout.renamed["continueWatching"], "My anime")
        XCTAssertFalse(b.services.preferences.isEnabled("netflix")); XCTAssertFalse(h.engine.hasPendingChanges)
    }
}

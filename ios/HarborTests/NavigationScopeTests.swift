import XCTest
@testable import Harbor

@MainActor private final class MemoryNavigationPersistence: NavigationLayoutPersistence {
    var values: [String: NativeNavigationLayout] = [:]
    var failRead = false, failWrite = false
    var writes = 0
    func read(_ key: String) throws -> NativeNavigationLayout? {
        if failRead { throw HarborError(code: "test-storage-unavailable") }
        return values[key]
    }
    func write(_ value: NativeNavigationLayout, key: String) throws {
        if failWrite { throw HarborError(code: "test-storage-unavailable") }
        writes += 1; values[key] = value
    }
}

@MainActor final class NavigationScopeTests: XCTestCase {
    private func isolated(_ body: (UserDefaults, MemoryNavigationPersistence) throws -> Void) throws {
        let suite = "HarborNavigationTests-" + UUID().uuidString, defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        try body(defaults, MemoryNavigationPersistence())
    }
    func testLegacyMigrationWaitsForTheKnownOwnerAndDoesNotLeakToAnotherAccount() throws {
        try isolated { defaults, memory in
            defaults.set(["anime", "home"], forKey: "iphone.nav.order")
            defaults.set(["sports"], forKey: "iphone.nav.hidden")
            defaults.set(["anime": "Mis series"], forKey: "iphone.nav.names")
            let store = ScopedNavigationPreferences(storage: defaults, persistence: memory)
            store.change { $0.renamed["home"] = "Must not save" }
            XCTAssertFalse(store.ready); XCTAssertNil(store.scope); XCTAssertEqual(memory.writes, 0)
            store.bind(.local(owner: "alice"))
            XCTAssertTrue(store.ready); XCTAssertEqual(store.value.renamed["anime"], "Mis series")
            let alice = store.value
            store.bind(.local(owner: "bob"))
            XCTAssertTrue(store.value.renamed.isEmpty); XCTAssertTrue(store.value.order.isEmpty)
            store.change { $0.renamed["music"] = "Bob music" }
            store.bind(.local(owner: "alice")); XCTAssertEqual(store.value, alice)
            store.bind(.local(owner: "bob")); XCTAssertEqual(store.value.renamed, ["music": "Bob music"])
            XCTAssertEqual(defaults.stringArray(forKey: "iphone.nav.order"), ["anime", "home"], "The original upgrade backup is kept")
            XCTAssertEqual(defaults.dictionary(forKey: "iphone.nav.names") as? [String: String], ["anime": "Mis series"])
        }
    }
    func testStorageFailuresNeverTurnAnUnreadStoreIntoEmptySettings() throws {
        try isolated { defaults, memory in
            defaults.set(["anime"], forKey: "iphone.nav.order")
            memory.failRead = true
            let store = ScopedNavigationPreferences(storage: defaults, persistence: memory)
            store.bind(.local(owner: "alice"))
            XCTAssertFalse(store.ready); XCTAssertNotNil(store.error); XCTAssertEqual(memory.writes, 0)
            XCTAssertNil(defaults.object(forKey: "iphone.nav.migration.owner.v1"))
            memory.failRead = false; store.reload()
            XCTAssertTrue(store.ready); let saved = store.value
            memory.failWrite = true; store.change { $0.renamed["anime"] = "Unsaved" }
            XCTAssertEqual(store.value, saved); XCTAssertNotNil(store.error)
            XCTAssertEqual(memory.values[NavigationScope.local(owner: "alice").key], saved)
        }
    }
    func testHarborAccountsAreSeparateAndLinkedProfilesShareOnlyTheirOwnAccount() throws {
        try isolated { defaults, memory in
            let store = ScopedNavigationPreferences(storage: defaults, persistence: memory)
            store.bind(.local(owner: "alice")); store.change { $0.renamed["home"] = "Local home" }
            let one = NavigationScope.harbor(owner: "alice", account: "one", profile: "primary", linked: true)
            store.bind(one); store.change { $0.renamed["anime"] = "Account one" }
            store.bind(.harbor(owner: "alice", account: "two", profile: "primary", linked: true))
            XCTAssertNil(store.value.renamed["anime"]); XCTAssertEqual(store.value.renamed["home"], "Local home")
            store.bind(.harbor(owner: "alice", account: "one", profile: "secondary", linked: true))
            XCTAssertEqual(store.value.renamed["anime"], "Account one")
            store.bind(.harbor(owner: "alice", account: "one", profile: "secondary", linked: false))
            XCTAssertNil(store.value.renamed["anime"])
            store.bind(one); XCTAssertEqual(store.value.renamed["anime"], "Account one")
            XCTAssertNotEqual(NavigationScope.local(owner: "a|b").key, NavigationScope.local(owner: "a").key)
        }
    }
    func testRemoteApplyCannotCrossTheActiveScopeAndDoesNotEnqueueAnEcho() throws {
        try isolated { defaults, memory in
            let store = ScopedNavigationPreferences(storage: defaults, persistence: memory)
            let alice = NavigationScope.local(owner: "alice"), bob = NavigationScope.local(owner: "bob")
            store.bind(alice)
            var notifications = 0; store.onEdit = { _ in notifications += 1 }
            let remote = NativeNavigationLayout(order: ["anime"], hidden: ["sports"], renamed: ["anime": "Remote"])
            try store.apply(remote, to: alice)
            XCTAssertEqual(store.value, remote); XCTAssertEqual(notifications, 0)
            store.change { $0.renamed["anime"] = "User edit" }; XCTAssertEqual(notifications, 1)
            store.bind(bob); let before = memory.writes
            XCTAssertThrowsError(try store.apply(remote, to: alice))
            store.change(in: alice) { $0.renamed["anime"] = "Late text-field submit" }
            XCTAssertTrue(store.value.renamed.isEmpty); XCTAssertEqual(memory.writes, before)
        }
    }
    func testDesktopNavigationRetainsGamesPluginsAndFutureFieldsWhenIOSChanges() throws {
        let raw = try JSONDecoder().decode(JSONValue.self, from: Data(#"{"order":["home","games","anime","plugins","music"],"hidden":["games","anime"],"renamed":{"games":"My PC","anime":"Japan","plugins":"Sources"},"future":{"style":"compact","version":7}}"#.utf8))
        let desktop = try DesktopNavigationLayout(raw), known: Set<String> = ["home", "anime", "music"]
        let local = NativeNavigationLayout(order: ["music", "search", "home", "anime"], hidden: ["music", "search"], renamed: ["anime": "Anime phone", "search": "Search phone"])
        let updated = try desktop.applying(local, knownIDs: known, defaultOrder: ["home", "anime", "music"])
        XCTAssertEqual(updated.order, ["music", "games", "home", "plugins", "anime"])
        XCTAssertEqual(updated.hidden, ["games", "music"])
        XCTAssertEqual(updated.renamed, ["games": "My PC", "plugins": "Sources", "anime": "Anime phone"])
        XCTAssertEqual(updated.raw["future"], raw["future"])
        let applied = desktop.native(knownIDs: known, preserving: local, defaultOrder: ["home", "anime", "search", "music"])
        XCTAssertEqual(applied.order, ["home", "search", "anime", "music"])
        XCTAssertEqual(applied.hidden, ["search", "anime"])
        XCTAssertEqual(applied.renamed["search"], "Search phone"); XCTAssertEqual(applied.renamed["anime"], "Japan")
        XCTAssertFalse(applied.order.contains("games")); XCTAssertNil(applied.renamed["plugins"])
    }
    func testMalformedOrOversizedDesktopValuesAreRejectedInsteadOfAppliedAsDefaults() throws {
        for text in [#"{"order":{}}"#, #"{"hidden":[42]}"#, #"{"renamed":{"anime":false}}"#, "null"] {
            let value = try JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))
            XCTAssertThrowsError(try DesktopNavigationLayout(value))
        }
        XCTAssertThrowsError(try DesktopNavigationLayout(.object(["future": .string(String(repeating: "x", count: 100_000))])))
    }
    func testServerRevisionsAndExactDocumentKeysControlTheSyncProtocol() throws {
        let value = JSONValue.object(["order": .array([.string("anime")])])
        let document = HarborLayoutDocument(key: "profile-id:nav", rev: 41, value: value)
        let packet = try document.write(value)
        XCTAssertEqual(packet["writes"].array.count, 1)
        XCTAssertEqual(packet["writes"].array.first?["key"].string, "profile-id:nav")
        XCTAssertEqual(packet["writes"].array.first?["baseRev"], .integer(41))
        if case .accepted(let revision) = try document.result(.object(["results": .array([.object(["ok": .bool(true), "rev": .integer(42)])])])) { XCTAssertEqual(revision, 42) }
        else { XCTFail("The server accepted this revision") }
        let staleResponse: JSONValue = .object(["results": .array([.object(["ok": .bool(true), "rev": .integer(41)])])])
        XCTAssertThrowsError(try document.result(staleResponse))
        XCTAssertThrowsError(try HarborLayoutDocument.revision(.number(41.5)))
        XCTAssertThrowsError(try HarborLayoutDocument.revision(.integer(-1)))
        XCTAssertThrowsError(try HarborLayoutDocument.revision(.integer(HarborLayoutDocument.maximumRevision + 1)))
    }
    func testDuplicateStateDocumentsAndCrossProfileConflictsAreRejected() throws {
        let doc: JSONValue = .object(["key": .string("one:nav"), "rev": .integer(12), "value": .object([:])])
        XCTAssertThrowsError(try HarborLayoutDocument.state(.object(["rev": .integer(12), "docs": .array([doc, doc])]), key: "one:nav"))
        let current = HarborLayoutDocument(key: "two:nav", rev: 10, value: .object([:]))
        let crossProfileResponse: JSONValue = .object(["results": .array([.object(["ok": .bool(false), "current": doc])])])
        XCTAssertThrowsError(try current.result(crossProfileResponse))
        XCTAssertNil(try HarborLayoutDocument.state(.object(["rev": .integer(12), "docs": .array([doc])]), key: "missing:nav"))
    }
}

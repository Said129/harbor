import XCTest
@testable import Harbor

@MainActor private final class SourcePageJournal: PageSyncPersistence {
    var values: [String: PageSyncRecord] = [:]
    var fail = false
    func read(_ key: String) throws -> PageSyncRecord? { values[key] }
    func write(_ value: PageSyncRecord, key: String) throws {
        if fail { throw HarborError(code: "owned-source-journal") }
        values[key] = value
    }
}

@MainActor final class CustomSourceStorageTests: XCTestCase {
    private var source: JSONValue {
        .object(["id": .string("owned-source"), "title": .string("Owned folders"), "future": .string("keep source field"),
            "folders": .array([.object(["id": .string("owned-folder"), "title": .string("Owned titles"), "tileShape": .string("POSTER"),
                "catalogSources": .array([.object(["addonId": .string("owned.addon"), "type": .string("movie"), "catalogId": .string("owned")])])])])])
    }
    private var profile: JSONValue { .object(["syncId": .string("one"), "settingsLinked": .bool(false)]) }
    private func text(_ value: JSONValue) throws -> String { String(decoding: try JSONEncoder().encode(value), as: UTF8.self) }
    private func state(_ value: JSONValue?, rev: Int64) -> JSONValue {
        .object(["rev": .integer(rev), "docs": .array(value.map { [.object(["key": .string("one:home"), "rev": .integer(rev), "value": $0])] } ?? [])])
    }
    private func accepted(_ rev: Int64) -> JSONValue { .object(["results": .array([.object(["ok": .bool(true), "rev": .integer(rev)])])]) }
    private func isolated(_ body: @MainActor (String, PageCustomization, HarborPageSync, SourcePageJournal) async throws -> Void) async throws {
        let owner = "owned-source-" + UUID().uuidString, preferences = PageCustomization(owner: owner, page: "home"), memory = SourcePageJournal()
        let engine = HarborPageSync(preferences: preferences, persistence: memory)
        defer {
            engine.unbind(); try? KeychainStore().remove("page-layout-" + EBookShelf.hash(owner + "|home"))
            for linked in [false, true] {
                let scope = NavigationScope.harbor(owner: owner, account: "A", profile: "one", linked: linked)
                try? KeychainStore().remove("page-layout-scope-" + EBookShelf.hash(scope.key + "|home"))
            }
        }
        try await body(owner, preferences, engine, memory)
    }
    func testLocalImportsReopenAndExplicitPrivateInheritanceKeepsSourcesWithoutChangingTheSharedRecord() throws {
        let owner = "owned-local-source-" + UUID().uuidString, privateOwner = owner + "-private"
        defer { for value in [owner, privateOwner] { try? KeychainStore().remove("page-layout-" + EBookShelf.hash(value + "|home")) } }
        let shared = PageCustomization(owner: owner, page: "home")
        try shared.importSources(text(source), expected: shared.scope)
        XCTAssertEqual(PageCustomization(owner: owner, page: "home").sourceRows.first?.raw, source)
        let independent = PageCustomization(owner: privateOwner, page: "home", inheritedOwner: owner)
        XCTAssertEqual(independent.sourceRows.first?.raw, source)
        try independent.editSourceImages(rowID: "owned-source", folderID: "owned-folder", cover: "https://owned.invalid/private.png", focus: "", expected: independent.scope)
        XCTAssertNil(shared.sourceRows.first?.folders.first?.cover)
        XCTAssertEqual(independent.sourceRows.first?.folders.first?.cover, "https://owned.invalid/private.png")
        let raw = independent.wireProjection
        XCTAssertThrowsError(try independent.importSources("{bad json", expected: independent.scope)); XCTAssertEqual(independent.wireProjection, raw)
        independent.reset(); XCTAssertTrue(independent.sourceRows.isEmpty); XCTAssertEqual(shared.sourceRows.count, 1)
    }
    func testSourceOnlyEditAfterAMissingServerDocumentSurvivesAnInterruptedQueueAndReopening() async throws {
        try await isolated { owner, preferences, engine, memory in
            try await engine.synchronize(state: self.state(nil, rev: 0), account: "A", profile: self.profile) { _ in XCTFail("No default upload"); return .null }
            let before = preferences.layout; memory.fail = true
            try preferences.importSources(self.text(self.source), expected: preferences.scope)
            XCTAssertEqual(preferences.layout, before); XCTAssertNotNil(engine.error); memory.fail = false; engine.unbind()
            let reopened = PageCustomization(owner: owner, page: "home"), resumed = HarborPageSync(preferences: reopened, persistence: memory)
            defer { resumed.unbind() }
            var sent: JSONValue?
            try await resumed.synchronize(state: self.state(nil, rev: 0), account: "A", profile: self.profile) { body in sent = body; return self.accepted(1) }
            XCTAssertEqual(sent?["writes"].array.first?["value"]["customSources"], .array([self.source]))
            XCTAssertEqual(reopened.sourceRows.first?.raw, self.source); XCTAssertFalse(resumed.hasPendingChanges)
        }
    }
    func testAnOfflineRawEditBeforeFirstPullPublishesToAnAbsentDocumentAndCanBeRecoveredWhenTheRemoteWins() async throws {
        for remoteWins in [false, true] {
            try await isolated { owner, preferences, engine, _ in
                let scope = NavigationScope.harbor(owner: owner, account: "A", profile: "one", linked: false)
                preferences.bind(scope); try preferences.importSources(self.text(self.source), expected: scope)
                let remote: JSONValue? = remoteWins ? .object(["customSources": .array([]), "future": .string("remote authority")]) : nil
                var writes: [JSONValue] = []
                try await engine.synchronize(state: self.state(remote, rev: remoteWins ? 5 : 0), account: "A", profile: self.profile) { body in writes.append(body); return self.accepted(1) }
                if remoteWins {
                    XCTAssertTrue(writes.isEmpty); XCTAssertTrue(preferences.sourceRows.isEmpty); XCTAssertTrue(engine.hasParkedVersion)
                    engine.restoreMyVersion()
                    try await engine.synchronize(state: self.state(remote, rev: 5), account: "A", profile: self.profile) { body in writes.append(body); return self.accepted(6) }
                }
                XCTAssertEqual(writes.count, 1); XCTAssertEqual(writes.first?["writes"].array.first?["value"]["customSources"], .array([self.source]))
                XCTAssertEqual(preferences.sourceRows.first?.id, "owned-source"); XCTAssertFalse(engine.hasPendingChanges)
            }
        }
    }
    func testRawImageEditDuringAnAcknowledgementKeepsItsNewQueueAndTheWholeSourceCanBeRestoredAfterAConflict() async throws {
        try await isolated { _, preferences, engine, _ in
            let initial: JSONValue = .object(["customSources": .array([self.source]), "future": .string("original")])
            try await engine.synchronize(state: self.state(initial, rev: 1), account: "A", profile: self.profile) { _ in XCTFail("No echo"); return .null }
            try preferences.editSourceImages(rowID: "owned-source", folderID: "owned-folder", cover: "https://owned.invalid/first.png", focus: "", expected: preferences.scope)
            var first: JSONValue?
            try await engine.synchronize(state: self.state(initial, rev: 1), account: "A", profile: self.profile) { body in
                first = body["writes"].array.first?["value"]
                try preferences.editSourceImages(rowID: "owned-source", folderID: "owned-folder", cover: "https://owned.invalid/first.png", focus: "https://owned.invalid/latest.gif", expected: preferences.scope)
                return self.accepted(2)
            }
            XCTAssertTrue(engine.hasPendingChanges)
            var latest: JSONValue?
            try await engine.synchronize(state: self.state(first, rev: 2), account: "A", profile: self.profile) { body in latest = body["writes"].array.first?["value"]; return self.accepted(3) }
            XCTAssertEqual(latest?["customSources"].array.first?["folders"].array.first?["focusGifUrl"].string, "https://owned.invalid/latest.gif")
            try preferences.editSourceImages(rowID: "owned-source", folderID: "owned-folder", cover: "https://owned.invalid/conflict.png", focus: "", expected: preferences.scope)
            let winner: JSONValue = .object(["customSources": .array([]), "future": .string("winner")])
            try await engine.synchronize(state: self.state(winner, rev: 5), account: "A", profile: self.profile) { _ in XCTFail("Newer remote wins before upload"); return .null }
            XCTAssertTrue(preferences.sourceRows.isEmpty); XCTAssertTrue(engine.hasParkedVersion); engine.restoreMyVersion()
            try await engine.synchronize(state: self.state(winner, rev: 5), account: "A", profile: self.profile) { body in
                XCTAssertEqual(body["writes"].array.first?["value"]["customSources"].array.first?["future"].string, "keep source field")
                return self.accepted(6)
            }
            XCTAssertEqual(preferences.sourceRows.first?.folders.first?.cover, "https://owned.invalid/conflict.png")
        }
    }
    func testFirstSignInParksGuestSourceRowsWhenTheAccountWinsAndAnAbsentAccountWaitsForAnExplicitEdit() async throws {
        for remoteWins in [false, true] {
            try await isolated { owner, preferences, engine, _ in
                let typedDefaults = preferences.layout
                try preferences.importSources(self.text(self.source), expected: preferences.scope)
                XCTAssertEqual(preferences.layout, typedDefaults, "Guest source imports do not change typed preferences")
                let remote: JSONValue? = remoteWins ? .object(["customSources": .array([]), "future": .string("account authority")]) : nil
                try await engine.synchronize(state: self.state(remote, rev: remoteWins ? 7 : 0), account: "A", profile: self.profile) { _ in
                    XCTFail("The first pull must adopt the account or hold a guest snapshot without uploading it"); return .null
                }
                XCTAssertFalse(engine.hasPendingChanges)
                XCTAssertEqual(engine.hasParkedVersion, remoteWins)
                XCTAssertEqual(PageCustomization(owner: owner, page: "home").sourceRows.first?.raw, self.source, "The separate guest record remains intact")
                if remoteWins {
                    XCTAssertTrue(preferences.sourceRows.isEmpty); engine.restoreMyVersion()
                } else {
                    XCTAssertEqual(preferences.sourceRows.first?.raw, self.source)
                    try preferences.editSourceImages(rowID: "owned-source", folderID: "owned-folder", cover: "https://owned.invalid/after-login.png", focus: "", expected: preferences.scope)
                }
                var writes: [JSONValue] = []
                try await engine.synchronize(state: self.state(remote, rev: remoteWins ? 7 : 0), account: "A", profile: self.profile) { body in
                    writes.append(body); return self.accepted(remoteWins ? 8 : 1)
                }
                XCTAssertEqual(writes.count, 1)
                let sent = try XCTUnwrap(writes.first?["writes"].array.first)
                XCTAssertEqual(sent["baseRev"], .integer(remoteWins ? 7 : 0))
                XCTAssertEqual(sent["value"]["customSources"].array.first?["future"].string, "keep source field")
                XCTAssertEqual(preferences.sourceRows.first?.id, "owned-source"); XCTAssertFalse(engine.hasPendingChanges)
            }
        }
    }
    func testLinkedProfileSourceEditsOnlyUploadTheEditingProfilesSectionAndKeepTheLatestSharedUnknownFields() async throws {
        let h = try OwnedHouseholdLayouts(); defer { h.close() }
        h.set("desktop-primary", "home", .object(["customSources": .array([source]), "future": .string("earlier")]))
        h.set("linked-other", "home", .object(["customSources": .array([source]), "future": .string("latest")]), rev: 11)
        let a = try h.active(); try await h.run(a)
        try a.home.preferences.editSourceImages(rowID: "owned-source", folderID: "owned-folder", cover: "https://owned.invalid/linked.png", focus: "", expected: a.home.preferences.scope)
        try await h.select("linked-other"); let b = try h.active(); try await h.run(b)
        XCTAssertEqual(h.packets.compactMap { $0["writes"].array.first?["key"].string }, ["desktop-primary:home"])
        XCTAssertEqual(h.packets.first?["writes"].array.first?["value"]["future"].string, "latest")
        XCTAssertEqual(b.home.preferences.sourceRows.first?.folders.first?.cover, "https://owned.invalid/linked.png")
    }
    func testAnImportOpenedForAnOlderScopeAndAnOversizedPayloadCannotChangeTheCurrentSavedSourceRows() throws {
        let owner = "owned-source-scope-" + UUID().uuidString, preferences = PageCustomization(owner: owner, page: "home")
        let before = preferences.scope
        let next = NavigationScope.harbor(owner: owner, account: "A", profile: "one", linked: false)
        defer {
            try? KeychainStore().remove("page-layout-" + EBookShelf.hash(owner + "|home"))
            try? KeychainStore().remove("page-layout-scope-" + EBookShelf.hash(next.key + "|home"))
        }
        preferences.bind(next)
        XCTAssertThrowsError(try preferences.importSources(text(source), expected: before))
        XCTAssertTrue(preferences.sourceRows.isEmpty)
        try preferences.importSources(text(source), expected: next); let saved = preferences.wireProjection
        XCTAssertThrowsError(try preferences.importSources(String(repeating: " ", count: 96 * 1_024 + 1), expected: next))
        XCTAssertEqual(preferences.wireProjection, saved)
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("owned-source-" + UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: file) }
        let contents = try text(source)
        try Data(contents.utf8).write(to: file)
        XCTAssertEqual(try CustomSourceDocumentFile.read(file), contents)
        try Data(repeating: 32, count: 96 * 1_024 + 1).write(to: file)
        XCTAssertThrowsError(try CustomSourceDocumentFile.read(file)); XCTAssertEqual(preferences.wireProjection, saved)
    }
}

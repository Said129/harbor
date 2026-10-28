import XCTest
@testable import Harbor

@MainActor private final class HomeListPageMemory: PageSyncPersistence {
    var values: [String: PageSyncRecord] = [:]
    func read(_ key: String) throws -> PageSyncRecord? { values[key] }
    func write(_ value: PageSyncRecord, key: String) throws { values[key] = value }
}

@MainActor final class CustomListHomeTests: XCTestCase {
    private func fixture() throws -> JSONValue {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "home-lists-reference", withExtension: "json", subdirectory: "Fixtures"))
        let value = try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: url))
        XCTAssertEqual(value["reference"].string, "0834340cec5531650bfe78cd628628702e636987")
        XCTAssertEqual(value["actual_original_typescript_executed"], .bool(true))
        XCTAssertEqual(value["provider_network_requests"].integer, 0)
        XCTAssertEqual(value["executed_module_hashes"].objectValue.count, 2)
        return value
    }
    private func cleanup(_ owner: String) {
        try? KeychainStore().remove("page-layout-" + EBookShelf.hash(owner + "|home"))
        for account in ["A", "B"] {
            let scope = NavigationScope.harbor(owner: owner, account: account, profile: "one", linked: false)
            try? KeychainStore().remove("page-layout-scope-" + EBookShelf.hash(scope.key + "|home"))
        }
    }
    private func lists(_ value: JSONValue) -> [CustomList] { value.array.compactMap(CustomList.parse) }
    private func projection(_ rows: [CustomList]) -> JSONValue {
        .array(rows.map { list in
            .object(["key": .string("list-" + list.id), "name": .string(list.name), "type": .string("movie"),
                "page": .integer(1), "hasMore": .bool(false), "noDedup": .bool(true),
                "metas": .array(list.items.map { item in
                    var fields: [String: JSONValue] = ["id": .string(item.id), "type": .string(item.type), "name": .string(item.name)]
                    fields["poster"] = item.poster.map(JSONValue.string); return .object(fields)
                })])
        })
    }
    func testActualDesktopSelectorsPreserveSelectionOrderEmptyListsAndLiteralNames() throws {
        let fixture = try fixture(); XCTAssertEqual(fixture["projections"].array.count, 6)
        for row in fixture["projections"].array {
            let lists = lists(row["lists"]), ids = row["selected_ids"].array.compactMap(\.string)
            let selected = CustomListHomeRows.selected(lists, ids: ids)
            XCTAssertEqual(projection(selected), row["expected_rows"])
            XCTAssertEqual(JSONValue.array(CustomListHomeRows.available(lists, ids: ids).map {
                .object(["id": .string($0.id), "name": .string($0.name)])
            }), row["expected_available"])
        }
        let list = try XCTUnwrap(lists(fixture["projections"].array[0]["lists"]).first)
        let rail = PageRail.list(list)
        XCTAssertEqual(rail.id, "list-alpha"); XCTAssertEqual(rail.title, "Own titles")
        XCTAssertEqual(rail.metas.first?.addonOrigin?.id, "own")
        XCTAssertEqual(rail.metas.first?.videos?.first?.id, "own:show:5:23", "Display customization must preserve the provider's actual episode ID")
    }
    func testActualDesktopAddRemoveAndRowOptionsPersistAndResetWithoutDeletingLists() throws {
        let owner = "owned-home-actions-" + UUID().uuidString; defer { cleanup(owner) }
        let preferences = PageCustomization(owner: owner, page: "home"), fixture = try fixture()
        let sourceLists = lists(fixture["projections"].array[0]["lists"])
        XCTAssertEqual(fixture["action_cases"].array.count, 13)
        for row in fixture["action_cases"].array {
            preferences.setEditingRails(CustomListHomeRows.selected(sourceLists, ids: preferences.listRowIDs).map(PageRail.list))
            let args = row["args"].array, action = try XCTUnwrap(row["action"].string)
            switch action {
            case "addListRow": try preferences.addListRow(try XCTUnwrap(args[0].string), expected: preferences.scope)
            case "removeListRow": try preferences.removeListRow(try XCTUnwrap(args[0].string), expected: preferences.scope)
            case "renameRow":
                let rail = try XCTUnwrap(sourceLists.map(PageRail.list).first { $0.id == args[0].string })
                preferences.rename(rail, to: try XCTUnwrap(args[1].string))
            case "toggleRowHidden":
                let key = try XCTUnwrap(args[0].string); preferences.change { if !$0.hidden.insert(key).inserted { $0.hidden.remove(key) } }
            case "toggleRowNumerals":
                let key = try XCTUnwrap(args[0].string); preferences.change { if !$0.numerals.insert(key).inserted { $0.numerals.remove(key) } }
            case "toggleHeroSource":
                let key = try XCTUnwrap(args[0].string); preferences.change { $0.heroSource = $0.heroSource == key ? nil : key }
            case "togglePlayButtonSquare": preferences.change { $0.playButtonSquare.toggle() }
            case "toggleSecondaryMoreInfo": preferences.change { $0.secondaryMoreInfo.toggle() }
            case "toggleCwTop": preferences.change { $0.cwTop.toggle() }
            case "resetHomeRows": preferences.reset()
            default: XCTFail("Unmapped original action: " + action)
            }
            var current = try XCTUnwrap(preferences.wireProjection).objectValue
            current["customSources"] = .array(preferences.sourceRows.map(\.raw))
            XCTAssertEqual(JSONValue.object(current), row["expected"], action)
            let reopened = PageCustomization(owner: owner, page: "home")
            XCTAssertTrue(reopened.ready); XCTAssertEqual(reopened.listRowIDs, preferences.listRowIDs)
            XCTAssertEqual(reopened.layout, preferences.layout)
        }
        XCTAssertEqual(sourceLists.count, 4); XCTAssertEqual(sourceLists.first?.items.count, 1)
        for row in fixture["layout_cases"].array {
            let listByID = Dictionary(uniqueKeysWithValues: sourceLists.map { ("list-" + $0.id, $0) })
            let rails = row["rows"].array.compactMap { listByID[$0["key"].string ?? ""] }.map(PageRail.list)
            let map = DesktopPageRowMap(page: "home", rails: rails)
            let codec = try DesktopPageLayout(page: "home", raw: row["custom"])
            try preferences.apply(codec.native(preserving: PageLayout(), mapping: map), to: preferences.scope, projection: codec.raw)
            let ordered = preferences.ordered(rails, includeHidden: row["include_hidden"] == .bool(true))
            XCTAssertEqual(ordered.map(\.id), row["expected"].array.compactMap { $0["key"].string })
            XCTAssertEqual(ordered.map { preferences.title($0, among: rails) }, row["expected"].array.compactMap { $0["name"].string })
        }
    }
    func testRawListReferencesRetainMissingRowsAndRejectStaleOrMalformedEditsWithoutReplacingSavedData() throws {
        let shared = "owned-home-shared-" + UUID().uuidString, owner = shared + "-child"
        defer { cleanup(shared); cleanup(owner) }
        let parent = PageCustomization(owner: shared, page: "home")
        let raw: JSONValue = .object(["listRows": .array([.string("alpha"), .string("missing")]),
            "order": .array([.string("list-missing"), .string("list-alpha")]),
            "hidden": .array([.string("list-missing")]), "renamed": .object(["list-missing": .string("Keep my name")]),
            "numerals": .array([.string("list-missing")]), "heroSource": .string("list-missing"), "future": .integer(42)])
        let codec = try DesktopPageLayout(page: "home", raw: raw)
        try parent.apply(codec.native(preserving: PageLayout(), mapping: .init(page: "home")), to: parent.scope, projection: raw)
        let child = PageCustomization(owner: owner, page: "home", inheritedOwner: shared)
        XCTAssertEqual(child.listRowIDs, ["alpha", "missing"])
        XCTAssertEqual(child.layout.heroSource, "list-missing"); XCTAssertTrue(child.layout.hidden.contains("list-missing"))
        XCTAssertEqual(child.layout.renamed["list-missing"], "Keep my name")
        XCTAssertNil(try LayoutEditStorage.object("page-layout-" + EBookShelf.hash(owner + "|home"), as: PageLayout.self))
        try child.addListRow("beta", expected: child.scope)
        try parent.removeListRow("alpha", expected: parent.scope)
        XCTAssertEqual(child.listRowIDs, ["alpha", "missing", "beta"])
        let old = child.wireProjection, local = child.scope
        XCTAssertThrowsError(try child.addListRow("", expected: local))
        XCTAssertThrowsError(try child.addListRow(String(repeating: "a", count: 2_048), expected: local))
        XCTAssertEqual(child.wireProjection, old)
        child.bind(.harbor(owner: owner, account: "A", profile: "one", linked: false))
        XCTAssertThrowsError(try child.removeListRow("alpha", expected: local))
        XCTAssertEqual(child.wireProjection, old)
        let list = CustomList(raw: .object(["id": .string("missing"), "name": .string("Now available"), "items": .array([])]))
        child.setEditingRails([.list(list)])
        XCTAssertEqual(child.layout.renamed["list-missing"], "Keep my name")
        XCTAssertEqual(child.wireProjection?["future"], .integer(42))
        child.reset(); XCTAssertTrue(child.listRowIDs.isEmpty); XCTAssertTrue(child.sourceRows.isEmpty)
        XCTAssertEqual(child.wireProjection?["future"], .integer(42), "Retain forward compatible fields while resetting supported options")
        XCTAssertEqual(parent.listRowIDs, ["missing"])
    }
    func testAddingOnlyAListReferenceQueuesTheRawHarborLayoutAndSurvivesAnOfflineReopen() async throws {
        let owner = "owned-home-sync-" + UUID().uuidString; defer { cleanup(owner) }
        let preferences = PageCustomization(owner: owner, page: "home"), memory = HomeListPageMemory()
        let engine = HarborPageSync(preferences: preferences, persistence: memory)
        let profile: JSONValue = .object(["syncId": .string("one"), "settingsLinked": .bool(false)])
        let raw: JSONValue = .object(["listRows": .array([.string("alpha")]), "future": .integer(7)])
        let state: JSONValue = .object(["rev": .integer(1), "docs": .array([.object(["key": .string("one:home"), "rev": .integer(1), "value": raw])])])
        try await engine.synchronize(state: state, account: "A", profile: profile) { _ in XCTFail("No default upload"); return .null }
        let before = preferences.layout
        try preferences.addListRow("beta", expected: preferences.scope)
        XCTAssertEqual(preferences.layout, before); XCTAssertTrue(engine.hasPendingChanges)
        engine.unbind()
        let reopened = PageCustomization(owner: owner, page: "home"), resumed = HarborPageSync(preferences: reopened, persistence: memory)
        defer { resumed.unbind() }
        var requests = 0
        try await resumed.synchronize(state: state, account: "A", profile: profile) { request in
            requests += 1
            let write = try XCTUnwrap(request["writes"].array.first)
            XCTAssertEqual(write["key"], .string("one:home")); XCTAssertEqual(write["baseRev"], .integer(1))
            XCTAssertEqual(write["value"]["listRows"], .array([.string("alpha"), .string("beta")]))
            XCTAssertEqual(write["value"]["future"], .integer(7))
            return .object(["results": .array([.object(["ok": .bool(true), "rev": .integer(2)])])])
        }
        XCTAssertEqual(requests, 1); XCTAssertFalse(resumed.hasPendingChanges)
        XCTAssertEqual(reopened.listRowIDs, ["alpha", "beta"])
    }
    func testMangaCoverSelectionUsesOnlyMatchingOwnedBooksAndConfiguredSources() async throws {
        let local = MangaBook(id: "local:owned", title: "Own Manga", format: "pdf")
        let item = CustomListItem(raw: CustomListItem.input(local))
        XCTAssertEqual(CustomListMangaArtworkSelection.saved(item, books: [local], server: nil, plugins: [])?.id, local.id)
        XCTAssertNil(CustomListMangaArtworkSelection.saved(item, books: [], server: nil, plugins: []), "A linked list never grants access to another profile's PDF")
        var wrong = local; wrong.title = "Other book"
        XCTAssertNil(CustomListMangaArtworkSelection.saved(item, books: [wrong], server: nil, plugins: []))
        var remote = local; remote.server = "server-A"; remote.remoteID = "19"
        XCTAssertNil(CustomListMangaArtworkSelection.saved(item, books: [remote], server: "server-B", plugins: []))
        XCTAssertEqual(CustomListMangaArtworkSelection.saved(item, books: [remote], server: "server-A", plugins: [])?.remoteID, "19")
        var plugin = local; plugin.pluginID = "configured-plugin"
        XCTAssertNil(CustomListMangaArtworkSelection.saved(item, books: [plugin], server: nil, plugins: []))
        XCTAssertNotNil(CustomListMangaArtworkSelection.saved(item, books: [plugin], server: nil, plugins: ["configured-plugin"]))
        var active = true
        let context = CustomListMangaArtworkContext(activation: "owned", owner: "owned", books: [local], client: nil, reading: nil, isCurrent: { active })
        let resolved = await context.resolve(item); XCTAssertEqual(resolved?.id, local.id)
        active = false
        let retired = await context.resolve(item); XCTAssertNil(retired); XCTAssertFalse(context.active)
    }
}

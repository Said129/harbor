import XCTest
@testable import Harbor

@MainActor final class AnimeContinuationLayoutTests: XCTestCase {
    func testTheContinuationRowUsesActualRoomMembershipAndNeverDuplicatesOrInventsEmptyHistory() {
        let airing = PageRail.discovery(.init(id: "anime-airing", title: "Airing Now", kind: "anime", path: "owned"))
        let movie = record("owned-movie", type: "movie"), provider = record("mal:1", type: "series")
        let tagged = record("owned-anime", type: "anime"), detected = record("tt4644488", type: "series")
        let finished = record("owned-no-progress", type: "anime", offset: 0)
        XCTAssertFalse(PageRail.addingContinuation(to: [airing], kind: "anime", records: [movie, finished], detectedAnime: [], presentationError: false).contains { $0.id == "continueWatching" })
        for item in [provider, tagged, detected] {
            let rows = PageRail.addingContinuation(to: [.continuing(kind: "anime"), airing], kind: "anime", records: [item], detectedAnime: [detected.id], presentationError: false)
            XCTAssertEqual(rows.map(\.id), ["continueWatching", "discovery-anime-airing"])
            XCTAssertEqual(rows.first?.kind, "anime"); XCTAssertTrue(rows.first?.metas.isEmpty == true)
        }
        let feedback = PageRail.addingContinuation(to: [airing], kind: "anime", records: [], detectedAnime: [], presentationError: true)
        XCTAssertEqual(feedback.first?.id, "continueWatching", "The ordinary library retry feedback must remain accessible")
    }

    func testNativeRowOrderingVisibilityRenamingAndMovementMatchTheExecutedDesktopOracle() throws {
        let previous = UserDefaults.standard.string(forKey: "uiLanguage")
        UserDefaults.standard.set("en", forKey: "uiLanguage")
        defer { if let previous { UserDefaults.standard.set(previous, forKey: "uiLanguage") } else { UserDefaults.standard.removeObject(forKey: "uiLanguage") } }
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "anime-continuation-reference", withExtension: "json", subdirectory: "Fixtures"))
        let reference = try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: url))
        XCTAssertEqual(reference["input_sha256"].string, "6d285ab82a36e2b1fee3763dd07652f6ef54cd44f5353b1fe554eb826ab7bd18")
        let rails = reference["rows"].array.map { row -> PageRail in
            if row["key"].string == "continueWatching" { return .continuing(kind: "anime") }
            return .discovery(.init(id: "anime-" + (row["key"].string ?? ""), title: row["name"].string ?? "", kind: "anime", path: "owned"))
        }
        let owner = "owned-continuation-oracle-" + UUID().uuidString, preferences = PageCustomization(owner: owner, page: "anime")
        defer { try? KeychainStore().remove("page-layout-" + EBookShelf.hash(owner + "|anime")) }
        let mapping = DesktopPageRowMap(page: "anime")
        XCTAssertEqual(reference["cases"].array.count, 6)
        for vector in reference["cases"].array {
            preferences.reset()
            let initial = try DesktopPageLayout(page: "anime", raw: vector["custom"]).native(preserving: preferences.layout, mapping: mapping)
            preferences.change { $0 = initial }; preferences.setEditingRails(rails)
            let action = vector["action"], row = rails.first { mapping.desktop($0.id) == action["key"].string }
            if let row {
                switch action["type"].string {
                case "move":
                    let order = preferences.ordered(rails, includeHidden: true)
                    let index = try XCTUnwrap(order.firstIndex { $0.id == row.id }), target = index + (action["delta"].integer ?? 0)
                    XCTAssertTrue(order.indices.contains(target)); preferences.move(row, toward: order[target])
                case "hide": preferences.change { if $0.hidden.contains(row.id) { $0.hidden.remove(row.id) } else { $0.hidden.insert(row.id) } }
                case "rename": preferences.rename(row, to: action["name"].string ?? "")
                default: XCTFail("Unknown original oracle action")
                }
            }
            for (key, includeHidden) in [("visible", false), ("editing", true)] {
                let actual = preferences.ordered(rails, includeHidden: includeHidden), expected = vector["expected"][key].array
                XCTAssertEqual(actual.compactMap { mapping.desktop($0.id) }, expected.compactMap { $0["key"].string })
                XCTAssertEqual(actual.map { preferences.title($0, among: rails) }, expected.compactMap { $0["name"].string })
            }
        }
    }

    func testContinuationCannotBecomeARankedPosterRailAndHomeKeepsItsSeparateContinueAtTopOption() throws {
        let owner = "owned-continuation-options-" + UUID().uuidString, preferences = PageCustomization(owner: owner, page: "anime")
        defer { try? KeychainStore().remove("page-layout-" + EBookShelf.hash(owner + "|anime")) }
        let row = PageRail.continuing(kind: "anime")
        preferences.change { $0.numerals.insert(row.id) }
        XCTAssertFalse(preferences.ranked(row)); XCTAssertFalse(row.supportsArtworkCustomization)
        XCTAssertTrue(row.metas.isEmpty); XCTAssertFalse(row.defaultNumerals)
        var home = DesktopPageRowMap(page: "home"); home.register([row])
        XCTAssertNil(home.desktop(row.id)); XCTAssertEqual(DesktopPageRowMap(page: "anime").desktop(row.id), "continueWatching")
        let value = try DesktopPageLayout(page: "home", raw: .object(["cwTop": .bool(true)])).native(preserving: PageLayout(), mapping: home)
        XCTAssertTrue(value.cwTop)
    }

    func testTheRealKeychainQueueRoundTripsAnimeContinueOrderHideAndLiteralNameWithoutResettingOtherRows() async throws {
        let owner = "owned-continuation-cloud-" + UUID().uuidString
        let preferences = PageCustomization(owner: owner, page: "anime"), engine = HarborPageSync(preferences: preferences)
        let scope = NavigationScope.harbor(owner: owner, account: "owned-account", profile: "owned-profile", linked: false)
        defer {
            engine.unbind()
            for key in ["page-layout-" + EBookShelf.hash(owner + "|anime"),
                "page-layout-scope-" + EBookShelf.hash(scope.key + "|anime"),
                "page-layout-sync-" + EBookShelf.hash(scope.key + "|owned-profile:anime")] { try? KeychainStore().remove(key) }
        }
        let raw: JSONValue = .object(["order": .array([.string("airing"), .string("continueWatching"), .string("future-row")]),
            "hidden": .array([.string("continueWatching")]), "renamed": .object(["continueWatching": .string("Desktop row")]), "future": .integer(9)])
        let state: JSONValue = .object(["rev": .integer(4), "docs": .array([.object(["key": .string("owned-profile:anime"), "rev": .integer(4), "value": raw])])])
        let profile: JSONValue = .object(["syncId": .string("owned-profile"), "settingsLinked": .bool(false)])
        let row = PageRail.continuing(kind: "anime"), airing = PageRail.discovery(.init(id: "anime-airing", title: "Airing Now", kind: "anime", path: "owned"))
        try await engine.synchronize(state: state, account: "owned-account", profile: profile) { _ in XCTFail("A pull must not echo"); return .null }
        XCTAssertEqual(preferences.title(row, among: [row, airing]), "Desktop row")
        XCTAssertEqual(preferences.ordered([row, airing]).map(\.id), [airing.id])
        preferences.rename(row, to: "Desde iOS"); preferences.change { $0.hidden.remove(row.id) }
        preferences.setEditingRails([row, airing]); preferences.move(row, toward: airing)
        XCTAssertTrue(engine.hasPendingChanges)
        try await engine.synchronize(state: state, account: "owned-account", profile: profile) { request in
            let write = try XCTUnwrap(request["writes"].array.first)
            XCTAssertEqual(write["key"], .string("owned-profile:anime")); XCTAssertEqual(write["baseRev"], .integer(4))
            XCTAssertEqual(write["value"]["order"], .array([.string("continueWatching"), .string("airing"), .string("future-row")]))
            XCTAssertEqual(write["value"]["hidden"], .array([])); XCTAssertEqual(write["value"]["renamed"]["continueWatching"], .string("Desde iOS"))
            XCTAssertEqual(write["value"]["future"], .integer(9))
            return .object(["results": .array([.object(["ok": .bool(true), "rev": .integer(5)])])])
        }
        XCTAssertFalse(engine.hasPendingChanges)
        let reopened = PageCustomization(owner: owner, page: "anime"); reopened.bind(scope)
        XCTAssertEqual(reopened.layout.order, preferences.layout.order)
        XCTAssertEqual(reopened.layout.renamed[row.id], "Desde iOS"); XCTAssertFalse(reopened.layout.hidden.contains(row.id))
    }

    private func record(_ id: String, type: String, offset: Int64 = 60_000) -> LibraryRecord {
        LibraryRecord(raw: .object(["_id": .string(id), "type": .string(type), "name": .string("Owned title"),
            "removed": .bool(false), "temp": .bool(false), "state": .object(["timeOffset": .integer(offset), "duration": .integer(600_000)])]))
    }
}

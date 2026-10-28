import XCTest
@testable import Harbor

actor OwnedCustomListDisk: CustomListPersistence {
    private var values: [String: JSONValue] = [:]
    var reject = false
    func setReject(_ value: Bool) { reject = value }
    func read(owner: String) -> JSONValue? { values[owner] }
    func write(_ value: JSONValue, owner: String) throws {
        if reject { throw HarborError(code: "owned-write-failure") }; values[owner] = value
    }
}

@MainActor final class CustomListTests: XCTestCase {
    private func fixture() throws -> JSONValue {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "custom-lists-reference", withExtension: "json", subdirectory: "Fixtures"))
        let value = try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: url))
        XCTAssertEqual(value["reference"].string, "0834340cec5531650bfe78cd628628702e636987")
        XCTAssertEqual(value["actual_original_typescript_executed"], .bool(true)); XCTAssertEqual(value["provider_network_requests"].integer, 0)
        XCTAssertEqual(value["executed_module_hashes"].objectValue.count, 2); return value
    }
    private func action(_ row: JSONValue) throws -> CustomListsDocument.Action {
        let args = row.array
        func string(_ index: Int) throws -> String { try XCTUnwrap(args[index].string) }
        switch try string(0) {
        case "create": return try .create(string(1), string(2), id: string(3))
        case "rename": return try .rename(string(1), string(2))
        case "describe": return try .describe(string(1), string(2))
        case "delete": return try .delete(string(1))
        case "add": return try .add(string(1), args[2])
        case "remove": return try .remove(string(1), string(2))
        case "toggle": return try .toggle(string(1), args[2])
        case "update": return try .updateItem(string(1), string(2), args[3])
        case "reorderLists": return .reorderLists(args[1].array.compactMap(\.string))
        case "reorderItems": return try .reorderItems(string(1), args[2].array.compactMap(\.string))
        default: throw HarborError(code: "owned-fixture-action")
        }
    }
    func testExecutedDesktopListOperationsLimitsOrderAndPersistedMetadataMatchAllEightScenarios() throws {
        let fixture = try fixture(), at = Int64(try XCTUnwrap(fixture["at"].numericValue)); XCTAssertEqual(fixture["cases"].array.count, 8)
        for row in fixture["cases"].array {
            var document = CustomListsDocument(), writes = 0, outcomes: [JSONValue] = []
            for (index, input) in row["actions"].array.enumerated() {
                let result = document.apply(try action(input), at: at + Int64(index)); if result.changed { writes += 1 }
                if input.array[0].string == "create" { outcomes.append(result.createdID.map(JSONValue.string) ?? .null) }
                else if input.array[0].string == "toggle" { outcomes.append(.bool(result.contains ?? false)) }
                else { outcomes.append(.null) }
            }
            XCTAssertEqual(JSONValue.array(document.sorted.map(\.raw)), row["expected"], row["name"].string ?? "")
            XCTAssertEqual(JSONValue.array(outcomes), row["outcomes"], row["name"].string ?? "")
            XCTAssertEqual(writes, row["writes"].integer, row["name"].string ?? "")
        }
    }
    func testProtectedDiskReopenAndLinkedFallbackRemainScopedUntilAnIndependentProfileEdits() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("owned-custom-lists-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let disk = CustomListDisk(root: root), shared = CustomListStore(owner: "shared", disk: disk, now: { 100 })
        await shared.load(); let created = await shared.apply(.create("Shared", "", id: "shared-list")); XCTAssertEqual(created?.createdID, "shared-list")
        let child = CustomListStore(owner: "independent", inherited: shared, disk: disk, now: { 200 })
        await child.load(); XCTAssertEqual(child.lists.map(\.name), ["Shared"])
        await shared.apply(.rename("shared-list", "Shared update")); XCTAssertEqual(child.lists.map(\.name), ["Shared update"])
        await child.apply(.rename("shared-list", "Independent"))
        await shared.apply(.rename("shared-list", "Later shared")); XCTAssertEqual(child.lists.map(\.name), ["Independent"])
        let restored = CustomListStore(owner: "independent", inherited: shared, disk: CustomListDisk(root: root))
        await restored.load(); XCTAssertEqual(restored.lists.map(\.name), ["Independent"])
        let other = CustomListStore(owner: "other-account", disk: disk); await other.load(); XCTAssertTrue(other.lists.isEmpty)
    }
    func testFailedPersistenceKeepsVisibleOwnedMemoryAndRetrySavesItBeforeRestart() async throws {
        let disk = OwnedCustomListDisk(), store = CustomListStore(owner: "owned", disk: disk, now: { 100 })
        await store.load(); await disk.setReject(true)
        let created = await store.apply(.create("Kept in memory", "Owned", id: "one"))
        XCTAssertEqual(created?.createdID, "one"); XCTAssertEqual(store.lists.map(\.id), ["one"]); XCTAssertTrue(store.unsaved); XCTAssertNotNil(store.error)
        let before = await disk.read(owner: "owned"); XCTAssertNil(before)
        let foreign = CustomListStore(owner: "foreign", disk: disk); await foreign.load(); XCTAssertTrue(foreign.lists.isEmpty)
        await store.load(force: true); XCTAssertEqual(store.lists.map(\.id), ["one"], "Reload must not discard the visible memory fallback")
        await disk.setReject(false); await store.save(); XCTAssertFalse(store.unsaved); XCTAssertNil(store.error)
        let restored = CustomListStore(owner: "owned", disk: disk); await restored.load(); XCTAssertEqual(restored.lists.map(\.id), ["one"])
    }
    func testReadFailureKeepsTheOriginalBytesAndDisablesAnEmptyFallbackOverwrite() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("owned-custom-corrupt-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true); defer { try? FileManager.default.removeItem(at: root) }
        let original = Data("{not-a-list".utf8), file = root.appendingPathComponent(EBookShelf.hash("owned") + ".json")
        try original.write(to: file)
        let store = CustomListStore(owner: "owned", disk: CustomListDisk(root: root)); await store.load()
        XCTAssertFalse(store.ready); XCTAssertNotNil(store.error)
        let result = await store.apply(.create("Must not overwrite", "", id: "one")); XCTAssertNil(result)
        XCTAssertEqual(try Data(contentsOf: file), original)
    }
}

import XCTest
@testable import Harbor

@MainActor final class CustomListConcurrencyTests: XCTestCase {
    func testHeldReloadCoalescesAndKeepsEditsDisabledUntilCommittedDataIsReady() async throws {
        let disk = OwnedCustomListDisk(), store = CustomListStore(owner: "owned", disk: disk, now: { 100 })
        await store.load(); await store.apply(.create("Committed", "", id: "one"))
        await disk.holdRead()
        let reload = Task { await store.load(force: true) }
        for _ in 0..<100 { if await disk.isReadHeld { break }; try await Task.sleep(for: .milliseconds(20)) }
        let held = await disk.isReadHeld; XCTAssertTrue(held); XCTAssertTrue(store.busy)
        let changed = await store.apply(.rename("one", "Must wait")); XCTAssertNil(changed)
        let coalesced = Task { await store.load(force: true) }
        await disk.releaseRead(); await reload.value; await coalesced.value
        XCTAssertFalse(store.busy); XCTAssertEqual(store.lists.map(\.name), ["Committed"])
        await store.apply(.rename("one", "After reload")); XCTAssertEqual(store.lists.map(\.name), ["After reload"])
    }
}

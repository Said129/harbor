import CoreText
import XCTest
@testable import Harbor

final class ReadingDisplayInterfaceSeedTests: XCTestCase {
    @MainActor func testPrepareOwnedVolumeAndActualFontForNewReaderDisplayInterfaces() async throws {
        try await EBookDetailInterfaceSeedTests.prepare()
        let context = AppProfileContext.shared
        let owner = try XCTUnwrap(context.binding?.personalOwner)
        let url = try XCTUnwrap(Bundle.main.url(forResource: "Inter", withExtension: "ttf"))
        let font = try await ReadingFontStore.shared.importFont(url, owner: owner)
        XCTAssertEqual(font.name, "Inter")
    }
}

final class ReadingFontTests: XCTestCase {
    func testActualFontImportsRendersRestoresAndDeletesWithoutGlobalRegistrationOrAnotherOwner() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("reading-font-" + UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let store = ReadingFontStore(root: root), url = try XCTUnwrap(Bundle.main.url(forResource: "Inter", withExtension: "ttf"))
        let first = try await store.importFont(url, owner: "one"), second = try await store.importFont(url, owner: "two")
        XCTAssertEqual(first.id, second.id); XCTAssertNotEqual(first.owner, second.owner)
        let duplicate = try await store.importFont(url, owner: "one")
        XCTAssertEqual(duplicate.id, first.id)
        let fonts = try await store.list(owner: "one"); XCTAssertEqual(fonts.map(\.id), [first.id])
        let absent = try await store.list(owner: "three"); XCTAssertTrue(absent.isEmpty)
        let data = try await ReadingFontStore(root: root).data(id: first.id, owner: "one")
        XCTAssertEqual(data.count, first.bytes)
        let provider = try XCTUnwrap(CGDataProvider(data: data as CFData)), graphic = try XCTUnwrap(CGFont(provider))
        let font = CTFontCreateWithGraphicsFont(graphic, 24, nil, nil)
        XCTAssertEqual(CTFontGetSize(font), 24); XCTAssertGreaterThan(CTFontGetGlyphCount(font), 0)
        do { _ = try await store.data(id: first.id, owner: "three"); XCTFail("No font may cross owners") } catch {}
        try await store.remove(id: first.id, owner: "one")
        let remaining = try await store.list(owner: "one"); XCTAssertTrue(remaining.isEmpty)
        let other = try await store.data(id: second.id, owner: "two"); XCTAssertEqual(other, data)
    }

    func testInvalidOversizedTraversalAndCancelledFontNeverBecomeAnImportedChoice() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("reading-font-invalid-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let store = ReadingFontStore(root: root.appendingPathComponent("store")), invalid = root.appendingPathComponent("invalid.ttf")
        try Data("not a font".utf8).write(to: invalid)
        do { _ = try await store.importFont(invalid, owner: "one"); XCTFail("Invalid font") } catch {}
        let oversized = root.appendingPathComponent("large.ttf")
        try Data(repeating: 0, count: ReadingFontStore.maximumBytes + 1).write(to: oversized)
        do { _ = try await store.importFont(oversized, owner: "one"); XCTFail("Font size guard") } catch let error as HarborError { XCTAssertEqual(error.code, "reading-font-size") }
        do { _ = try await store.data(id: "../invalid", owner: "one"); XCTFail("Reject paths as identities") } catch {}
        let valid = try XCTUnwrap(Bundle.main.url(forResource: "Inter", withExtension: "ttf"))
        let cancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await store.importFont(valid, owner: "one")
        }
        do { _ = try await cancelled.value; XCTFail("Cancelled font must not persist") } catch is CancellationError {}
        let rows = try await store.list(owner: "one"); XCTAssertTrue(rows.isEmpty)
    }
}

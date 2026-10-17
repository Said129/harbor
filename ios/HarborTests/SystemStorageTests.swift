import XCTest
@testable import Harbor

@MainActor final class SystemStorageTests: XCTestCase {
    func testStorageCountsCategoriesOnceAndLeavesImportedFilesIntact() async throws {
        let files = FileManager.default, root = files.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? files.removeItem(at: root) }
        let locations = AppStorageLocations(documents: root.appendingPathComponent("Documents"), library: root.appendingPathComponent("Library"), caches: root.appendingPathComponent("Library/Caches"), temporary: root.appendingPathComponent("tmp"))
        for folder in [locations.documents, locations.library, locations.caches, locations.temporary] { try files.createDirectory(at: folder, withIntermediateDirectories: true) }
        let imported = locations.documents.appendingPathComponent("owned-book.pdf"), data = Data(repeating: 73, count: 37)
        try data.write(to: imported)
        try Data(repeating: 1, count: 19).write(to: locations.library.appendingPathComponent("preferences.json"))
        try Data(repeating: 2, count: 23).write(to: locations.caches.appendingPathComponent("poster.png"))
        try Data(repeating: 3, count: 11).write(to: locations.temporary.appendingPathComponent("scratch"))
        let outside = root.appendingPathComponent("outside"); try files.createDirectory(at: outside, withIntermediateDirectories: true)
        try Data(repeating: 9, count: 4096).write(to: outside.appendingPathComponent("excluded"))
        try files.createSymbolicLink(at: locations.documents.appendingPathComponent("external"), withDestinationURL: outside)
        try files.createSymbolicLink(at: locations.documents.appendingPathComponent("cycle"), withDestinationURL: locations.documents)
        let report = try await AppStorageMaintenance(locations: locations).measure()
        XCTAssertEqual(report.documents, 37); XCTAssertEqual(report.library, 19)
        XCTAssertEqual(report.caches, 23); XCTAssertEqual(report.temporary, 11); XCTAssertEqual(report.files, 90)
        XCTAssertEqual(try Data(contentsOf: imported), data)
        XCTAssertEqual(try AppStorageMaintenance.bytes(in: locations.documents.appendingPathComponent("external")), 0)
        XCTAssertEqual(try AppStorageMaintenance.bytes(in: root.appendingPathComponent("missing")), 0)
    }

    func testCanceledStorageScanStopsWithoutChangingFiles() async throws {
        let files = FileManager.default, root = files.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try files.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? files.removeItem(at: root) }
        let file = root.appendingPathComponent("retained"); try Data([1, 2, 3]).write(to: file)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try AppStorageMaintenance.bytes(in: root)
        }
        do { _ = try await task.value; XCTFail("A canceled scan must stop") }
        catch is CancellationError {}
        XCTAssertEqual(try Data(contentsOf: file), Data([1, 2, 3]))
    }
}

import XCTest
@testable import Harbor

final class MusicFolderRescanTests: XCTestCase {
    @MainActor
    func testFolderImportRescanUpdatesInPlaceAndRemovesManagedMissingTrack() async throws {
        let owner = "music-folder-rescan-" + UUID().uuidString
        let key = "music-library-" + EBookShelf.hash(owner)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: folder)
            try? KeychainStore().remove(key)
        }
        let audio = folder.appendingPathComponent("01.wav")
        // One second of owned 8 kHz mono PCM.
        var wave = try XCTUnwrap(Data(base64Encoded: "UklGRqQ+AABXQVZFZm10IBAAAAABAAEAQB8AAIA+AAACABAAZGF0YYA+AAA="))
        wave.append(Data(repeating: 0, count: 16_000))
        try wave.write(to: audio)
        let library = MusicLibrary(owner: owner, bookmarks: MusicFolderRescanTestBookmarks())

        library.importFolder(folder)
        try await waitForImport(library)
        XCTAssertEqual(library.records.count, 1)
        let first = try XCTUnwrap(library.records.first)

        var changed = try Data(contentsOf: audio)
        changed[changed.index(before: changed.endIndex)] ^= 1
        try changed.write(to: audio, options: .atomic)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(5)], ofItemAtPath: audio.path)
        library.rescanFolder()
        try await waitForImport(library)
        XCTAssertEqual(library.records.count, 1)
        XCTAssertEqual(library.records.first?.id, first.id, "A content update at the tracked path keeps the playlist track ID")
        XCTAssertNotEqual(library.records.first?.filename, first.filename)

        try FileManager.default.removeItem(at: audio)
        library.rescanFolder()
        try await waitForImport(library)
        XCTAssertTrue(library.records.isEmpty, "A completed scan removes only the managed track whose source file disappeared")
    }

    func testLegacyArrayPayloadMigratesToVersionedDocumentWithoutDroppingTracks() throws {
        let original = record(id: "local:legacy", filename: String(repeating: "a", count: 64) + ".mp3")
        let encoded = try JSONEncoder().encode([original])

        let document = try JSONDecoder().decode(MusicLibraryDocument.self, from: encoded)

        XCTAssertEqual(document.version, 1)
        XCTAssertEqual(document.records, [original])
        XCTAssertNil(document.trackedFolder)
        let persisted = try JSONDecoder().decode(MusicLibraryDocument.self, from: JSONEncoder().encode(document))
        XCTAssertEqual(persisted.records, [original])
    }

    func testIncrementalScanSkipsOnlyMatchingSizeAndModificationTime() {
        let url = URL(fileURLWithPath: "/music/01.mp3")
        let same = MusicFolderFile(url: url, relativePath: "01.mp3", size: 128, modifiedAtSeconds: 100)
        let previous = MusicFolderIndexEntry(recordID: "local:stable", size: 128, modifiedAtSeconds: 100, preserveWhenMissing: false)

        XCTAssertTrue(MusicIncrementalScan.isUnchanged(same, from: previous))
        XCTAssertFalse(MusicIncrementalScan.isUnchanged(.init(url: url, relativePath: "01.mp3", size: 129, modifiedAtSeconds: 100), from: previous))
        XCTAssertFalse(MusicIncrementalScan.isUnchanged(.init(url: url, relativePath: "01.mp3", size: 128, modifiedAtSeconds: 101), from: previous))
        XCTAssertFalse(MusicIncrementalScan.isUnchanged(same, from: nil))
    }

    func testIncompleteTraversalNeverMarksMissingEntriesForRemoval() {
        let previous: Set<String> = ["album/one.mp3", "album/two.mp3"]
        let seen: Set<String> = ["album/one.mp3"]

        XCTAssertTrue(MusicIncrementalScan.removedPaths(previous: previous, seen: seen, completed: false).isEmpty)
        XCTAssertEqual(MusicIncrementalScan.removedPaths(previous: previous, seen: seen, completed: true), ["album/two.mp3"])
    }

    func testFolderBookmarkIndexAndDeletionSuppressionsRoundTripTogether() throws {
        let track = record(id: "local:stable", filename: String(repeating: "b", count: 64) + ".mp3")
        let folder = MusicFolderSource(id: "folder", name: "Music", bookmark: Data([1, 2, 3]),
                                       entries: ["album/one.mp3": .init(recordID: track.id, size: 128, modifiedAtSeconds: 100, preserveWhenMissing: false)],
                                       suppressedPaths: ["album/deleted.mp3"])
        let document = MusicLibraryDocument(records: [track], trackedFolder: folder)

        let decoded = try JSONDecoder().decode(MusicLibraryDocument.self, from: JSONEncoder().encode(document))

        XCTAssertEqual(decoded.records, [track])
        XCTAssertEqual(decoded.trackedFolder?.bookmark, Data([1, 2, 3]))
        XCTAssertEqual(decoded.trackedFolder?.entries["album/one.mp3"]?.recordID, track.id)
        XCTAssertEqual(decoded.trackedFolder?.suppressedPaths, ["album/deleted.mp3"])
    }

    func testChangedContentAtTheSameFolderPathKeepsItsRecordID() {
        let oldID = MusicIncrementalScan.recordID(sourceID: "folder", relativePath: "album/one.mp3", existingID: nil)

        XCTAssertEqual(MusicIncrementalScan.recordID(sourceID: "folder", relativePath: "album/one.mp3", existingID: oldID), oldID)
        XCTAssertNotEqual(MusicIncrementalScan.recordID(sourceID: "folder", relativePath: "album/two.mp3", existingID: nil), oldID)
    }

    func testSuppressedPathsAreNotImportedAgain() {
        XCTAssertFalse(MusicIncrementalScan.shouldImport(path: "album/removed.mp3", suppressed: ["album/removed.mp3"]))
        XCTAssertTrue(MusicIncrementalScan.shouldImport(path: "album/new.mp3", suppressed: ["album/removed.mp3"]))
    }

    private func record(id: String, filename: String) -> MusicRecord {
        let track = MusicTrack(id: id, connectorId: "local", sourceId: filename, playbackUrl: nil, title: "Track", artist: "Artist",
                               album: "Album", artwork: "", durationSeconds: 1, durationLabel: "0:01")
        let local = LocalMusic(track: track, albumKey: "album", artistKey: "artist", albumArtist: "Artist", trackNo: 1, discNo: nil, year: nil)
        return MusicRecord(local: local, filename: filename, originalName: "track.mp3", size: 1, importedAt: Date(timeIntervalSince1970: 1), cover: nil)
    }

    @MainActor private func waitForImport(_ library: MusicLibrary, timeout: TimeInterval = 20) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while library.importing, Date() < deadline { try await Task.sleep(for: .milliseconds(25)) }
        XCTAssertFalse(library.importing, "The bounded music folder operation should finish")
        XCTAssertNil(library.error)
    }
}

private struct MusicFolderRescanTestBookmarks: LocalLibraryBookmarks {
    func bookmark(for url: URL) throws -> Data { Data(url.standardizedFileURL.path.utf8) }
    func resolve(_ data: Data) throws -> (url: URL, stale: Bool) {
        (URL(fileURLWithPath: String(decoding: data, as: UTF8.self)), false)
    }
}

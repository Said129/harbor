import Foundation
import XCTest
@testable import Harbor

final class MusicPlaylistImportTests: XCTestCase {
    @MainActor func testSelectedFolderImportsRealAudioAndPreservesM3UMetadataAndFullOrder() async throws {
        let owner = "owned-m3u-" + UUID().uuidString
        let library = MusicLibrary(owner: owner), store = MusicPlaylistStore(owner: owner)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(owner)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let fixture = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "owned-tone", withExtension: "wav", subdirectory: "Fixtures"))
        let audio = folder.appendingPathComponent("owned.wav")
        try FileManager.default.copyItem(at: fixture, to: audio)
        defer { cleanup(owner, folder: folder) }
        let content = "#EXTM3U\n#EXTINF:8,Owned Artist - Import metadata\nowned.wav\n#EXTINF:0,Owned Radio\nhttps://example.com/owned-radio\n"
        let draft = try await MusicPlaylistFiles.shared.parse(Data(content.utf8), base: folder, filename: "Collection.m3u8", owner: owner, records: [])
        XCTAssertTrue(draft.needsFolder)
        var lastProgress = 0
        let playlist = try await MusicPlaylistImporter.run(draft, name: "Collection", folder: folder, library: library, store: store, allowed: { true }, cancel: {}, progress: { lastProgress = $0; XCTAssertEqual($1, 2) })
        XCTAssertEqual(lastProgress, 2)
        XCTAssertEqual(playlist.trackIds, draft.tracks.map(\.id))
        XCTAssertEqual(library.records.count, 1)
        let tracks = store.recordings(in: playlist.id)
        XCTAssertEqual(tracks[0].title, "Import metadata")
        XCTAssertEqual(tracks[0].artist, "Owned Artist")
        XCTAssertEqual(tracks[1].playbackUrl, "https://example.com/owned-radio")
        let record = try XCTUnwrap(MusicLocalRecordIndex(library.records).record(tracks[0]))
        XCTAssertEqual(try Data(contentsOf: MusicFileService.file(record, owner: owner)), try Data(contentsOf: audio))
        XCTAssertNotEqual(tracks[0].id, record.id, "M3U identity survives the genuine local copy")
        XCTAssertEqual(MusicPlaylistStore(owner: owner).recordings(in: playlist.id), tracks)
        let roundTrip = try await MusicPlaylistFiles.shared.parse(Data(("#EXTM3U\n" + (try MusicFileService.file(record, owner: owner)).path + "\n").utf8), base: folder, filename: "Reimport.m3u", owner: owner, records: library.records)
        XCTAssertFalse(roundTrip.needsFolder)
        XCTAssertEqual(roundTrip.owned.values.first?.id, record.id)
    }

    @MainActor func testMissingFilesAndRetiredProfileCannotCreatePartialPlaylistsOrTouchOriginals() async throws {
        let owner = "owned-m3u-rollback-" + UUID().uuidString
        let library = MusicLibrary(owner: owner), store = MusicPlaylistStore(owner: owner)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(owner)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let fixture = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "owned-tone", withExtension: "wav", subdirectory: "Fixtures"))
        let audio = folder.appendingPathComponent("exists.wav")
        try FileManager.default.copyItem(at: fixture, to: audio)
        defer { cleanup(owner, folder: folder) }
        let draft = try await MusicPlaylistFiles.shared.parse(Data("exists.wav\nmissing.wav\n".utf8), base: folder, filename: "Missing.m3u", owner: owner, records: [])
        do {
            _ = try await MusicPlaylistImporter.run(draft, name: "Missing", folder: folder, library: library, store: store, allowed: { true }, cancel: {}, progress: { _, _ in })
            XCTFail("A missing audio file must be reported")
        } catch { XCTAssertTrue(library.records.isEmpty); XCTAssertTrue(store.playlists.isEmpty) }
        XCTAssertEqual(try Data(contentsOf: audio), try Data(contentsOf: fixture))
        let current = try await MusicPlaylistFiles.shared.parse(Data("exists.wav\n".utf8), base: folder, filename: "Cancelled.m3u", owner: owner, records: [])
        var permitted = true
        do {
            _ = try await MusicPlaylistImporter.run(current, name: "Cancelled", folder: folder, library: library, store: store, allowed: { permitted }, cancel: {}, progress: { _, _ in permitted = false })
            XCTFail("Retiring an owner must prevent publication")
        } catch is CancellationError { }
        XCTAssertTrue(library.records.isEmpty); XCTAssertTrue(store.playlists.isEmpty)
        XCTAssertFalse(library.importing)
    }

    func testCrossPlatformPathsUseUnambiguousFolderMatchesAndRejectAmbiguousBasenames() throws {
        let root = URL(fileURLWithPath: "/owned-folder", isDirectory: true)
        let a = root.appendingPathComponent("Album A/track.flac"), b = root.appendingPathComponent("Album B/track.flac")
        let index = try MusicPlaylistLocalIndex(root: root, files: [a, b])
        func entry(_ location: String) -> Harbor.MusicTrack {
            .init(id: "m3u:owned", connectorId: "local", sourceId: location, playbackUrl: location, title: "Owned", artist: "Owned", album: nil, artwork: "", durationSeconds: 0, durationLabel: "0:00")
        }
        XCTAssertEqual(try index.file(entry("C:\\Music\\Album A\\track.flac")), a)
        XCTAssertThrowsError(try index.file(entry("track.flac")))
        XCTAssertThrowsError(try MusicPlaylistLocalIndex(root: root, files: [URL(fileURLWithPath: "/another-owner/track.flac")]))
    }

    @MainActor private func cleanup(_ owner: String, folder: URL) {
        try? KeychainStore().remove("music-library-" + EBookShelf.hash(owner))
        try? KeychainStore().remove("music-playlists-v2-" + EBookShelf.hash(owner))
        // Both roots are created by this test and contain only owned fixtures.
        if let root = try? MusicFileService.root(owner: owner) { try? FileManager.default.removeItem(at: root) }
        try? FileManager.default.removeItem(at: folder)
    }
}

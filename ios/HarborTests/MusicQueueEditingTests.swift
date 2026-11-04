import SwiftUI
import UIKit
import XCTest
@testable import Harbor

@MainActor final class MusicQueueEditingTests: XCTestCase {
    func testUpcomingReorderingAndClearingPreserveCurrentClockHistoryAndRejectRetiredSnapshots() async throws {
        let engine = SharedMusicControlledEngine(), resolver = SharedMusicResolver()
        let player = MusicPlayback(engine: engine, systemIntegration: false, recordPlayed: { _, _ in })
        let oldShuffle = player.shuffle, oldRepeat = player.repeatMode
        player.shuffle = false; player.repeatMode = .off
        defer { player.stop(); player.shuffle = oldShuffle; player.repeatMode = oldRepeat }
        let tracks = (0..<6).map(track)
        player.play(tracks[1], queue: tracks, using: resolver)
        try await wait { player.loaded }
        player.setPaused(true); try await wait { player.paused }
        let original = player.queueSnapshot, position = player.position
        let current = try XCTUnwrap(original.current)
        let before = await engine.opened
        XCTAssertEqual(original.previous.map(\.track.id), ["track-0"])
        XCTAssertEqual(original.upcoming.map(\.track.id), ["track-2", "track-3", "track-4", "track-5"])
        player.moveUpcoming(from: IndexSet([0, 2]), to: 4, in: original)
        XCTAssertEqual(player.queueSnapshot.upcoming.map(\.track.id), ["track-3", "track-5", "track-2", "track-4"])
        XCTAssertEqual(player.currentTrack?.id, "track-1"); XCTAssertTrue(player.paused)
        XCTAssertEqual(player.position, position)
        let moved = player.items.map(\.id)
        player.clearUpcoming(in: original)
        player.moveUpcoming(from: IndexSet(integer: 0), to: 2, in: original)
        player.playQueueItem(original.upcoming[0], in: original)
        player.prioritizeQueueItem(original.previous[0], in: original)
        player.removeQueueItem(current, in: original)
        XCTAssertEqual(player.items.map(\.id), moved)
        player.moveUpcoming(from: IndexSet(integer: 50), to: -1, in: player.queueSnapshot)
        XCTAssertEqual(player.items.map(\.id), moved)
        player.clearUpcoming(in: player.queueSnapshot)
        XCTAssertEqual(player.items.map(\.track.id), ["track-0", "track-1"])
        XCTAssertTrue(player.queueSnapshot.upcoming.isEmpty); XCTAssertEqual(player.currentTrack?.id, "track-1")
        let after = await engine.opened; XCTAssertEqual(after.count, before.count)
        let staleProfile = player.queueSnapshot
        let retiredCurrent = try XCTUnwrap(staleProfile.current)
        let other = SharedMusicResolver()
        player.play(tracks[5], queue: [tracks[5], tracks[0]], using: other)
        try await wait { player.loaded && player.owner == other.scope.owner }
        player.clearUpcoming(in: staleProfile)
        player.removeQueueItem(retiredCurrent, in: staleProfile)
        XCTAssertEqual(player.items.map(\.track.id), ["track-5", "track-0"])
        resolver.active = false
        other.active = false
        player.clearUpcoming(in: player.queueSnapshot)
        XCTAssertEqual(player.items.count, 2)
    }

    func testNativeQueueControlsRenderForPhoneTabletAndRightToLeftWithOriginalLabels() async throws {
        let resolver = SharedMusicResolver()
        let player = MusicPlayback(engine: SharedMusicControlledEngine(), systemIntegration: false, recordPlayed: { _, _ in })
        let oldShuffle = player.shuffle, oldRepeat = player.repeatMode, oldLanguage = UserDefaults.standard.string(forKey: "uiLanguage")
        player.shuffle = false; player.repeatMode = .off
        defer {
            player.stop(); player.shuffle = oldShuffle; player.repeatMode = oldRepeat
            if let oldLanguage { UserDefaults.standard.set(oldLanguage, forKey: "uiLanguage") }
            else { UserDefaults.standard.removeObject(forKey: "uiLanguage") }
        }
        let tracks = (0..<6).map(track)
        player.play(tracks[1], queue: tracks, using: resolver)
        try await wait { player.loaded }
        for (name, size, language, direction) in [
            ("phone", CGSize(width: 390, height: 844), "es", LayoutDirection.leftToRight),
            ("tablet", CGSize(width: 1024, height: 1366), "es", LayoutDirection.leftToRight),
            ("arabic-phone", CGSize(width: 390, height: 844), "ar", LayoutDirection.rightToLeft)
        ] {
            UserDefaults.standard.set(language, forKey: "uiLanguage")
            try await capture(NavigationStack { MusicQueueView(player: player).environment(\.editMode, .constant(.active)) }
                .environment(\.layoutDirection, direction).environment(\.locale, Locale(identifier: language)),
                              name: "music-editable-queue-" + name, size: size)
        }
        for code in InterfaceLanguage.all.map(\.code) {
            for key in ["music.queue.nowPlaying", "music.row.upNext", "music.queue.previous", "music.queue.empty",
                        "music.queue.dragHint", "music.queue.shuffleNote", "music.transport.queue", "music.transport.clearQueue",
                        "music.queue.moveUp", "music.queue.moveDown", "music.queue.count"] {
                XCTAssertNotEqual(DesktopInterfaceText.value(key, language: code), key)
            }
        }
    }
    func testQueuedSourceAlternativesUseTheOwnedLibraryAndPreserveCurrentAudioAndPriority() async throws {
        let scope = SharedMusicScope(), owner = scope.scope.owner
        let file = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "owned-tone", withExtension: "wav", subdirectory: "Fixtures"))
        let imported = try await MusicFileService.shared.importFile(file, owner: owner).record
        let raw = imported.local.track
        let local = MusicTrack(id: raw.id, connectorId: "local", sourceId: raw.sourceId, playbackUrl: nil,
                               title: "Owned requested recording", artist: "Owned Artist", album: "Owned Album", artwork: "",
                               durationSeconds: raw.durationSeconds, durationLabel: raw.durationLabel)
        let record = MusicRecord(local: .init(track: local, albumKey: "owned-album", artistKey: "owned-artist",
                                             albumArtist: nil, trackNo: nil, discNo: nil, year: nil),
                                 filename: imported.filename, originalName: imported.originalName, size: imported.size,
                                 importedAt: imported.importedAt, cover: nil)
        let server = SubsonicMusicService(scope: scope.scope, currentScope: { scope.scope }, persistence: SharedMusicPairingDisk())
        let session = MusicPlaybackSession(server: server, playlists: MusicPlaylistStore(owner: owner, persistence: SharedMusicDisk()),
                                          localRecords: { [record] }, currentScope: { scope.scope })
        let engine = SharedMusicControlledEngine()
        let player = MusicPlayback(engine: engine, systemIntegration: false, recordPlayed: { _, _ in })
        let oldShuffle = player.shuffle, oldRepeat = player.repeatMode, oldLanguage = UserDefaults.standard.string(forKey: "uiLanguage")
        player.shuffle = false; player.repeatMode = .off
        defer {
            player.stop(); server.dispose(); player.shuffle = oldShuffle; player.repeatMode = oldRepeat
            if let oldLanguage { UserDefaults.standard.set(oldLanguage, forKey: "uiLanguage") }
            else { UserDefaults.standard.removeObject(forKey: "uiLanguage") }
        }
        do {
            let current = track(100)
            let requested = MusicTrack(id: "owned-catalog-request", connectorId: "catalog", sourceId: nil, playbackUrl: nil,
                                       title: local.title, artist: local.artist, album: local.album, artwork: "",
                                       durationSeconds: local.durationSeconds, durationLabel: local.durationLabel)
            player.play(current, queue: [current, requested, track(101)], using: session)
            try await wait { player.loaded }
            player.setPaused(true); try await wait { player.paused }
            let queued = try XCTUnwrap(player.items.first { $0.track.id == requested.id })
            player.prioritizeQueueItem(queued, in: player.queueSnapshot)
            let snapshot = player.queueSnapshot, position = player.position
            let selection = MusicQueueSourceSelection(item: queued, queue: snapshot)
            let candidates = try await session.alternativeSources(for: requested)
            XCTAssertEqual(candidates.count, 1)
            let candidate = try XCTUnwrap(candidates.first)
            XCTAssertEqual(candidate.connectorId, "local"); XCTAssertEqual(candidate.track.id, local.id)
            let before = await engine.opened
            for (name, size, language, direction) in [
                ("phone", CGSize(width: 390, height: 844), "es", LayoutDirection.leftToRight),
                ("tablet", CGSize(width: 1024, height: 1366), "es", LayoutDirection.leftToRight),
                ("arabic-phone", CGSize(width: 390, height: 844), "ar", LayoutDirection.rightToLeft)
            ] {
                UserDefaults.standard.set(language, forKey: "uiLanguage")
                try await capture(NavigationStack { MusicSourcePickerView(player: player, session: session, queuedSelection: selection) }
                    .environment(\.layoutDirection, direction).environment(\.locale, Locale(identifier: language)),
                                  name: "music-queued-source-" + name, size: size)
            }
            try player.replaceQueuedSource(candidate.track, for: queued, in: snapshot)
            let replacement = try XCTUnwrap(player.items.first { $0.id == queued.id })
            XCTAssertEqual(replacement.track.connectorId, "local"); XCTAssertEqual(replacement.track.id, local.id)
            XCTAssertEqual(replacement.track.title, requested.title); XCTAssertEqual(replacement.track.artist, requested.artist)
            XCTAssertEqual(replacement.track.collectionOrigin?.id, requested.id)
            XCTAssertEqual(player.currentTrack?.id, current.id); XCTAssertTrue(player.paused)
            XCTAssertEqual(player.position, position)
            let untouched = await engine.opened; XCTAssertEqual(untouched.count, before.count)
            do { try player.replaceQueuedSource(candidate.track, for: queued, in: snapshot); XCTFail("A retired queue cannot replace a source") }
            catch is CancellationError { }
            player.next()
            try await wait { player.loaded && player.currentTrack?.id == local.id }
            let opened = await engine.opened; XCTAssertEqual(opened.last, imported.filename)
            XCTAssertEqual(player.currentTrack?.collectionOrigin?.id, requested.id)
            scope.scope = .init(owner: owner + "-retired", activation: UUID())
            do { try player.replaceQueuedSource(candidate.track, for: queued, in: player.queueSnapshot); XCTFail("A retired session cannot replace a source") }
            catch is CancellationError { }
            player.stop(); await engine.stop(request: .max)
            try await MusicFileService.shared.remove(imported, owner: owner)
        } catch {
            player.stop(); await engine.stop(request: .max)
            try? await MusicFileService.shared.remove(imported, owner: owner)
            throw error
        }
    }
    private func track(_ index: Int) -> MusicTrack {
        .init(id: "track-\(index)", connectorId: "direct", sourceId: "track-\(index)", playbackUrl: "https://owned.invalid/\(index).wav",
              title: "Owned recording \(index)", artist: "Owned Artist", album: "Owned queue", artwork: "", durationSeconds: 180, durationLabel: "3:00")
    }
    private func wait(_ predicate: @MainActor () -> Bool) async throws {
        for _ in 0..<250 { if predicate() { return }; try await Task.sleep(for: .milliseconds(20)) }
        XCTFail("Owned queue did not settle"); throw HarborError(code: "owned-queue-timeout")
    }
    private func capture<V: View>(_ view: V, name: String, size: CGSize) async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first { $0.isKeyWindow }, window = UIWindow(windowScene: scene)
        window.frame = CGRect(origin: .zero, size: size)
        let host = UIHostingController(rootView: view.preferredColorScheme(.dark))
        window.rootViewController = host; window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil; previous?.makeKeyAndVisible() }
        host.view.layoutIfNeeded(); try await Task.sleep(for: .milliseconds(450))
        let image = UIGraphicsImageRenderer(size: size).image { _ in host.view.drawHierarchy(in: CGRect(origin: .zero, size: size), afterScreenUpdates: true) }
        let attachment = XCTAttachment(image: image); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}

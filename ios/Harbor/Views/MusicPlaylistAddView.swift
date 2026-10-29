import SwiftUI

@MainActor struct MusicPlaylistAddView: View {
    let id: String
    let library: MusicLibrary
    let store: MusicPlaylistStore
    @State private var model = MusicCollectionModel()
    @State private var candidates: [MusicTrack] = []
    @State private var failed = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.musicPlaybackSession) private var session
    private struct Input: Equatable { let held: [MusicTrack]; let candidates: [MusicTrack] }
    private var input: Input {
        let collections = MusicCollections.shared
        guard store.owner == library.owner else { return .init(held: [], candidates: []) }
        let values = collections.tracks(.liked, store: store, library: library.records, owner: library.owner)
            + collections.tracks(.recent, store: store, library: library.records, owner: library.owner)
        return .init(held: store.recordings(in: id, local: library.records), candidates: values)
    }
    var body: some View {
        NavigationStack {
            List {
                Text(DesktopInterfaceText.value("music.library.addTracksCount", variables: ["count": String(candidates.count)])).font(.caption).foregroundStyle(.secondary)
                ForEach(candidates) { track in
                    MusicCollectionTrackRow(track: track, record: library.records.first { $0.id == track.id }, owner: library.owner) {
                        guard store.owner == library.owner, session.map({ $0.scope.owner == library.owner && (try? $0.validate()) != nil }) ?? true else { return }
                        store.add([track], to: id)
                    }.disabled(!store.ready)
                }
                if candidates.isEmpty { Text(DesktopInterfaceText.value("music.library.playlistEmpty")).foregroundStyle(.secondary) }
                if failed { Text(DesktopInterfaceText.value("music.error.load")).foregroundStyle(.orange) }
                if let error = store.error { Text(error).foregroundStyle(.orange) }
            }.listStyle(.plain).scrollContentBackground(.hidden).background(HarborTheme.background)
                .navigationTitle(DesktopInterfaceText.value("music.library.addTracks")).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button(DesktopInterfaceText.value("Close")) { dismiss() } } }
                .task(id: input) {
                    do { let values = try await model.addable(input.candidates, to: input.held); try Task.checkCancellation(); candidates = values; failed = false }
                    catch is CancellationError { }
                    catch { failed = true }
                }
        }.accessibilityIdentifier("music-playlist-add-recordings")
    }
}

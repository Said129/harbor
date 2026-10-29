import SwiftUI
import UniformTypeIdentifiers

struct MusicPlaylistExportDocument: FileDocument {
    static var type: UTType { UTType(filenameExtension: "m3u") ?? .plainText }
    static var readableContentTypes: [UTType] { [type] }
    let data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw MusicPlaylistExportError.unavailable }
        self.data = data
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

@MainActor struct MusicPlaylistExportButton: View {
    let playlist: MusicPlaylist
    let tracks: [MusicTrack]
    let library: MusicLibrary
    let store: MusicPlaylistStore
    @Environment(\.musicPlaybackSession) private var session
    @State private var operation: Task<Void, Never>?
    @State private var request = UUID()
    @State private var busy = false
    @State private var exporting = false
    @State private var prepared: MusicPlaylistExport?
    @State private var notice: String?
    @State private var failure = false
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { start() } label: {
                HStack {
                    if busy { ProgressView().accessibilityHidden(true) } else { Image(systemName: "square.and.arrow.up") }
                    Text(DesktopInterfaceText.value("music.m3u.export"))
                }.frame(minHeight: 44)
            }.disabled(busy || !store.ready || store.owner != library.owner || session == nil)
                .accessibilityLabel(DesktopInterfaceText.value("music.m3u.export") + " · " + DesktopInterfaceText.value("music.m3u.playlist"))
                .accessibilityIdentifier("music-playlist-export")
            if failure { Text(DesktopInterfaceText.value("music.mobile.exportFailed")).font(.caption).foregroundStyle(.orange).accessibilityIdentifier("music-playlist-export-failure") }
            if let notice { Text(notice).font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("music-playlist-export-notice") }
        }
        .fileExporter(isPresented: $exporting, document: prepared.map { MusicPlaylistExportDocument(data: $0.data) },
                      contentType: MusicPlaylistExportDocument.type, defaultFilename: prepared?.filename ?? "playlist.m3u") { result in
            switch result {
            case .success:
                if let prepared {
                    notice = DesktopInterfaceText.value("music.m3u.exportedNotice", variables: ["count": String(prepared.count), "name": prepared.name])
                }
            case .failure(let error):
                if (error as? CocoaError)?.code != .userCancelled { failure = true }
            }
            prepared = nil
        }
        .onDisappear { operation?.cancel(); operation = nil; request = UUID(); busy = false; prepared = nil; exporting = false }
    }
    private func start() {
        guard let session else { return }
        operation?.cancel(); let token = UUID(); request = token; busy = true; failure = false; notice = nil
        let list = playlist, recordings = tracks, owner = library.owner, store = store
        operation = Task {
            defer { if request == token { busy = false; operation = nil } }
            do {
                let file = try await MusicPlaylistExporter.prepare(list, tracks: recordings, owner: owner, using: session, allowed: {
                    store.ready && store.owner == owner && store.playlists.contains { $0.id == list.id }
                })
                try Task.checkCancellation(); guard request == token else { return }
                prepared = file; exporting = true
            } catch is CancellationError { }
            catch { if request == token { failure = true } }
        }
    }
}

import SwiftUI
import UniformTypeIdentifiers

@MainActor struct MusicPlaylistImportView: View {
    let library: MusicLibrary
    let store: MusicPlaylistStore
    let imported: (MusicPlaylist) -> Void
    @Environment(\.musicPlaybackSession) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var selecting = false
    @State private var selectingFolder = false
    @State private var draft: MusicPlaylistImportDraft?
    @State private var name = ""
    @State private var folder: URL?
    @State private var busy = false
    @State private var failed = false
    @State private var completed = 0
    @State private var request = UUID()
    @State private var operation: Task<Void, Never>?
    private var allowed: Bool {
        store.owner == library.owner && session.map { $0.scope.owner == library.owner && (try? $0.validate()) != nil } == true
    }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(DesktopInterfaceText.value("music.mobile.m3uHelp")).font(.footnote).foregroundStyle(.secondary)
                    Button(DesktopInterfaceText.value("music.mobile.m3uSelect")) { selecting = true }
                        .disabled(busy).accessibilityIdentifier("music-m3u-file")
                    if let draft {
                        Text(draft.filename).font(.subheadline).lineLimit(2)
                        Text(DesktopInterfaceText.value("music.card.trackCount", variables: ["count": String(draft.tracks.count)])).font(.caption).foregroundStyle(.secondary)
                        TextField(DesktopInterfaceText.value("music.playlist.nameLabel"), text: $name).disabled(busy)
                            .accessibilityIdentifier("music-m3u-name")
                        if draft.needsFolder {
                            Text(DesktopInterfaceText.value("music.mobile.m3uFolderHelp")).font(.footnote).foregroundStyle(.secondary)
                            Button(DesktopInterfaceText.value("music.mobile.m3uAudioFolder")) { selectingFolder = true }
                                .disabled(busy).accessibilityIdentifier("music-m3u-folder")
                            if let folder { Text(folder.lastPathComponent).font(.caption).foregroundStyle(.secondary) }
                        }
                        Button(DesktopInterfaceText.value("music.m3u.import")) { start() }
                            .disabled(busy || library.importing || !library.ready || !store.ready || !allowed || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (draft.needsFolder && folder == nil))
                            .accessibilityIdentifier("music-m3u-import")
                    }
                }
                if busy {
                    Section {
                        if let draft, completed > 0 { ProgressView(value: Double(completed), total: Double(max(1, draft.tracks.count))) }
                        else { ProgressView() }
                    }
                }
                if failed { Section { Text(DesktopInterfaceText.value("music.mobile.m3uFailed")).foregroundStyle(.orange).accessibilityIdentifier("music-m3u-failure") } }
            }.navigationTitle(DesktopInterfaceText.value("music.m3u.import")).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button(DesktopInterfaceText.value("Close")) { operation?.cancel(); dismiss() } } }
        }
        .fileImporter(isPresented: $selecting, allowedContentTypes: [UTType(filenameExtension: "m3u") ?? .plainText, UTType(filenameExtension: "m3u8") ?? .plainText], allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls): if let url = urls.first { load(url) }
            case .failure(let error): if (error as? CocoaError)?.code != .userCancelled { failed = true }
            }
        }
        .fileImporter(isPresented: $selectingFolder, allowedContentTypes: [.folder], allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls): folder = urls.first; failed = false
            case .failure(let error): if (error as? CocoaError)?.code != .userCancelled { failed = true }
            }
        }
        .onDisappear { operation?.cancel(); operation = nil; request = UUID(); busy = false }
        .accessibilityIdentifier("music-m3u-import-sheet")
    }
    private func load(_ url: URL) {
        operation?.cancel(); let token = UUID(); request = token; busy = true; failed = false; completed = 0; draft = nil; folder = nil
        operation = Task {
            defer { if request == token { busy = false; operation = nil } }
            do {
                guard allowed else { throw CancellationError() }
                let value = try await MusicPlaylistFiles.shared.read(url, owner: library.owner, records: library.records)
                try Task.checkCancellation(); guard allowed, request == token else { return }
                draft = value; name = value.suggestedName.isEmpty ? DesktopInterfaceText.value("music.m3u.imported") : value.suggestedName
            } catch is CancellationError { }
            catch { if request == token { failed = true } }
        }
    }
    private func start() {
        guard let draft, !busy else { return }
        let token = UUID(); request = token; busy = true; failed = false; completed = 0
        operation = Task {
            defer { if request == token { busy = false; operation = nil } }
            do {
                let playlist = try await MusicPlaylistImporter.run(draft, name: name, folder: folder, library: library, store: store,
                    allowed: { allowed && request == token }, cancel: { operation?.cancel() }, progress: { value, _ in completed = value })
                try Task.checkCancellation(); guard allowed, request == token else { return }
                imported(playlist); dismiss()
            } catch is CancellationError { }
            catch { if request == token { failed = true } }
        }
    }
}

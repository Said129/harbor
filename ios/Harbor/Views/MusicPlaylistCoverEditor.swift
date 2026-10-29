import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

@MainActor struct MusicPlaylistCoverEditor: View {
    let playlist: String
    let tracks: [MusicTrack]
    let library: MusicLibrary
    let store: MusicPlaylistStore
    @Environment(\.musicPlaybackSession) private var session
    @State private var importing = false
    @State private var choosingPhoto = false
    @State private var photo: PhotosPickerItem?
    @State private var hasCustom = false
    @State private var busy = false
    @State private var failure: String?
    @State private var request = UUID()
    @State private var operation: Task<Void, Never>?
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .bottomTrailing) {
                MusicCollectionCover(tracks: tracks, local: library.records, owner: library.owner, playlist: playlist, onCustomChange: { hasCustom = $0 })
                Menu {
                    Button(DesktopInterfaceText.value("music.playlist.coverUpload")) { importing = true }
                    Button(DesktopInterfaceText.value("Upload photo")) { choosingPhoto = true }
                    if hasCustom {
                        Button(DesktopInterfaceText.value("music.playlist.coverRemove"), role: .destructive) { clear() }
                    }
                } label: {
                    Group { if busy { ProgressView().tint(HarborTheme.ink) } else { MusicGlyph("plus", size: 18) } }
                        .frame(width: 44, height: 44).background(HarborTheme.background.opacity(0.85), in: .circle)
                }.buttonStyle(.borderless).disabled(busy || !store.ready || store.owner != library.owner)
                    .accessibilityLabel(DesktopInterfaceText.value("music.playlist.coverUpload")).accessibilityIdentifier("music-playlist-cover-edit")
            }.aspectRatio(1, contentMode: .fit)
            if let failure { Text(DesktopInterfaceText.value(failure)).font(.caption2).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("music-playlist-cover-error") }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.image], allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls): if let url = urls.first { start { try await Self.read(url) } }
            case .failure(let error): if (error as? CocoaError)?.code != .userCancelled { failure = "music.playlist.coverFailed" }
            }
        }
        .photosPicker(isPresented: $choosingPhoto, selection: $photo, matching: .images, preferredItemEncoding: .compatible)
        .onChange(of: photo) { _, value in
            if let value { start { guard let data = try await value.loadTransferable(type: Data.self) else { throw MusicPlaylistCoverError.type }; return data } }
        }
        .onDisappear { operation?.cancel(); operation = nil; request = UUID(); busy = false }
    }
    private func allowed() -> @MainActor @Sendable () -> Bool {
        let owner = library.owner, playlist = playlist, store = store, session = session
        return {
            store.ready && store.owner == owner && store.playlists.contains { $0.id == playlist }
                && (session.map { $0.scope.owner == owner && (try? $0.validate()) != nil } ?? true)
        }
    }
    private func start(_ load: @escaping @MainActor () async throws -> Data) {
        operation?.cancel(); let token = UUID(); request = token; busy = true; failure = nil
        let permission = allowed(), owner = library.owner, playlist = playlist
        operation = Task {
            defer { if request == token { busy = false; photo = nil; operation = nil } }
            do {
                guard permission() else { throw CancellationError() }
                let data = try await load(); try Task.checkCancellation()
                try await MusicPlaylistCoverStore.shared.save(data, owner: owner, playlist: playlist, allowed: permission)
            } catch is CancellationError { }
            catch { if request == token { failure = Self.message(error) } }
        }
    }
    private func clear() {
        failure = nil
        do { try MusicPlaylistCoverStore.shared.clear(owner: library.owner, playlist: playlist, allowed: allowed()) }
        catch is CancellationError { }
        catch { failure = Self.message(error) }
    }
    private static func message(_ error: Error) -> String {
        switch error {
        case MusicPlaylistCoverError.type: "music.playlist.coverType"
        case MusicPlaylistCoverError.size: "music.playlist.coverSize"
        default: "music.playlist.coverFailed"
        }
    }
    private static func read(_ url: URL) async throws -> Data {
        let task = Task.detached(priority: .utility) {
            try Task.checkCancellation()
            let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values.isRegularFile == true else { throw MusicPlaylistCoverError.type }
            guard let size = values.fileSize, size <= 24 * 1024 * 1024 else { throw MusicPlaylistCoverError.size }
            let data = try Data(contentsOf: url); try Task.checkCancellation(); return data
        }
        return try await withTaskCancellationHandler(operation: { try await task.value }, onCancel: { task.cancel() })
    }
}

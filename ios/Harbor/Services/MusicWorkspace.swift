import Foundation

/// Catalog navigation and a song playing outside the Music page keep the same
/// profile-owned server session, including its credential revision.
@MainActor final class MusicWorkspace {
    let scope: PluginExecutionScope
    let library: MusicLibrary
    let playlists: MusicPlaylistStore
    let server: SubsonicMusicService
    let catalog: MusicCatalogModel
    let playback: MusicPlaybackSession
    private var disposed = false
    var available: Bool { !disposed && server.active }
    init(scope: PluginExecutionScope, currentScope: @escaping @MainActor () -> PluginExecutionScope) {
        self.scope = scope
        let library = MusicLibrary(owner: scope.owner), playlists = MusicPlaylistStore(owner: scope.owner)
        let server = SubsonicMusicService(scope: scope, currentScope: currentScope)
        self.library = library; self.playlists = playlists; self.server = server
        catalog = MusicCatalogModel(client: MusicServerCatalogClient(server: server, currentScope: currentScope))
        playback = MusicPlaybackSession(server: server, playlists: playlists, localRecords: { library.records }, currentScope: currentScope)
    }
    func dispose() { disposed = true; server.dispose(); library.cancelImport(); catalog.invalidatePrivateServer() }
}

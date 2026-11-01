import Foundation

/// Catalog navigation and a song playing outside the Music page keep the same
/// profile-owned server session, including its credential revision.
@MainActor final class MusicWorkspace {
    let scope: PluginExecutionScope
    let library: MusicLibrary
    let playlists: MusicPlaylistStore
    let server: SubsonicMusicService
    let spotify: SpotifyMusicService
    let lyrics: MusicLyricsClient
    let soundcloud: SoundCloudMusicService
    let catalog: MusicCatalogModel
    let playback: MusicPlaybackSession
    private var disposed = false
    var available: Bool { !disposed && server.active }
    init(scope: PluginExecutionScope, currentScope: @escaping @MainActor () -> PluginExecutionScope) {
        self.scope = scope
        let library = MusicLibrary(owner: scope.owner), playlists = MusicPlaylistStore(owner: scope.owner)
        let server = SubsonicMusicService(scope: scope, currentScope: currentScope)
        self.library = library; self.playlists = playlists; self.server = server
        spotify = SpotifyMusicService(scope: scope, currentScope: currentScope)
        let lyrics = MusicLyricsClient(scope: scope, currentScope: currentScope); self.lyrics = lyrics
        let soundcloud = SoundCloudMusicService(scope: scope, currentScope: currentScope); self.soundcloud = soundcloud
        catalog = MusicCatalogModel(client: MusicServerCatalogClient(server: server, soundcloud: soundcloud, currentScope: currentScope))
        playback = MusicPlaybackSession(server: server, playlists: playlists, localRecords: { library.records }, localRevision: { library.revision }, lyrics: lyrics, soundcloud: soundcloud, currentScope: currentScope)
    }
    func dispose() { disposed = true; soundcloud.dispose(); lyrics.dispose(); spotify.dispose(); server.dispose(); library.cancelImport(); catalog.invalidatePrivateServer() }
}

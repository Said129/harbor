import SwiftUI

/// Desktop's AniList step of the playback autosave (`use-resume-autosave.ts`): after 90 seconds the entry
/// becomes Current, and from 70 % of the episode (or its end) the episode count is written forward.
/// Only `kitsu:`, `mal:` and `anilist:` entries count; anime found through IMDb or TMDB ids is not resolved yet.
struct AniListPlaybackSync: ViewModifier {
    let state: PlayerState
    let session: PlaybackSession
    let media: Media?
    let library: LibraryModel?
    let resumePending: Bool
    @AppStorage("anilistAutoSync") private var autoSync = true

    func body(content: Content) -> some View {
        content.task(id: autoSync && !resumePending) {
            guard autoSync, !resumePending, session.progressEnabled, let library,
                  let target = AniListTracking.target(metaID: session.target.id, videoID: session.target.videoId, fallbackEpisode: session.target.episode) else { return }
            let context = AppProfileContext.shared, activation = context.activationID, generation = context.playback.generation
            let owner = library.personalOwner, account = AniListAccount.forOwner(owner)
            guard context.binding?.personalOwner == owner else { return }
            do { if !account.ready { try account.load() } } catch { return }
            guard let stored = account.session, stored.isActive() else { return }
            let token = stored.accessToken
            let sync = AniListSync(
                client: AniListClient(transport: AniListHTTPTransport()), token: token,
                owned: { context.activationID == activation && context.playback.generation == generation && account.session?.accessToken == token && AniListAccount.autoSyncEnabled },
                kitsuToAniList: { await AnimeFranchiseService.shared.anilistMediaID(kitsu: $0) },
                authenticationFailed: { await account.validate() },
                emit: { account.record($0) })
            let title = (session.media ?? media)?.name ?? ""
            var settled = false
            var nextAttempt = Date.distantPast
            while !Task.isCancelled {
                if Date() >= nextAttempt {
                    switch AniListTracking.phase(position: state.position, duration: state.duration, ended: state.ended) {
                    case .none: break
                    case .watching: await sync.markWatching(target.id, title: title)
                    case .progress:
                        if !settled {
                            settled = await sync.syncProgress(target.id, episode: target.episode, title: title, season: session.target.season)
                            // A lookup or write that failed is tried again, but not on every tick.
                            if !settled { nextAttempt = Date().addingTimeInterval(30) }
                        }
                    }
                }
                do { try await Task.sleep(for: .seconds(5)) } catch { break }
            }
        }
    }
}

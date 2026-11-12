import Foundation

/// Desktop's Simkl half of the bookmark toggle (`lib/watchlist.ts` `syncWithSimkl`, `lib/simkl/watchlist.ts`): saving a
/// title adds it to Simkl's Plan to Watch list, and removing it sends Desktop's removal request. It runs only for a
/// connected Simkl account and, as on Desktop, a failed request does not undo the local bookmark.
@MainActor enum SimklWatchlistWrite {
    /// The library request one bookmark change sends.
    static func endpoint(saved: Bool, target: SimklTarget) -> SimklLibraryEndpoint {
        saved ? .status(target, .plantowatch) : .remove(target)
    }

    static func enqueue(_ media: Media, saved: Bool, owner: String) {
        let account = SimklAccountStore.forOwner(owner)
        if !account.ready { try? account.load() }
        guard let session = account.session else { return }
        let token = session.accessToken
        Task {
            let resolved: SimklTarget?
            do { resolved = try await SimklTarget.resolve(media) } catch { return }
            guard let target = resolved else { return }
            _ = try? await SimklClient.shared.response(.library(endpoint(saved: saved, target: target)), token: token)
        }
    }
}

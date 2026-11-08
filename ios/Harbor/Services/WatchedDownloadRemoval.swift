import Foundation

/// Desktop's `deleteWatchedDownloads`: a download whose playback reaches 90 percent is removed through `DownloadManager.remove`.
/// The player reads the file while it is open, so a removal the progress saves ask for waits until the player closes (`playerClosed`).
@MainActor final class WatchedDownloadRemoval {
    static let shared = WatchedDownloadRemoval()

    /// The decision for one progress save: the setting is on, the playing source is a download (never a stream),
    /// and the playback reached the `UISettingsPolicy` rule.
    nonisolated static func shouldRemove(enabled: Bool, viaDownload: Bool, positionMs: Double, durationMs: Double) -> Bool {
        guard enabled, viaDownload, positionMs.isFinite, durationMs.isFinite, durationMs > 0 else { return false }
        return UISettingsPolicy.removesWatchedDownload(enabled: true, progress: positionMs / durationMs)
    }

    /// Downloads waiting for their player to close, keyed by session.
    private var pending: [UUID: (item: DownloadItem, owner: String)] = [:]
    /// Sessions whose download was already queued, so each session removes at most one download.
    private var handled: Set<UUID> = []

    /// Called on every progress save. Remembers the playing download once the rule is reached.
    func note(session: PlaybackSession, value: ResumeSnapshot) {
        guard pending[session.id] == nil, !handled.contains(session.id), session.source.via == "download",
              let owner = session.personalOwner,
              Self.shouldRemove(enabled: InterfacePreferences.shared.deleteWatchedDownloads, viaDownload: true,
                                positionMs: value.positionMs, durationMs: value.durationMs) else { return }
        let manager = DownloadManager.shared
        guard let item = manager.items.first(where: { (try? manager.file($0).path) == session.source.url }) else { return }
        pending[session.id] = (item: item, owner: owner)
    }

    /// Called when the download player is dismissed, so the file is no longer open. Removes the queued downloads once each.
    func playerClosed() {
        let ready = pending
        pending = [:]
        for (session, entry) in ready {
            handled.insert(session)
            DownloadManager.shared.remove(entry.item, owner: entry.owner)
        }
    }
}

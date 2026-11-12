import Foundation

/// What the in-player Download control shows (Desktop's `DownloadButton` in `transport/download-button.tsx`).
enum PlayerDownloadState: Equatable, Sendable {
    /// Nothing saved yet: the control offers to start.
    case start
    /// Downloading, or paused; `fraction` is nil until the server reports a size.
    case downloading(fraction: Double?, paused: Bool)
    case saved
    case failed
}

/// The title and episode a download of the playing source is filed under.
struct PlayerDownloadContext {
    let media: Media
    let episode: Episode?
}

/// Rules for downloading the video that is playing, as Desktop's `useVideoDownload` does with the playing URL.
/// iPhone has Downloads but no local torrent engine, so only a source that already resolved to a plain http(s) file qualifies.
enum PlayerDownloadPolicy {
    /// The media types the picker's own Download button accepts.
    static let downloadableTypes: Set<String> = ["movie", "series", "anime", "music"]

    /// `DownloadManager` refuses anything but a plain http(s) file: local files, playlists (HLS and DASH) and live links stay out.
    static func canDownload(url: String) -> Bool {
        guard let parsed = URL(string: url), let scheme = parsed.scheme?.lowercased() else { return false }
        guard scheme == "http" || scheme == "https" else { return false }
        let ext = parsed.pathExtension.lowercased()
        return ext != "m3u8" && ext != "mpd"
    }

    /// The media and episode to file the download under, or nil when the control must stay hidden: no signed-in downloads owner,
    /// a title type that is not downloadable, a source that cannot be saved, or an episode the title does not list.
    static func context(media: Media?, target: ResumeTarget, owner: String?, url: String) -> PlayerDownloadContext? {
        guard let owner = owner, !owner.isEmpty, let media = media else { return nil }
        guard downloadableTypes.contains(media.type), media.id == target.id, canDownload(url: url) else { return nil }
        if media.episodic {
            let episodes: [Episode] = media.videos ?? []
            guard let episode = episodes.first(where: { $0.belongs(to: target) }) else { return nil }
            return PlayerDownloadContext(media: media, episode: episode)
        }
        return PlayerDownloadContext(media: media, episode: nil)
    }

    private static func rank(_ status: DownloadStatus) -> Int {
        switch status {
        case .downloading, .paused: return 0
        case .complete: return 1
        case .failed: return 2
        }
    }

    /// The download of this title or episode that matters most: one in progress, then a saved one, then a failed one; newest first.
    static func latest(in items: [DownloadItem], mediaID: String, videoID: String?) -> DownloadItem? {
        let matches = items.filter { $0.media.id == mediaID && $0.target.videoId == videoID }
        let ordered = matches.sorted { left, right in
            if rank(left.status) != rank(right.status) { return rank(left.status) < rank(right.status) }
            return left.started > right.started
        }
        return ordered.first
    }

    static func state(for item: DownloadItem?) -> PlayerDownloadState {
        guard let item = item else { return .start }
        switch item.status {
        case .downloading: return .downloading(fraction: item.fraction, paused: false)
        case .paused: return .downloading(fraction: item.fraction, paused: true)
        case .complete: return .saved
        case .failed: return .failed
        }
    }

    /// The torrent a debrid download came from, so a saved copy can later stand in for it (`DownloadManager.completedSource`).
    static func torrentIdentity(infoHash: String?, fileIdx: Int?) -> DownloadTorrentIdentity? {
        guard let hash = infoHash, !hash.isEmpty else { return nil }
        var fields: [String: JSONValue] = ["infoHash": .string(hash)]
        if let index = fileIdx { fields["fileIdx"] = .integer(Int64(index)) }
        return DownloadTorrentIdentity(.object(fields))
    }
}

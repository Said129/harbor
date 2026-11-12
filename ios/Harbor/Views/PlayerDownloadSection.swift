import SwiftUI

/// Desktop's in-player Download control, as a section of the player's options. It saves the video that is playing through
/// `DownloadManager`, the same place the picker's Download button uses. It stays out of sight for local files, playlists and live links.
struct PlayerDownloadSection: View {
    let session: PlaybackSession
    let media: Media?
    @AppStorage("downloadsCellular") private var cellular = false
    @State private var message: String?

    private var context: PlayerDownloadContext? {
        PlayerDownloadPolicy.context(media: session.media ?? media, target: session.target, owner: session.personalOwner, url: session.source.url)
    }

    var body: some View {
        if let context = context, let owner = session.personalOwner {
            let item = PlayerDownloadPolicy.latest(in: DownloadManager.shared.list(owner: owner), mediaID: context.media.id, videoID: context.episode?.id)
            HarborSettingsSection("Download") {
                control(for: PlayerDownloadPolicy.state(for: item), item: item, context: context, owner: owner)
                if let message = message {
                    Text(message).font(HarborTheme.font(13)).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    @ViewBuilder private func control(for state: PlayerDownloadState, item: DownloadItem?, context: PlayerDownloadContext, owner: String) -> some View {
        switch state {
        case .start, .failed:
            VStack(alignment: .leading, spacing: 8) {
                if state == .failed, let note = item?.message {
                    Text(note).font(HarborTheme.font(13)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Button { start(context, owner: owner) } label: {
                    Label(DesktopInterfaceText.value("Download"), image: "stream-download").font(HarborTheme.font(15, weight: .semibold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                }.accessibilityIdentifier("player-download-start")
            }
        case .downloading(let fraction, let paused):
            VStack(alignment: .leading, spacing: 8) {
                if let fraction = fraction {
                    ProgressView(value: fraction)
                } else {
                    ProgressView()
                }
                HStack {
                    Text(progressText(fraction: fraction, paused: paused)).font(HarborTheme.font(13)).foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    if let item = item {
                        Button(DesktopInterfaceText.value("Cancel")) { DownloadManager.shared.remove(item, owner: owner) }
                            .frame(minHeight: 44).accessibilityIdentifier("player-download-cancel")
                    }
                }
            }
        case .saved:
            Label(DesktopInterfaceText.value("Saved"), image: "music-check").font(HarborTheme.font(15, weight: .semibold))
                .frame(minHeight: 44).accessibilityIdentifier("player-download-saved")
        }
    }

    private func progressText(fraction: Double?, paused: Bool) -> String {
        let status = paused ? DownloadStatus.paused.title : DownloadStatus.downloading.title
        guard let fraction = fraction else { return status }
        return status + " " + String(Int((fraction * 100).rounded())) + "%"
    }

    private func start(_ context: PlayerDownloadContext, owner: String) {
        let torrent = PlayerDownloadPolicy.torrentIdentity(infoHash: session.adSkipStream?.infoHash, fileIdx: session.adSkipStream?.fileIdx)
        do {
            try DownloadManager.shared.start(source: session.source, media: context.media, episode: context.episode, owner: owner, cellular: cellular, torrent: torrent)
            message = DesktopInterfaceText.value("Download started")
        } catch {
            message = safeMessage(error)
        }
    }
}

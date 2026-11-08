import SwiftUI

/// Desktop's episode row progress line (`series-episode-row.tsx`): "Watched {ago}" or "{pct}% watched · {ago}".
struct EpisodeProgressLine: View {
    let progress: EpisodeRowProgress.Value

    var body: some View {
        let ago = EpisodeRowProgress.relativeWatched(progress.startedAt) { DesktopInterfaceText.value($0, variables: $1) }
        if let line = EpisodeRowProgress.statusText(progress, ago: ago, text: { DesktopInterfaceText.value($0, variables: $1) }) {
            Text(line).font(.caption).foregroundStyle(progress.watched ? Color.green : HarborTheme.accent)
        }
    }
}

/// Desktop's 3-point progress bar along the bottom of an episode still. Hidden below 1% watched.
struct EpisodeProgressBar: View {
    let ratio: Double

    var body: some View {
        if ratio > 0.01 {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Rectangle().fill(Color.black.opacity(0.55))
                    Rectangle().fill(HarborTheme.accent).frame(width: proxy.size.width * EpisodeRowProgress.barFraction(ratio))
                }
            }
            .frame(height: 3)
        }
    }
}

import SwiftUI

/// The live progress of one active download: a bar, what has arrived, the speed, and a hint when the source stays silent.
/// The same block sits in the Downloads list, the player's Download section and the stream picker.
struct DownloadProgressBlock: View {
    let item: DownloadItem
    private let downloads = DownloadManager.shared

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let info = DownloadProgressPresentation.make(item: item, bytesPerSecond: downloads.speeds[item.id], now: context.date)
            VStack(alignment: .leading, spacing: 6) {
                if let fraction = info.fraction {
                    ProgressView(value: fraction)
                } else {
                    ProgressView().progressViewStyle(.linear)
                }
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(info.headline).font(.caption.weight(.semibold))
                    Spacer(minLength: 8)
                    if !info.detail.isEmpty { Text(info.detail).font(.caption).monospacedDigit().foregroundStyle(.secondary).multilineTextAlignment(.trailing) }
                }
                if let hint = info.hint {
                    Text(hint).font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                }
            }.accessibilityElement(children: .combine).accessibilityIdentifier("download-progress")
        }
    }
}

/// A slim bar above the bottom edge while something is downloading, so a download started from a title page can be followed
/// from anywhere. Tapping it opens Downloads.
struct DownloadsActivityBar: View {
    let owner: String
    let open: () -> Void
    private let downloads = DownloadManager.shared

    var body: some View {
        let active = downloads.list(owner: owner).filter { $0.status.isActive }
        if let first = active.first {
            let info = DownloadProgressPresentation.make(item: first, bytesPerSecond: downloads.speeds[first.id])
            let title = active.count > 1 ? "\(active.count) descargas activas" : first.title
            Button(action: open) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 8) {
                        Image("nav-download").resizable().scaledToFit().frame(width: 16, height: 16).accessibilityHidden(true)
                        Text(title).font(.caption.weight(.semibold)).lineLimit(1)
                        Spacer(minLength: 8)
                        Text(info.fraction.map { String(Int(($0 * 100).rounded())) + " %" } ?? info.headline).font(.caption).monospacedDigit().foregroundStyle(.secondary)
                    }
                    if let fraction = info.fraction { ProgressView(value: fraction) } else { ProgressView().progressViewStyle(.linear) }
                }.padding(.horizontal, 14).padding(.vertical, 8).frame(minHeight: 44).contentShape(Rectangle())
            }.buttonStyle(.plain).background(HarborTheme.surface)
                .accessibilityLabel(title + ", " + info.headline).accessibilityHint("Abre Descargas")
                .accessibilityIdentifier("downloads-activity-bar")
        }
    }
}

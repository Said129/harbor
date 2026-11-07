import SwiftUI

/// The resolution and HDR line under the player title (Desktop's `QualityInfo`), drawn when "Show stream quality under the
/// title" is on, as a text bar or as chips (`qualityBadgeStyle`). The labels come from the decoded picture size and mpv's
/// `video-params/gamma`; the rules are in `QualityBadgePolicy`.
struct PlayerQualityInfoLine: View {
    let state: PlayerState

    private var labels: [String] {
        QualityBadgePolicy.infoLabels(width: state.videoWidth, height: state.videoHeight, gamma: state.hdrGamma)
    }

    var body: some View {
        if StreamPreferences.shared.showQualityInfo, !labels.isEmpty {
            if QualityBadgeStyle.restored(StreamPreferences.shared.qualityBadgeStyle) == .chips {
                HStack(spacing: 4) {
                    ForEach(labels, id: \.self) { label in
                        let highlighted = QualityBadgePolicy.isHighlighted(label)
                        Text(label).font(.system(size: 10, weight: .bold))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(highlighted ? Color.yellow.opacity(0.9) : Color.white.opacity(0.18), in: .capsule)
                            .foregroundStyle(highlighted ? Color.black : Color.white)
                    }
                }
                .accessibilityElement(children: .combine).accessibilityIdentifier("player-quality-info")
            } else {
                Text(labels.joined(separator: " · ")).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                    .accessibilityIdentifier("player-quality-info")
            }
        }
    }
}

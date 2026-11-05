import SwiftUI

/// Desktop's subtitle sync indicator (`lib/player/subtitle-offset.ts`, `components/player/subtitle-offset-indicator.tsx`):
/// the current subtitle delay, shown on the picture for a moment whenever it is nudged.
enum SubtitleOffset {
    /// How long the indicator stays after a change (Desktop uses 1.8 s).
    static let visibleMilliseconds = 1_800

    /// `+500 ms`, `-250 ms`, `0 ms`: whole milliseconds with a plus sign for a positive delay.
    static func format(_ delaySeconds: Double) -> String {
        guard delaySeconds.isFinite else { return "0 ms" }
        let milliseconds = Int((delaySeconds * 1_000 + 0.5).rounded(.down))
        return (milliseconds > 0 ? "+" : "") + "\(milliseconds) ms"
    }
}

enum SubtitleOffsetPosition: String, CaseIterable, Sendable {
    case topLeft = "top-left", top, topRight = "top-right", left, center, right
    case bottomLeft = "bottom-left", bottom, bottomRight = "bottom-right"

    /// Desktop's `sanitizeSubtitleOffsetPosition`: anything unknown means the bottom.
    static func sanitized(_ raw: String) -> SubtitleOffsetPosition { SubtitleOffsetPosition(rawValue: raw) ?? .bottom }

    var label: String {
        switch self {
        case .topLeft: "Top left"
        case .top: "Top"
        case .topRight: "Top right"
        case .left: "Left"
        case .center: "Center"
        case .right: "Right"
        case .bottomLeft: "Bottom left"
        case .bottom: "Bottom"
        case .bottomRight: "Bottom right"
        }
    }
    var alignment: Alignment {
        switch self {
        case .topLeft: .topLeading
        case .top: .top
        case .topRight: .topTrailing
        case .left: .leading
        case .center: .center
        case .right: .trailing
        case .bottomLeft: .bottomLeading
        case .bottom: .bottom
        case .bottomRight: .bottomTrailing
        }
    }
    var isTop: Bool { [.topLeft, .top, .topRight].contains(self) }
    var isBottom: Bool { [.bottomLeft, .bottom, .bottomRight].contains(self) }
}

enum SubtitleOffsetSize: String, CaseIterable, Sendable {
    case small, medium, large

    /// Desktop's `sanitizeSubtitleOffsetSize`: anything but small or large means the default.
    static func sanitized(_ raw: String) -> SubtitleOffsetSize { raw == "small" || raw == "large" ? SubtitleOffsetSize(rawValue: raw) ?? .medium : .medium }

    var label: String {
        switch self {
        case .small: "Smaller"
        case .medium: "Default"
        case .large: "Larger"
        }
    }
    var text: CGFloat {
        switch self {
        case .small: 11.5
        case .medium: 13
        case .large: 15
        }
    }
    var icon: CGFloat {
        switch self {
        case .small: 14
        case .medium: 17
        case .large: 20
        }
    }
    var spacing: CGFloat {
        switch self {
        case .small: 8
        case .medium: 10
        case .large: 12
        }
    }
    var valueWidth: CGFloat {
        switch self {
        case .small: 56
        case .medium: 64
        case .large: 80
        }
    }
}

struct SubtitleOffsetIndicator: View {
    /// The delay to show, or nil while nothing was changed.
    let delay: Double?
    let position: SubtitleOffsetPosition
    let size: SubtitleOffsetSize

    var body: some View {
        let visible = delay != nil
        HStack(spacing: size.spacing) {
            Image(systemName: "captions.bubble").font(.system(size: size.icon)).foregroundStyle(.white.opacity(0.8))
            Text(DesktopInterfaceText.value("Subtitle sync")).font(.system(size: size.text, weight: .medium)).foregroundStyle(.white.opacity(0.75))
            Rectangle().fill(.white.opacity(0.35)).frame(width: 1, height: size.text)
            Text(SubtitleOffset.format(delay ?? 0)).font(.system(size: size.text, weight: .semibold)).monospacedDigit().foregroundStyle(.white)
                .frame(minWidth: size.valueWidth)
        }
        .shadow(color: .black.opacity(0.9), radius: 3, y: 1)
        .opacity(visible ? 1 : 0).offset(y: visible ? 0 : 8)
        .animation(.easeOut(duration: 0.15), value: visible)
        .padding(.top, position.isTop ? 64 : 0).padding(.bottom, position.isBottom ? 120 : 0).padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: position.alignment)
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine).accessibilityHidden(!visible)
        .accessibilityIdentifier("subtitle-offset-indicator")
    }
}

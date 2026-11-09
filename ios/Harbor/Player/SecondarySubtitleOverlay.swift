import SwiftUI

struct SecondarySubtitleOverlay: View {
    let state: PlayerState
    let options: PlaybackOptions
    private let preferences = SubtitleSelectionPreferences.shared

    var body: some View {
        if state.loaded, !state.seeking, !state.ended, !state.restarting, state.error == nil,
           !state.pictureInPictureActive, !state.pictureInPictureChanging,
           state.secondarySubtitle != nil, !state.secondarySubtitleText.isEmpty {
            GeometryReader { geometry in
                let horizontal = horizontalAlignment
                let atTop = options.secondarySubtitlePlacement == "top"
                let viewport = geometry.size
                // Match the primary track's mpv/libass size, expressed relative to 720 points.
                let responsiveScale = viewport.height / 720
                let baseSize = min(120, max(16, options.subtitleSize))
                let primarySize = max(1, CGFloat(baseSize) * responsiveScale)
                let secondarySize = max(1, primarySize * CGFloat(Self.scale(preferences.subSecondaryScale)))
                let marginFraction = min(1, max(0, (100 - options.subtitlePosition) / 100))
                let margin = viewport.height * CGFloat(marginFraction)

                VStack(alignment: horizontal, spacing: max(2, 6 * responsiveScale)) {
                    SubtitleStyledText(text: state.secondarySubtitleText, options: options, size: secondarySize, styleScale: responsiveScale)
                    if !atTop, !state.primarySubtitleText.isEmpty {
                        // Reserve the height of the wrapped primary cue that mpv draws.
                        SubtitleStyledText(text: state.primarySubtitleText, options: options, size: primarySize, styleScale: responsiveScale)
                            .hidden()
                    }
                }
                .frame(maxWidth: viewport.width * 0.8, alignment: Alignment(horizontal: horizontal, vertical: .center))
                .padding(.horizontal, viewport.width * 0.06)
                .padding(atTop ? .top : .bottom, margin)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: Alignment(horizontal: horizontal, vertical: atTop ? .top : .bottom))
            }
            .environment(\.layoutDirection, .leftToRight)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    private var horizontalAlignment: HorizontalAlignment {
        switch options.subtitleAlignment {
        case "left": .leading
        case "right": .trailing
        default: .center
        }
    }

    static func scale(_ value: Double) -> Double {
        value.isFinite ? min(1.4, max(0.4, value)) : 0.85
    }
}

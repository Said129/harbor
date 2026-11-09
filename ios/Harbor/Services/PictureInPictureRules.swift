import Foundation

/// Pure Picture in Picture rules for the iOS player.
enum PictureInPictureRules {
    /// Desktop's `subShowInPip` (`views/player/stage-overlays.tsx`): subtitles stay visible in the
    /// small floating window only while the setting is on. Inline playback uses
    /// mpv unless the player draws that track in its own view.
    static func subtitleVisibility(inPictureInPicture: Bool, showSubtitlesInPip: Bool, hasInlineOverlay: Bool = false) -> String {
        (inPictureInPicture ? showSubtitlesInPip : !hasInlineOverlay) ? "yes" : "no"
    }
}

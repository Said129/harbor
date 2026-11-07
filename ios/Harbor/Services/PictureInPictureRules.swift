import Foundation

/// Pure Picture in Picture rules for the iOS player.
enum PictureInPictureRules {
    /// Desktop's `subShowInPip` (`views/player/stage-overlays.tsx`): subtitles stay visible in the
    /// small floating window only while the setting is on. Inline playback always shows them.
    /// The value is the mpv `sub-visibility` (and `secondary-sub-visibility`) property.
    static func subtitleVisibility(inPictureInPicture: Bool, showSubtitlesInPip: Bool) -> String {
        inPictureInPicture && !showSubtitlesInPip ? "no" : "yes"
    }
}

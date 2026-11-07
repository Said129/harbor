import Foundation

/// Maps mpv tracks onto the policy inputs in `SubtitleSelectionPolicy.swift`.
extension PlayerState.Track {
    /// The policy input for this track. `externalPrepared` is true for an external file only after mpv has loaded it, which is how iOS adds them (`MPVController.loadAddonSubtitle`). The `title` is mpv's raw title, not the composed `label`.
    func subtitleSelectionCandidate(externalPrepared: Bool = true) -> SubtitleSelectionCandidate {
        SubtitleSelectionCandidate(
            id: id,
            language: language,
            title: title,
            forced: forced,
            hearingImpaired: hearingImpaired,
            external: external,
            codec: codec,
            isDefault: defaultTrack,
            matchScore: 0,
            matchLevel: .low,
            timing: .notChecked,
            prepared: externalPrepared)
    }
}

extension Array where Element == PlayerState.Track {
    /// Subtitle tracks that can be selected as text. Image subtitles (PGS, VobSub) are left out, as `SubtitleLanguages.preferredSecondary` also does.
    var subtitleSelectionCandidates: [SubtitleSelectionCandidate] {
        filter { $0.type == "sub" && !$0.isImageSubtitle }.map { $0.subtitleSelectionCandidate() }
    }
}

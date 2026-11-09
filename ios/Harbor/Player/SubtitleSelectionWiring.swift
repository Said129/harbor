import Foundation

/// Pure decisions that connect the subtitle selection settings to `MPVController`. They reuse `SubtitleSelectionPolicy` and `AssSizeNormalization` and touch neither mpv nor UserDefaults.
enum SubtitleSelectionWiring {
    enum ForcedChoice: Equatable, Sendable {
        case off
        case track(Int)
    }

    static func forcedChoice(candidates: [SubtitleSelectionCandidate], audioLanguage: String?,
                             context: SubtitleAutoSelectionContext) -> ForcedChoice? {
        guard !context.suppressed, !context.languages.isEmpty, let audioLanguage,
              SubtitleSelectionPolicy.languageScore(audioLanguage, preferred: context.languages) >= 0,
              SubtitleSelectionPolicy.replacementAllowed(origin: context.origin, autoUpgrade: context.autoUpgrade, lateArrival: false) else { return nil }

        var best: SubtitleSelectionCandidate?
        var bestScore = Int.min
        for track in candidates where track.forced || SubtitleSelectionPolicy.hasForcedWord(track.title) {
            guard SubtitleSelectionPolicy.isAutoSelectable(track) else { continue }
            let score = SubtitleSelectionPolicy.languageScore(track.language, preferred: context.languages)
            if score > bestScore {
                best = track
                bestScore = score
            }
        }
        return best.map { .track($0.id) } ?? .off
    }

    /// The subtitle Harbor should select now, or nil to leave mpv's choice alone. `previous` is the candidate list from the last track update, which tells a late arrival apart from the first list. Desktop `use-track-autoload.ts:838-863` and `autoload-run.ts:36-43`.
    static func subtitleChoice(candidates: [SubtitleSelectionCandidate], previous: [SubtitleSelectionCandidate], currentID: Int?, context: SubtitleAutoSelectionContext) -> Int? {
        guard !context.suppressed, !context.languages.isEmpty else { return nil }
        // With every related setting off and nothing blocked, mpv's own choice stays exactly as it was.
        let words = SubtitleSelectionPolicy.normalizedBlockWords(context.blockWords)
        let current = candidates.first(where: { $0.id == currentID })
        let currentBlocked = current.map { SubtitleSelectionPolicy.isBlocked($0, words: words) } ?? false
        guard currentBlocked || context.preferEmbedded || context.autoUpgrade else { return nil }
        let knownIDs = Set(previous.map(\.id))
        let lateArrival = !previous.isEmpty && candidates.contains { !knownIDs.contains($0.id) }
        if lateArrival, !SubtitleSelectionPolicy.allowsExternalArrival(existing: previous, lateArrival: true, context: context) {
            return nil
        }
        guard let desired = SubtitleSelectionPolicy.trackToAutoSelect(among: candidates, context: context) else { return nil }
        return desired.id == currentID ? nil : desired.id
    }

    /// The audio track to switch to when the one mpv picked matches a block word. Desktop `use-track-autoload.ts:801-816`: `allow` filters the list, then `pickBestTrack` (`language.ts:377-395`) chooses. A track the person picked is never changed.
    static func audioChoice(candidates: [SubtitleSelectionCandidate], currentID: Int?, languages: [String], blockWords: [String], userPicked: Bool) -> Int? {
        guard !userPicked, !languages.isEmpty else { return nil }
        let words = SubtitleSelectionPolicy.normalizedBlockWords(blockWords)
        guard !words.isEmpty, let current = candidates.first(where: { $0.id == currentID }),
              SubtitleSelectionPolicy.isBlocked(current, words: words) else { return nil }
        var best: SubtitleSelectionCandidate?
        var bestScore = Int.min
        for candidate in SubtitleSelectionPolicy.allowed(candidates, blockWords: blockWords) where !candidate.forced {
            let language = SubtitleSelectionPolicy.languageScore(candidate.language, preferred: languages)
            guard language >= 0 else { continue }
            let score = language * 10 + (candidate.isDefault ? 1 : 0)
            if score > bestScore {
                bestScore = score
                best = candidate
            }
        }
        guard let chosen = best, chosen.id != currentID else { return nil }
        return chosen.id
    }

    /// Whether mpv's selected track is ASS or SSA (`sub-format.ts`), using the codec or the external file name.
    static func isASSSelection(_ track: PlayerState.Track) -> Bool {
        AssSizeNormalization.isASSTrack(codec: track.codec, title: track.externalFilename)
    }

    /// The `sub-scale` for an ASS file whose text is `assText`, or nil when mpv keeps its own scale. Desktop `use-player-media.ts:229-231` and `sub-style.ts:79-95`.
    static func assSubScale(normalizeSize: Bool, assOverride: String, selectedIsASS: Bool, assText: String?, targetFontSize: Double) -> Double? {
        let active = AssSizeNormalization.isActive(normalizeSize: normalizeSize, assOverride: assOverride, selectedIsASS: selectedIsASS)
        guard active, let text = assText else { return nil }
        return AssSizeNormalization.mpvSubScale(active: true, baseFactor: AssSizeNormalization.baseFactor(assText: text), targetFontSize: targetFontSize)
    }

    /// `sub-ass-override` while a normalised scale is in use (`sub-style.ts:81`): "scale"; otherwise the person's own choice.
    static func assOverride(scaled: Bool, userOverride: String) -> String {
        scaled ? "scale" : userOverride
    }

    /// A local file for an mpv external track name, which is a path or a `file://` URL. Remote URLs (for example addon sources) return nil: Desktop fetches them, iOS does not yet.
    static func localFileURL(_ filename: String) -> URL? {
        guard !filename.isEmpty else { return nil }
        if filename.hasPrefix("file://") { return URL(string: filename) }
        if filename.contains("://") { return nil }
        return URL(fileURLWithPath: filename)
    }
}

extension Array where Element == PlayerState.Track {
    /// Audio tracks as policy candidates, for `SubtitleSelectionWiring.audioChoice`.
    var audioSelectionCandidates: [SubtitleSelectionCandidate] {
        filter { $0.type == "audio" }.map { $0.subtitleSelectionCandidate() }
    }
}

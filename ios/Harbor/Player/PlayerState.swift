import Foundation
import Observation

@MainActor @Observable
final class PlayerState {
    var position: Double = 0
    var hasPosition = false
    var duration: Double = 0
    var paused = false
    var buffering = false
    var loaded = false
    var mediaGeneration = 0
    var renderReady = false
    var renderCalls = 0
    var ended = false
    var endedNaturally = false
    var restarting = false
    var error: String?
    var playbackIssue: String?
    var tracks: [Track] = []
    var chapters: [Chapter] = []
    var speed = 1.0
    /// Where the read-ahead cache ends on the video timeline (mpv `demuxer-cache-time`), when mpv reports it.
    var cacheEnd: Double?
    /// Desktop's A-B loop for this video; a new video starts a new state.
    var abLoop = ABLoop()
    var volume = 100.0
    var muted = false
    var audioOutput = ""
    var wirelessAudio = false
    var choosingAudioRoute = false
    var pictureInPictureSupported = false
    var pictureInPictureActive = false
    var pictureInPictureChanging = false
    var videoWidth = 0
    var videoHeight = 0
    /// mpv's `video-params/gamma` ("pq" and "hlg" are HDR); empty when mpv reports none.
    var hdrGamma = ""
    var audioDelay = 0.0
    var subtitleDelay = 0.0
    var subtitleFPS: Double?
    var estimatedVideoFPS: Double?
    var containerVideoFPS: Double?
    var subtitleChanging = false
    var subtitleIssue: String?
    var importedSubtitleIDs: Set<Int> = []
    var subtitleImportMessage: String?
    var addonSubtitles: [PlaybackSource.Subtitle] = []
    var addonSubtitlesLoading = false
    var addonSubtitlesMessage: String?
    var addonSubtitlesRetry = 0
    var canSearchAddonSubtitles = false
    var addonSubtitleTracks: [String: Int] = [:]
    var addonSubtitleDownloading = false
    func addonSubtitleSelected(_ subtitle: PlaybackSource.Subtitle) -> Bool {
        guard let trackID = addonSubtitleTracks[subtitle.url] else { return false }
        return primarySubtitle?.id == trackID
    }
    var subtitleSyncing = false
    var subtitleSyncMessage: String?
    var subtitleSyncPhase = SubtitleSyncPhase.idle
    var subtitleSyncRevision = 0
    func updateSubtitleSync(_ phase: SubtitleSyncPhase, message: String? = nil) {
        subtitleSyncPhase = phase; subtitleSyncMessage = message; subtitleSyncRevision += 1
    }
    var subtitleSyncOriginal: Int?
    var primarySubtitleText = ""
    var secondarySubtitleText = ""
    var videoFPS: Double? { estimatedVideoFPS ?? containerVideoFPS }
    var primarySubtitle: Track? { tracks.first { $0.type == "sub" && $0.mainSelection == 0 } }
    var secondarySubtitle: Track? { tracks.first { $0.type == "sub" && $0.mainSelection == 1 } }
    weak var controller: MPVController?
    struct Track: Identifiable, Sendable {
        let id: Int
        let type: String
        let label: String
        let selected: Bool
        var codec = ""
        var language = ""
        var title = ""
        var externalFilename = ""
        var mainSelection: Int? = nil
        var external = false
        var forced = false
        var hearingImpaired = false
        var defaultTrack = false
        var channels = ""
    }
    struct Chapter: Identifiable, Equatable, Sendable {
        let id: Int
        let title: String
        let time: Double
    }
}

/// Desktop's hide-SDH gate: `sdhFilterAllowed` in `use-player-media.ts` with `sdhSafeForLanguage` from `lib/subtitles/sdh-filter.ts`.
enum SubtitleSDHGate {
    /// Desktop's `NON_LATIN_LANGS`, by primary language subtag.
    private static let nonLatinLanguages = Set([
        "ar", "arb", "he", "heb", "iw", "fa", "per", "fas", "ur", "urd",
        "ru", "rus", "uk", "ukr", "bg", "bul", "sr", "srp", "mk", "mkd", "be", "bel",
        "el", "gre", "ell", "hy", "hye", "ka", "kat", "th", "tha", "km", "khm", "lo", "lao",
        "ja", "jpn", "zh", "zho", "chi", "yue", "ko", "kor",
        "hi", "hin", "bn", "ben", "ta", "tam", "te", "tel", "ml", "mal", "kn", "kan",
        "mr", "mar", "gu", "guj", "pa", "pan", "si", "sin", "am", "amh", "yi", "yid",
    ])

    /// Hide-SDH is sent only for a track that is not forced, not foreign-only and in a language outside the non-Latin list.
    static func allows(forced: Bool, foreignOnly: Bool, language: String?) -> Bool {
        !forced && !foreignOnly && languageAllows(language)
    }

    static func languageAllows(_ language: String?) -> Bool {
        guard let language = language, !language.isEmpty else { return true }
        let primary = language.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            .components(separatedBy: CharacterSet(charactersIn: "-_")).first ?? ""
        return !nonLatinLanguages.contains(primary)
    }
}

/// Desktop's `lib/player/playback-end.ts`: an end before 85 percent of a known duration is truncated, not natural.
enum PlaybackEndRule {
    static func isNaturalEnd(position: Double, duration: Double) -> Bool {
        guard duration.isFinite, duration > 0 else { return true }
        return position / duration >= 0.85
    }

    static func isTruncatedEnd(position: Double, duration: Double) -> Bool {
        !isNaturalEnd(position: position, duration: duration)
    }
}

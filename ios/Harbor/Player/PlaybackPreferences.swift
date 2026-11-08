import Foundation
import Observation

enum VideoFit: String, CaseIterable, Identifiable, Codable {
    case original, fill, stretch, zoom, widescreen, classic, ultrawide, cinema, scope
    var id: String { rawValue }
    var title: String {
        switch self {
        case .original: DesktopInterfaceText.value("Fit")
        case .fill: DesktopInterfaceText.value("Fill")
        case .stretch: DesktopInterfaceText.value("Stretch")
        case .zoom: "Zoom"
        case .widescreen: "16:9"
        case .classic: "4:3"
        case .ultrawide: "21:9"
        case .cinema: "1.85:1"
        case .scope: "2.39:1"
        }
    }
    var aspect: String {
        switch self {
        case .widescreen: "16:9"
        case .classic: "4:3"
        case .ultrawide: "21:9"
        case .cinema: "1.85:1"
        case .scope: "2.39:1"
        default: "no"
        }
    }
}

enum PicturePreset: String, CaseIterable, Identifiable {
    case brighten, punchier, easy, crisp
    var id: String { rawValue }
    var title: String {
        let original = switch self {
        case .brighten: "Brighten dark movies"
        case .punchier: "Punchier color"
        case .easy: "Easy on the eyes"
        case .crisp: "Crisp (anime & cartoons)"
        }
        return DesktopInterfaceText.value(original)
    }
    var description: String {
        let original = switch self {
        case .brighten: "Lifts shadows so the pitch-black scenes are actually watchable."
        case .punchier: "Richer, more vivid picture with a touch more contrast."
        case .easy: "Softer and dimmer, kinder for late-night watching."
        case .crisp: "Sharper lines and a little more pop."
        }
        return DesktopInterfaceText.value(original)
    }
    var values: (brightness: Double, contrast: Double, saturation: Double, gamma: Double, sharpen: Double) {
        switch self {
        case .brighten: (4, 0, 0, 12, 0)
        case .punchier: (0, 8, 15, 0, 0)
        case .easy: (-4, 0, -5, -6, 0)
        case .crisp: (0, 0, 8, 0, 0.6)
        }
    }
}

/// Desktop's sound profiles (`AUDIO_PROFILE_AF` in `lib/player/mpv.ts`).
enum AudioProfile: String, CaseIterable, Sendable {
    case off, bass, voice, bassReduce = "bass-reduce", night

    var filter: String? {
        switch self {
        case .off: nil
        case .bass: "lavfi=[bass=g=7:f=110:w=0.6]"
        case .voice: "lavfi=[equalizer=f=300:t=q:w=1:g=-3,equalizer=f=2800:t=q:w=1:g=5]"
        case .bassReduce: "lavfi=[bass=g=-8:f=110:w=0.6]"
        case .night: "lavfi=[acompressor=ratio=3:threshold=-20dB:attack=20:release=300:makeup=4dB]"
        }
    }
    var label: String {
        switch self {
        case .off: DesktopInterfaceText.value("Flat")
        case .bass: DesktopInterfaceText.value("Bass boost")
        case .voice: DesktopInterfaceText.value("Vocal clarity")
        case .bassReduce: DesktopInterfaceText.value("Less bass")
        case .night: DesktopInterfaceText.value("Night mode")
        }
    }
}

/// Persisted native equivalents of Desktop's player/subtitle options. The mpv
/// event stream remains authoritative for the running player's transport state.
struct PlaybackOptions: Codable, Equatable {
    var autoHideControls = true
    /// Desktop's `subOffsetIndicator*`: show the subtitle delay on the picture while it is nudged, where and how large.
    var subOffsetIndicator = true
    var subOffsetPosition = SubtitleOffsetPosition.bottom.rawValue
    var subOffsetSize = SubtitleOffsetSize.medium.rawValue
    /// Desktop's `subShowInPip`: keep subtitles on the floating Picture in Picture window. Off hides them there only.
    var subShowInPip = true
    /// Desktop's playback stats card, which its hotkey I shows and hides.
    var showStats = false
    /// Desktop's `audioNormalize`: a dynamic loudness normalizer.
    var audioNormalize = false
    /// Desktop's `audioProfile`: one of `AudioProfile`'s raw values.
    var audioProfile = AudioProfile.off.rawValue
    /// Desktop's `playerScreenLockEnabled`: show a lock control that blocks touches until it is unlocked.
    var screenLock = false
    var showSkipIntro = true
    /// Desktop's auto-skip: jump past a detected segment the moment it starts (intros, recaps, credits).
    var autoSkipIntro = false
    var autoSkipRecap = false
    var autoSkipOutro = false
    /// Seconds after which the Skip button hides itself; 0 keeps it for the whole segment.
    var skipButtonHideSeconds = 0.0
    var keepScreenAwake = true
    var autoPlayNextEpisode = true
    /// Desktop's "Ask if you're still watching": pause after this many episodes start by themselves.
    var stillWatching = false
    var stillWatchingAfter = 3
    var nextEpisodeLeadSeconds = -1.0
    var resumeAfterInterruption = true
    var resumeOnForeground = false
    var seekBackSeconds = 10.0
    var seekForwardSeconds = 10.0
    /// Desktop's `seekBackStepShortSec` and `seekForwardStepShortSec`: the jump on Shift plus the arrow keys.
    var seekBackShortSeconds = 3.0
    var seekForwardShortSeconds = 3.0
    /// Desktop's `playerConfirmLeave`: ask before Esc closes the player.
    var confirmLeave = true
    /// Desktop's `volumeBoostMax`: how far past 100 percent the volume may go, as a multiple.
    var volumeBoostMax = 2.0
    var speed = 1.0
    var volume = 100.0
    var fit = VideoFit.original
    var brightness = 0.0
    var contrast = 0.0
    var saturation = 0.0
    var gamma = 0.0
    var zoom = 0.0
    var sharpen = 0.0
    var audioLanguage = "eng,jpn"
    var subtitleLanguage = "eng"
    var secondarySubtitleLanguage = ""
    var secondarySubtitlePlacement = "top"
    var stereo = false
    var audioDelay = 0.0
    var subtitleDelay = 0.0
    var subtitlesOff = false
    var subtitleSize = 32.0
    var subtitlePosition = 88.0
    var subtitleBold = false
    var subtitleStyle = "shadow"
    var subtitleASS = "no"
    var subtitleAlignment = "center"
    var subtitleColor = "#FFFFFF"
    var borderColor = "#000000"
    var borderSize = 2.0
    var boxOpacity = 0.6
    var subtitleOpacity = 1.0
    var subtitleFont = "inter"
    var subtitleSpacing = 0.0
    var subtitleBoxColor = "#000000"
    var hideSDH = false
    var bufferSize = BufferSize.auto

    var subtitleFamily: String {
        switch subtitleFont {
        case "system": "Helvetica Neue"
        case "serif": "Times New Roman"
        case "rounded": "Fredoka"
        case "arabic": "Vazirmatn"
        default: "Inter"
        }
    }

    mutating func applyPicturePreset(_ preset: PicturePreset) {
        let values = preset.values
        brightness = values.brightness; contrast = values.contrast
        saturation = values.saturation; gamma = values.gamma; sharpen = values.sharpen
    }

    /// Desktop's `applyAudioFilters`: the normalizer and the sound profile, behind a limiter that keeps peaks below clipping.
    var audioFilters: String {
        var parts: [String] = []
        if audioNormalize { parts.append("dynaudnorm=f=500:g=31:p=0.9:m=4:b=1") }
        if let profile = AudioProfile(rawValue: audioProfile)?.filter { parts.append(profile) }
        if !parts.isEmpty { parts.append("lavfi=[alimiter=limit=0.97]") }
        return parts.joined(separator: ",")
    }

    /// The boost Desktop offers, 100 to 600 percent; anything else falls back to its default of 200.
    static let volumeBoostChoices: [Double] = [1, 1.5, 2, 3, 4, 6]
    var volumeBoostLimit: Double { Self.volumeBoostChoices.contains(volumeBoostMax) ? volumeBoostMax : 2 }
    /// The loudest setting in mpv's scale, where 100 is the file's own level.
    var volumeCeiling: Double { volumeBoostLimit * 100 }

    var mpvOptions: [(String, String)] {
        var options: [(String, String)] = [
            ("volume-max", String(Int(volumeCeiling))),
            ("speed", String(speed)), ("volume", String(min(volume, volumeCeiling))), ("panscan", fit == .fill ? "1" : "0"),
            ("video-aspect-override", fit.aspect), ("keepaspect", fit == .stretch ? "no" : "yes"),
            ("video-zoom", fit == .zoom ? String(zoom) : "0"), ("sharpen", String(sharpen)),
            ("brightness", String(brightness)), ("contrast", String(contrast)),
            ("saturation", String(saturation)), ("gamma", String(gamma)),
            ("alang", audioLanguage), ("slang", subtitleLanguage),
            ("audio-channels", stereo ? "stereo" : "auto-safe"),
            ("audio-delay", String(audioDelay)), ("sub-delay", String(subtitleDelay)),
            ("sid", subtitlesOff ? "no" : "auto"),
            ("secondary-sub-pos", secondarySubtitlePlacement == "top" ? "0" : String(max(0, min(100, subtitlePosition - 8)))),
            ("sub-font-size", String(subtitleSize)), ("sub-pos", String(subtitlePosition)),
            ("sub-font", subtitleFamily), ("sub-spacing", String(subtitleSpacing)),
            // Set per selected track by MPVController.applySubtitleSDHFilter, so the Desktop gate applies from the first track.
            ("sub-filter-sdh", "no"), ("sub-filter-sdh-harder", "no"),
            ("sub-bold", subtitleBold ? "yes" : "no"), ("sub-ass-override", subtitleASS),
            ("sub-align-x", subtitleAlignment), ("sub-color", Self.alphaColor(subtitleColor, opacity: subtitleOpacity)),
            ("sub-border-color", Self.alphaColor(borderColor, opacity: subtitleOpacity)), ("sub-border-size", subtitleStyle == "outline" ? String(borderSize) : "0"),
            ("sub-shadow-offset", subtitleStyle == "shadow" ? "2" : "0"),
            ("sub-border-style", subtitleStyle == "box" ? "background-box" : "outline-and-shadow"),
            ("sub-back-color", Self.alphaColor(subtitleBoxColor, opacity: subtitleStyle == "box" ? boxOpacity * subtitleOpacity : 0))
        ]
        // Left out when empty so a player without filters never asks libmpv for an audio filter chain.
        let filters = audioFilters
        if !filters.isEmpty { options.append(("af", filters)) }
        return options
    }

    private static func alphaColor(_ color: String, opacity: Double) -> String {
        // mpv accepts #AARRGGBB. Never pass malformed persisted hex to libmpv.
        let rgb = color.count == 7 && color.first == "#" && UInt32(color.dropFirst(), radix: 16) != nil ? String(color.dropFirst()) : "FFFFFF"
        return String(format: "#%02X%@", Int((min(1, max(0, opacity)) * 255).rounded()), rgb)
    }
}

@MainActor @Observable
final class PlaybackPreferences {
    static let shared = PlaybackPreferences()
    private let storage: UserDefaults
    private static let key = "iphone.player-options.v1"
    private var reloading = false
    var options: PlaybackOptions {
        didSet {
            guard !reloading else { return }
            if let data = try? JSONEncoder().encode(options) { storage.set(data, forKey: Self.key) }
        }
    }

    init(storage: UserDefaults = .standard) {
        self.storage = storage
        // Merge new defaults into the existing document instead of dropping
        // the user's saved options when a later build adds a field.
        var merged = (try? JSONSerialization.jsonObject(with: JSONEncoder().encode(PlaybackOptions()))) as? [String: Any] ?? [:]
        if let data = storage.data(forKey: Self.key), let saved = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] { merged.merge(saved) { _, saved in saved } }
        options = (try? JSONSerialization.data(withJSONObject: merged)).flatMap { try? JSONDecoder().decode(PlaybackOptions.self, from: $0) } ?? PlaybackOptions()
    }
    func reloadPreferences() {
        reloading = true; defer { reloading = false }
        options = PlaybackPreferences(storage: storage).options
    }
}

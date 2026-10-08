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

/// Persisted native equivalents of Desktop's player/subtitle options. The mpv
/// event stream remains authoritative for the running player's transport state.
struct PlaybackOptions: Codable, Equatable {
    var autoHideControls = true
    var keepScreenAwake = true
    var autoPlayNextEpisode = true
    var nextEpisodeLeadSeconds = -1.0
    var resumeAfterInterruption = true
    var resumeOnForeground = false
    var seekBackSeconds = 10.0
    var seekForwardSeconds = 10.0
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

    var mpvOptions: [(String, String)] {
        [
            ("speed", String(speed)), ("volume", String(volume)), ("panscan", fit == .fill ? "1" : "0"),
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
            ("sub-filter-sdh", hideSDH ? "yes" : "no"), ("sub-filter-sdh-harder", "no"),
            ("sub-bold", subtitleBold ? "yes" : "no"), ("sub-ass-override", subtitleASS),
            ("sub-align-x", subtitleAlignment), ("sub-color", Self.alphaColor(subtitleColor, opacity: subtitleOpacity)),
            ("sub-border-color", Self.alphaColor(borderColor, opacity: subtitleOpacity)), ("sub-border-size", subtitleStyle == "outline" ? String(borderSize) : "0"),
            ("sub-shadow-offset", subtitleStyle == "shadow" ? "2" : "0"),
            ("sub-border-style", subtitleStyle == "box" ? "background-box" : "outline-and-shadow"),
            ("sub-back-color", Self.alphaColor(subtitleBoxColor, opacity: subtitleStyle == "box" ? boxOpacity * subtitleOpacity : 0))
        ]
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
    var options: PlaybackOptions {
        didSet {
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
}

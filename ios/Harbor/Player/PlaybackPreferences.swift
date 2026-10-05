import Foundation
import Observation

enum VideoFit: String, CaseIterable, Identifiable, Codable {
    case original, fill, widescreen, classic
    var id: String { rawValue }
    var title: String {
        switch self {
        case .original: "Original"
        case .fill: "Llenar pantalla"
        case .widescreen: "16:9"
        case .classic: "4:3"
        }
    }
}

/// Persisted native equivalents of Desktop's player/subtitle options. The mpv
/// event stream remains authoritative for the running player's transport state.
struct PlaybackOptions: Codable, Equatable {
    var autoHideControls = true
    var keepScreenAwake = true
    var seekBackSeconds = 10.0
    var seekForwardSeconds = 10.0
    var speed = 1.0
    var volume = 100.0
    var fit = VideoFit.original
    var brightness = 0.0
    var contrast = 0.0
    var saturation = 0.0
    var gamma = 0.0
    var audioLanguage = "eng,jpn"
    var subtitleLanguage = "eng"
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

    var mpvOptions: [(String, String)] {
        [
            ("speed", String(speed)), ("volume", String(volume)), ("panscan", fit == .fill ? "1" : "0"),
            ("video-aspect-override", fit == .widescreen ? "16:9" : fit == .classic ? "4:3" : "no"),
            ("brightness", String(brightness)), ("contrast", String(contrast)),
            ("saturation", String(saturation)), ("gamma", String(gamma)),
            ("alang", audioLanguage), ("slang", subtitleLanguage),
            ("audio-channels", stereo ? "stereo" : "auto-safe"),
            ("audio-delay", String(audioDelay)), ("sub-delay", String(subtitleDelay)),
            ("sid", subtitlesOff ? "no" : "auto"),
            ("sub-font-size", String(subtitleSize)), ("sub-pos", String(subtitlePosition)),
            ("sub-bold", subtitleBold ? "yes" : "no"), ("sub-ass-override", subtitleASS),
            ("sub-align-x", subtitleAlignment), ("sub-color", Self.alphaColor(subtitleColor, opacity: subtitleOpacity)),
            ("sub-border-color", borderColor), ("sub-border-size", subtitleStyle == "outline" ? String(borderSize) : "0"),
            ("sub-shadow-offset", subtitleStyle == "shadow" ? "2" : "0"),
            ("sub-border-style", subtitleStyle == "box" ? "background-box" : "outline-and-shadow"),
            ("sub-back-color", Self.alphaColor("#000000", opacity: subtitleStyle == "box" ? boxOpacity : 0))
        ]
    }

    private static func alphaColor(_ color: String, opacity: Double) -> String {
        // mpv accepts #AARRGGBB; native controls only emit these known hex colors.
        String(format: "#%02X%@", Int((min(1, max(0, opacity)) * 255).rounded()), String(color.dropFirst()))
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
        options = storage.data(forKey: Self.key).flatMap { try? JSONDecoder().decode(PlaybackOptions.self, from: $0) } ?? PlaybackOptions()
    }
}

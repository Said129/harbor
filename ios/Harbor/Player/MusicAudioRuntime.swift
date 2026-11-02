import Foundation

enum MusicAudioRuntime {
    static let extendedFilters = [
        "aecho", "crossfeed", "bass", "treble", "lowpass", "highpass", "bandreject",
        "astats", "ametadata", "afade", "acrossfade", "asplit", "asetpts", "alimiter"
    ]
    static let extended = supports(extendedFilters)
    static var version: UInt32 { harbor_audio_filter_version() }

    static func supports(_ filters: [String]) -> Bool {
        filters.allSatisfy { name in name.withCString { harbor_audio_filter_available($0) } }
    }

    static func supports(_ settings: MusicAudioOptions) -> Bool {
        if settings.dspBypass { return true }
        var required: [String] = []
        if abs(settings.preampDb) >= 0.01 || settings.eqEnabled && settings.autoHeadroom { required.append("volume") }
        if abs(settings.pitch) >= 0.01 { required += ["aresample", "asetrate", "atempo"] }
        if abs(settings.balance) >= 0.001 { required += ["aformat", "pan"] }
        if settings.reverb > 0 { required.append("aecho") }
        if settings.crossfeed > 0 { required.append("crossfeed") }
        if settings.eqEnabled && settings.eqMode == "graphic" && settings.eqBands.contains(where: { abs($0) >= 0.01 }) {
            required.append("equalizer")
        }
        if settings.eqEnabled && settings.eqMode == "parametric" && settings.eqStrength > 0 {
            let names = ["peak": "equalizer", "lowShelf": "bass", "highShelf": "treble",
                         "lowPass": "lowpass", "highPass": "highpass", "notch": "bandreject"]
            for filter in settings.peqFilters where filter.enabled {
                guard let name = names[filter.type] else { return false }
                required.append(name)
            }
        }
        return supports(required)
    }

    static func supports(_ effects: MusicAudioEffects) -> Bool {
        switch effects.kind {
        case "off": true
        case "echo", "delay", "spiral": supports(["aecho"])
        case "wide": supports(["aformat", "pan"])
        default: false
        }
    }

    static func supports(_ plan: MusicAudioPlan) -> Bool {
        supports(plan.settings) && (plan.settings.dspBypass || supports(plan.effects))
    }
}

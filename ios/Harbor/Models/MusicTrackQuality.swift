import Foundation

/// Desktop's lib/music/quality.ts: a conservative display tier from the declared
/// codec, rate and depth. It is not an audibility or mastering-quality claim.
struct MusicTrackQuality: Equatable, Sendable {
    enum Tier: String, Sendable { case lossy, lossless, hiRes = "hi-res", unverified }
    let tier: Tier
    let format: String?
    let sampleRateHz: Double?
    let bitDepth: Double?
    let bitrateKbps: Double?

    init?(_ track: MusicTrack) {
        let quality = track.quality
        let codec = Self.codec(quality?.codec)
        let format = codec?.label ?? Self.localFormat(track)
        let sampleRate = Self.positive(quality?.sampleRateHz, 3_072_000)
        // Lossy decoders often use float/s32 internally. That is not source resolution.
        let declaredLossy = codec?.lossless == false || quality?.lossless == false
        let bitDepth = declaredLossy ? nil : Self.positive(quality?.bitDepth, 64)
        let bitrate = Self.positive(quality?.bitrateKbps, 100_000)
        let lossless = quality?.lossless != false && codec?.lossless != false && (codec?.lossless == true || quality?.lossless == true)
        let hiRes = lossless && (sampleRate ?? 0) > 48_000 && (bitDepth ?? 0) >= 24
        guard lossless || format != nil || bitrate != nil || sampleRate != nil else { return nil }
        tier = hiRes ? .hiRes : lossless ? .lossless : declaredLossy ? .lossy : .unverified
        self.format = format; sampleRateHz = sampleRate; self.bitDepth = bitDepth; bitrateKbps = bitrate
    }

    static func labelKey(_ tier: Tier) -> String {
        switch tier {
        case .lossy: "music.quality.lossy"
        case .lossless: "music.quality.lossless"
        case .hiRes: "music.quality.hiRes"
        case .unverified: "music.quality.unverified"
        }
    }
    static func helpKey(_ tier: Tier) -> String { "music.quality." + (tier == .hiRes ? "hiRes" : tier.rawValue) + "Help" }

    /// `Number((hz / 1000).toFixed(3))` followed by " kHz".
    static func sampleRateLabel(_ hz: Double) -> String {
        var text = String(format: "%.3f", hz / 1000)
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text + " kHz"
    }

    private static func codec(_ value: String?) -> (label: String, lossless: Bool?)? {
        guard let codec = value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !codec.isEmpty else { return nil }
        if codec.range(of: #"^pcm_(?:s|u|f)\d+(?:le|be|planar)?$"#, options: .regularExpression) != nil { return (label: "PCM", lossless: true) }
        let codecs: [String: (String, Bool?)] = [
            "flac": ("FLAC", true), "alac": ("ALAC", true), "ape": ("APE", true), "wmalossless": ("WMA", true),
            "wavpack": ("WavPack", nil), "wav": ("WAV", nil), "mp3": ("MP3", false), "aac": ("AAC", false),
            "mp4a.40.2": ("AAC", false), "mp4a.40.5": ("AAC", false), "opus": ("Opus", false), "vorbis": ("Vorbis", false)
        ]
        guard let entry = codecs[codec] else { return nil }
        return (label: entry.0, lossless: entry.1)
    }

    private static func positive(_ value: Double?, _ maximum: Double) -> Double? {
        guard let value, value.isFinite, value > 0, value <= maximum else { return nil }
        return value
    }

    /// A local extension identifies its format, not the fidelity of its contents.
    private static func localFormat(_ track: MusicTrack) -> String? {
        guard track.connectorId == "local" else { return nil }
        let formats = ["flac": "FLAC", "mp3": "MP3", "m4a": "M4A", "aac": "AAC", "ogg": "OGG", "opus": "Opus", "wav": "WAV", "wv": "WavPack"]
        for location in [track.sourceId, track.playbackUrl].compactMap({ $0 }) {
            var path = location
            if location.range(of: #"^file://"#, options: [.regularExpression, .caseInsensitive]) != nil {
                guard let url = URL(string: location) else { continue }
                path = url.path
            } else if location.range(of: #"^(?:[a-z]:[\\/]|\\\\|/(?!/))"#, options: [.regularExpression, .caseInsensitive]) == nil {
                continue
            }
            guard let match = path.range(of: #"\.[A-Za-z0-9]+$"#, options: .regularExpression) else { continue }
            if let format = formats[String(path[match].dropFirst()).lowercased()] { return format }
        }
        return nil
    }
}

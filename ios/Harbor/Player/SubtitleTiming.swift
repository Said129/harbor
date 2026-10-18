import Foundation

/// Desktop's source-FPS choices and subtitle format policy, shared by the
/// native menu and its serialized mpv operations.
enum SubtitleTiming {
    struct Preset: Identifiable, Sendable {
        let label: String
        let value: Double
        var id: String { label }
    }

    static let presets: [Preset] = [
        .init(label: "23.976", value: 24000.0 / 1001), .init(label: "24", value: 24),
        .init(label: "25", value: 25), .init(label: "29.97", value: 30000.0 / 1001),
        .init(label: "30", value: 30), .init(label: "50", value: 50),
        .init(label: "59.94", value: 60000.0 / 1001), .init(label: "60", value: 60)
    ]

    static func valid(_ value: Double) -> Bool { value.isFinite && (1...240).contains(value) }
    static func parse(_ value: String) -> Double? {
        guard let number = Double(value.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")), valid(number) else { return nil }
        return number
    }
    static func matches(_ first: Double?, _ second: Double?) -> Bool {
        guard let first, let second, first.isFinite, second.isFinite else { return false }
        return abs(first - second) < 0.001
    }
    static func format(_ value: Double?) -> String {
        guard let value, value.isFinite, value > 0 else { return "—" }
        if let preset = presets.first(where: { matches($0.value, value) }) { return preset.label }
        return value.formatted(.number.precision(.fractionLength(0...6)))
    }

    @MainActor static func unavailable(_ state: PlayerState) -> String? {
        guard state.loaded, let track = state.primarySubtitle else { return DesktopInterfaceText.value("Select a subtitle track first.") }
        guard track.isTextSubtitle else { return DesktopInterfaceText.value("Subtitle FPS conversion is only available for text-based subtitles.") }
        guard state.secondarySubtitle == nil else { return DesktopInterfaceText.value("Subtitle FPS is unavailable while a secondary subtitle is active.") }
        guard state.videoFPS != nil else { return DesktopInterfaceText.value("Video FPS is unavailable.") }
        guard state.subtitleFPS != nil else { return DesktopInterfaceText.value("Subtitle FPS is unavailable in this libmpv runtime.") }
        return nil
    }
}

extension PlayerState.Track {
    var isImageSubtitle: Bool {
        let value = codec.uppercased()
        return ["PGS", "HDMV", "DVD_SUB", "DVD SUBTITLES", "DVD SUBTITLE", "DVB", "VOBSUB", "XSUB"].contains(where: value.contains)
    }
    var isTextSubtitle: Bool {
        guard type == "sub", !isImageSubtitle else { return false }
        let value = codec.uppercased()
        if ["SUBRIP", "WEBVTT", "SUBSTATION", "SUB STATION"].contains(where: value.contains) { return true }
        if value.range(of: #"\b(?:SRT|VTT|ASS|SSA|MOV[ _-]?TEXT|TEXT(?: SUBTITLE)?)\b"#, options: .regularExpression) != nil { return true }
        return [title, externalFilename].joined(separator: " ").range(of: #"\.(?:srt|vtt|ass|ssa)(?:$|[?#\s])"#, options: [.regularExpression, .caseInsensitive]) != nil
    }
}

import Foundation

struct SubtitleDocument: Sendable {
    struct Cue: Sendable { let start: Double; let end: Double; let range: NSRange; let hours: Bool }
    let text: String
    let cues: [Cue]
    let vtt: Bool
    init(_ text: String) throws {
        self.text = text
        vtt = text.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("WEBVTT")
        let pattern = #"(?m)^((?:\d{1,3}:)?\d{2}:\d{2}[,.]\d{3})[ \t]+-->[ \t]+((?:\d{1,3}:)?\d{2}:\d{2}[,.]\d{3})"#
        let regex = try NSRegularExpression(pattern: pattern)
        let source = text as NSString
        cues = regex.matches(in: text, range: NSRange(location: 0, length: source.length)).compactMap { match in
            let first = source.substring(with: match.range(at: 1)), last = source.substring(with: match.range(at: 2))
            guard let start = Self.seconds(first), let end = Self.seconds(last), end > start else { return nil }
            return Cue(start: start, end: end, range: match.range, hours: first.filter { $0 == ":" }.count == 2)
        }
        guard cues.count >= 4, cues.count <= 100_000 else { throw HarborError(code: "subtitle-sync-format") }
    }
    private static func seconds(_ value: String) -> Double? {
        let parts = value.replacingOccurrences(of: ",", with: ".").split(separator: ":").compactMap { Double($0) }
        guard (2...3).contains(parts.count), parts.allSatisfy(\.isFinite) else { return nil }
        return parts.reversed().enumerated().reduce(0) { $0 + $1.element * pow(60, Double($1.offset)) }
    }
    func applying(_ result: SubtitleSyncResult) -> String {
        let output = NSMutableString(string: text)
        func stamp(_ time: Double, hours: Bool) -> String {
            let ms = Int((max(0, time * result.ratio + result.offset) * 1_000).rounded())
            let separator = vtt ? "." : ","
            if hours || ms >= 3_600_000 { return String(format: "%02d:%02d:%02d%@%03d", ms / 3_600_000, (ms / 60_000) % 60, (ms / 1_000) % 60, separator, ms % 1_000) }
            return String(format: "%02d:%02d%@%03d", ms / 60_000, (ms / 1_000) % 60, separator, ms % 1_000)
        }
        for cue in cues.reversed() {
            output.replaceCharacters(in: cue.range, with: stamp(cue.start, hours: cue.hours) + " --> " + stamp(cue.end, hours: cue.hours))
        }
        return output as String
    }
}

struct SubtitleSyncResult: Sendable {
    let offset: Double
    let ratio: Double
    let confidence: Double
}

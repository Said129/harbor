import Foundation

struct SubtitleDocument: Sendable {
    struct Cue: Sendable { let start: Double; let end: Double; let range: NSRange; let hours: Bool }
    let text: String
    let cues: [Cue]
    let vtt: Bool
    init(_ text: String) throws {
        self.text = text
        let header = text.first == "\u{FEFF}" ? String(text.dropFirst()) : text
        vtt = header.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("WEBVTT")
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
        rewriting { cue in (cue.start * result.ratio + result.offset, cue.end * result.ratio + result.offset) }
    }

    func applying(_ transform: SubtitlePivotTransform) -> String {
        rewriting { cue in transform.displayTimes(cue.start, cue.end) }
    }

    func structuralCues() throws -> [SubtitlePivotCue] {
        let source = text as NSString
        let blankLine = try NSRegularExpression(pattern: #"\r\n[ \t]*\r\n|\n[ \t]*\n|\r(?!\n)[ \t]*\r(?!\n)"#)
        let tags = try NSRegularExpression(pattern: #"<[^>]+>|\{[^}]*\}"#)
        let cues = self.cues.enumerated().map { index, cue in
            let start = NSMaxRange(source.lineRange(for: cue.range))
            let limit = index + 1 < self.cues.count ? self.cues[index + 1].range.location : source.length
            let length = max(0, limit - start)
            if length == 0 || source.character(at: start) == 10 || source.character(at: start) == 13 {
                return SubtitlePivotCue(start: cue.start, end: cue.end, text: "")
            }
            let next = blankLine.firstMatch(in: text, range: NSRange(location: start, length: length))
            let range = NSRange(location: start, length: next.map { $0.range.location - start } ?? length)
            let raw = source.substring(with: range).replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
            let stripped = tags.stringByReplacingMatches(in: raw, range: NSRange(raw.startIndex..., in: raw), withTemplate: "")
            let body = [("\\N", "\n"), ("&nbsp;", " "), ("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&#39;", "'")]
                .reduce(stripped) { $0.replacingOccurrences(of: $1.0, with: $1.1) }
            return SubtitlePivotCue(start: cue.start, end: cue.end, text: body)
        }
        return cues.sorted { $0.start < $1.start }
    }

    private func rewriting(_ timing: (Cue) -> SubtitlePivotAudio.Interval) -> String {
        let output = NSMutableString(string: text)
        func stamp(_ time: Double, hours: Bool) -> String {
            let ms = Int((max(0, time) * 1_000).rounded())
            let separator = vtt ? "." : ","
            if hours || ms >= 3_600_000 { return String(format: "%02d:%02d:%02d%@%03d", ms / 3_600_000, (ms / 60_000) % 60, (ms / 1_000) % 60, separator, ms % 1_000) }
            return String(format: "%02d:%02d%@%03d", ms / 60_000, (ms / 1_000) % 60, separator, ms % 1_000)
        }
        for cue in cues.reversed() {
            let times = timing(cue)
            output.replaceCharacters(in: cue.range, with: stamp(times.start, hours: cue.hours) + " --> " + stamp(times.end, hours: cue.hours))
        }
        return output as String
    }
}

struct SubtitleSyncResult: Sendable {
    let offset: Double
    let ratio: Double
    let confidence: Double
}

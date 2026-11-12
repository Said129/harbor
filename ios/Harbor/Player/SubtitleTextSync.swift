import Foundation

/// Desktop's manual "Live sync" by text: `lib/subtitles/text-sync.ts` (`deltaFn`, `applyLinear`) and the state rules of
/// `views/player/hooks/use-text-sync.ts`. The person taps a line they hear, "Align to now" pins it to the playback time, a second line
/// corrects drift, a nudge moves everything, and a section can be shifted on its own. Nothing here touches mpv or the file system.
enum SubtitleTextSync {
    /// Desktop's `MIN_GAP_SEC`: two points closer than this measure reaction time, not drift.
    static let minimumGap = 3.0
    /// Desktop's `MAX_SLOPE`: a drift of more than 5 percent is not accepted.
    static let maximumSlope = 0.05

    struct Timing: Equatable, Sendable {
        let start: Double
        let end: Double
    }

    /// A line of the file (`t`, its start in the file) that was heard at playback time `at`.
    struct Point: Equatable, Sendable {
        let t: Double
        let at: Double
    }

    /// A run of lines, first to last index inclusive, shifted by `offset` seconds on top of the global correction.
    struct Segment: Equatable, Sendable {
        let startIndex: Int
        let endIndex: Int
        let offset: Double
    }

    /// Desktop `deltaFn(points, nudge)(t)`: the seconds to add to a cue that starts at `t`.
    static func delta(at t: Double, points: [Point], nudge: Double) -> Double {
        if points.isEmpty { return nudge }
        if points.count == 1 { return points[0].at - points[0].t + nudge }
        let sorted = points.sorted { $0.t < $1.t }
        let first = sorted[0]
        let last = sorted[sorted.count - 1]
        let base = first.at - first.t
        let span = last.t - first.t
        let slope = (last.at - last.t - base) / span
        // Nearby points measure reaction time, not FPS drift. The latest alignment stays a constant offset.
        if span < minimumGap || !slope.isFinite || abs(slope) > maximumSlope {
            let latest = points[points.count - 1]
            return latest.at - latest.t + nudge
        }
        return base + slope * (t - first.t) + nudge
    }

    /// Desktop `applyLinear`: every cue moved by the delta at its start (and at its end), plus the sections that cover its index.
    static func apply(_ cues: [Timing], points: [Point], nudge: Double, segments: [Segment]) -> [Timing] {
        var result: [Timing] = []
        result.reserveCapacity(cues.count)
        for (index, cue) in cues.enumerated() {
            var extra = 0.0
            for segment in segments where index >= segment.startIndex && index <= segment.endIndex { extra += segment.offset }
            let start = round3(max(0, cue.start + delta(at: cue.start, points: points, nudge: nudge) + extra))
            let end = max(start + 0.001, round3(cue.end + delta(at: cue.end, points: points, nudge: nudge) + extra))
            result.append(Timing(start: start, end: end))
        }
        return result
    }

    /// Desktop `syncFromHere`: the first two points are kept, and a third replaces the second.
    static func adding(_ point: Point, to points: [Point]) -> [Point] {
        points.count < 2 ? points + [point] : [points[0], point]
    }

    static func round3(_ value: Double) -> Double {
        (value * 1_000).rounded() / 1_000
    }

    /// The index of the cue showing at `position`, or nil between lines.
    static func activeIndex(in cues: [Timing], position: Double) -> Int? {
        guard position.isFinite else { return nil }
        return cues.firstIndex { position >= $0.start && position < $0.end }
    }

    /// Live sync rewrites SubRip and WebVTT files, the two formats `SubtitleDocument` reads. A styled (ASS) file is left alone.
    static func supportsFile(named name: String) -> Bool {
        let clean = name.components(separatedBy: CharacterSet(charactersIn: "?#")).first ?? name
        let fileExtension = (clean as NSString).pathExtension.lowercased()
        return fileExtension == "srt" || fileExtension == "vtt"
    }

    /// Desktop's `m:ss` label for a cue start.
    static func clock(_ seconds: Double) -> String {
        let whole = Int(max(0, seconds.isFinite ? seconds : 0))
        return String(format: "%02d:%02d", whole / 60, whole % 60)
    }
}

/// One open "Live sync" session over the lines of the selected external subtitle (Desktop's `useTextSync` state).
struct SubtitleTextSyncSession: Equatable, Sendable {
    let cues: [SubtitleTextSync.Timing]
    let texts: [String]
    /// The subtitle delay at the start. It is baked into the saved file, and the player's delay goes back to zero.
    let baseOffset: Double
    private(set) var points: [SubtitleTextSync.Point] = []
    private(set) var nudge: Double
    private(set) var segments: [SubtitleTextSync.Segment] = []
    private(set) var rangeStart: Int?
    private(set) var rangeEnd: Int?

    init(cues: [SubtitleTextSync.Timing], texts: [String], baseOffset: Double) {
        self.cues = cues
        self.texts = texts
        self.baseOffset = baseOffset
        self.nudge = baseOffset
    }

    /// Desktop's `dirty`: something changed that a save would write.
    var dirty: Bool {
        !points.isEmpty || nudge != baseOffset || !segments.isEmpty
    }

    var corrected: [SubtitleTextSync.Timing] {
        SubtitleTextSync.apply(cues, points: points, nudge: nudge, segments: segments)
    }

    func currentDelta(at position: Double) -> Double {
        SubtitleTextSync.delta(at: position, points: points, nudge: nudge)
    }

    /// The first and last line of the chosen section, in order, once both are chosen.
    var range: (low: Int, high: Int)? {
        guard let start = rangeStart, let end = rangeEnd else { return nil }
        return (low: min(start, end), high: max(start, end))
    }

    /// "Align to now" on one line. With a section chosen it shifts that section; otherwise it adds a point and drops the nudge,
    /// because the point already holds the whole correction.
    mutating func syncFromHere(cueIndex: Int, position: Double) {
        guard cues.indices.contains(cueIndex), position.isFinite else { return }
        let cue = cues[cueIndex]
        if let range {
            let current = SubtitleTextSync.delta(at: cue.start, points: points, nudge: nudge)
            let offset = SubtitleTextSync.round3(position - cue.start - current)
            var next = segments.filter { !($0.startIndex == range.low && $0.endIndex == range.high) }
            next.append(SubtitleTextSync.Segment(startIndex: range.low, endIndex: range.high, offset: offset))
            segments = next
            rangeStart = nil
            rangeEnd = nil
            return
        }
        points = SubtitleTextSync.adding(SubtitleTextSync.Point(t: cue.start, at: position), to: points)
        nudge = 0
    }

    mutating func adjustNudge(by seconds: Double) {
        guard seconds.isFinite else { return }
        nudge = SubtitleTextSync.round3(nudge + seconds)
    }

    mutating func chooseRangeStart(_ index: Int) {
        guard cues.indices.contains(index) else { return }
        rangeStart = index
        rangeEnd = nil
    }

    mutating func chooseRangeEnd(_ index: Int) {
        guard rangeStart != nil, cues.indices.contains(index) else { return }
        rangeEnd = index
    }

    mutating func clearRange() {
        rangeStart = nil
        rangeEnd = nil
    }

    /// Desktop's `reset`: every point, nudge and section is dropped.
    mutating func reset() {
        points = []
        nudge = 0
        segments = []
        rangeStart = nil
        rangeEnd = nil
    }

    /// Lines whose words contain `query`, ignoring case. An empty query matches none, as Desktop's highlight does.
    func matches(_ query: String) -> [Int] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return [] }
        return texts.indices.filter { texts[$0].lowercased().contains(needle) }
    }
}

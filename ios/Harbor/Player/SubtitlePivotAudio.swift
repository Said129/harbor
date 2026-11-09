import Foundation

/// Independent window geometry and zero-lag scoring from Desktop's
/// `subsync/analysis_windows.rs`, `scorer.rs` and `correlate.rs`.
enum SubtitlePivotAudio {
    typealias Interval = (start: Double, end: Double)

    struct Window: Hashable, Sendable {
        let id: String
        let start: Double
        let end: Double
        var length: Double { end - start }

        func overlaps(_ other: Window) -> Bool { start < other.end && other.start < end }
    }

    struct Quality: Sendable {
        let ncc: Double
        let coverage: Double
    }

    static func fitWindows(duration: Double) -> [Window] {
        guard duration.isFinite, duration >= 60 else { return [] }
        if duration < 300 {
            let start = max(duration * 0.05, 5)
            return [.init(id: "fit-whole", start: start, end: min(max(duration * 0.95, start + 30), duration))]
        }
        let margin = min(max(duration * 0.05, 5), 270)
        let length = min(max(duration * 0.22, 60), 600)
        let late = max(duration - margin - length, margin + length)
        return [.init(id: "fit-early", start: margin, end: margin + length),
                .init(id: "fit-late", start: late, end: late + length)]
    }

    static func middleWindows(duration: Double, excluding fit: [Window]) -> [Window] {
        guard duration.isFinite, duration >= 300 else { return [] }
        let length = min(max(duration * 0.1, 30), 240)
        let windows = [("validation-middle-a", 0.43), ("validation-middle-b", 0.57)].map { id, fraction in
            let center = duration * fraction
            return Window(id: id, start: center - length / 2, end: center + length / 2)
        }
        return verified(windows, duration: duration, excluding: fit) ?? []
    }

    static func verified(_ windows: [Window], duration: Double, excluding fit: [Window] = []) -> [Window]? {
        guard duration.isFinite, (60...28_800).contains(duration), (1...24).contains(windows.count),
              Set(windows.map(\.id)).count == windows.count else { return nil }
        let sorted = windows.sorted { $0.start == $1.start ? $0.id < $1.id : $0.start < $1.start }
        for (index, window) in sorted.enumerated() {
            guard window.start.isFinite, window.end.isFinite, window.start >= 0, window.end <= duration, window.length >= 2,
                  window.id.range(of: #"^[A-Za-z0-9._:-]{1,96}$"#, options: .regularExpression) != nil,
                  (index == 0 || !window.overlaps(sorted[index - 1])),
                  !fit.contains(where: window.overlaps) else { return nil }
        }
        return sorted
    }

    /// Every window must actually produce speech. An unavailable window cannot
    /// be treated as silence or carry a measured validation ID.
    static func measureSpeech(_ source: PlaybackSource, windows: [Window], audioID: Int) throws -> [Interval] {
        let deadline = Date().addingTimeInterval(12)
        return try windows.flatMap { window in
            try Task.checkCancellation()
            let audio = try SubtitleAutoSync.speech(source, window: .init(start: window.start, length: window.length),
                                                   audioID: audioID, timeout: deadline.timeIntervalSinceNow)
            guard !audio.isEmpty else { throw HarborError(code: "subtitle-pivot-no-speech") }
            return audio.map { (start: $0.0, end: $0.1) }
        }
    }

    /// Both hypotheses are scored against the same measured speech intervals.
    /// Packing excludes the unmeasured spans between the validation windows.
    static func quality(speech: [Interval], cues: [Interval], windows: [Window]) throws -> Quality? {
        guard cues.count >= 4, !speech.isEmpty else { return nil }
        let packedAudio = pack(speech, windows: windows)
        let packedCues = pack(cues, windows: windows)
        let duration = windows.reduce(0) { $0 + $1.length }
        guard (2...2_400).contains(duration), !packedAudio.isEmpty, packedCues.count >= 2 else { return nil }
        let count = Int((duration * 100).rounded())
        let audio = raster(packedAudio, count: count), subtitle = raster(packedCues, count: count)
        var voiced = 0, visible = 0, aligned = 0
        for index in 0..<count {
            if index.isMultiple(of: 10_000) { try Task.checkCancellation() }
            voiced += Int(audio[index]); visible += Int(subtitle[index])
            aligned += Int(audio[index] & subtitle[index])
        }
        let n = Double(count), x = Double(voiced), y = Double(visible), xy = Double(aligned)
        let denominator = sqrt(max(0, (x - x * x / n) * (y - y * y / n)))
        let ncc = denominator >= 1e-9 ? max(0, (xy - x * y / n) / denominator) : 0
        return Quality(ncc: ncc, coverage: visible == 0 ? 0 : xy / y)
    }

    private static func pack(_ intervals: [Interval], windows: [Window]) -> [Interval] {
        var offset = 0.0
        var result: [Interval] = []
        for window in windows {
            for interval in intervals where interval.start.isFinite && interval.end.isFinite {
                let start = max(interval.start, window.start), end = min(interval.end, window.end)
                if end > start { result.append((offset + start - window.start, offset + end - window.start)) }
            }
            offset += window.length
        }
        return result
    }

    private static func raster(_ intervals: [Interval], count: Int) -> [UInt8] {
        var mask = [UInt8](repeating: 0, count: count)
        for interval in intervals {
            let first = Int(min(Double(count), max(0, (interval.start * 100).rounded())))
            let last = Int(min(Double(count), max(0, (interval.end * 100).rounded())))
            if last > first { for index in first..<last { mask[index] = 1 } }
        }
        return mask
    }
}

/// Supplies the pivot workflow with native measurements. Speech can only be
/// reused for the exact audio track, source and requested window geometry.
@MainActor final class SubtitlePivotEvidence {
    private let source: PlaybackSource
    private let duration: Double
    private let audioID: Int
    private var speechByWindows: [[SubtitlePivotAudio.Window]: [SubtitlePivotAudio.Interval]] = [:]

    init(source: PlaybackSource, duration: Double, audioID: Int) {
        self.source = source
        self.duration = duration
        self.audioID = audioID
    }

    func validatePivot(cues: [SubtitlePivotCue]) async throws -> JSONValue {
        let fit = SubtitlePivotAudio.fitWindows(duration: duration)
        let windows = SubtitlePivotAudio.middleWindows(duration: duration, excluding: fit)
        guard !fit.isEmpty, !windows.isEmpty else { throw HarborError(code: "subtitle-pivot-windows") }
        let raw: [SubtitlePivotAudio.Interval] = cues.map { ($0.start, $0.end) }
        let fitSpeech = try await measuredSpeech(fit)
        let fitRanges = fit.map { SubtitleAutoSync.Window(start: $0.start, length: $0.length) }
        let duration = duration
        let fitted = try await Self.work {
            try SubtitleAutoSync.solve(audio: fitSpeech, cues: raw, duration: duration, windows: fitRanges)
        }
        let speech = try await measuredSpeech(windows)
        let (identity, corrected) = try await Self.work {
            let original = try SubtitlePivotAudio.quality(speech: speech, cues: raw, windows: windows)
            let changed: SubtitlePivotAudio.Quality? = try fitted.flatMap { result in
                let adjusted: [SubtitlePivotAudio.Interval] = raw.map { ($0.start * result.ratio + result.offset, $0.end * result.ratio + result.offset) }
                return try SubtitlePivotAudio.quality(speech: speech, cues: adjusted, windows: windows)
            }
            return (original, changed)
        }
        guard let identity else { throw HarborError(code: "subtitle-pivot-unmeasured") }
        let useFit = corrected.map { $0.ncc >= 0.55 && $0.coverage >= 0.55 && $0.ncc - identity.ncc + 1e-9 >= 0.08 } ?? false
        let best = useFit ? corrected ?? identity : identity
        return .object([
            "validated": .bool(best.ncc >= 0.55 && best.coverage >= 0.55),
            "transform": SubtitlePivotTransform.affine(offset: useFit ? fitted?.offset ?? 0 : 0, ratio: useFit ? fitted?.ratio ?? 1 : 1),
            "score": .number(best.ncc), "coverage": .number(best.coverage),
            "wrongCut": .bool(best.ncc < 0.25 || best.coverage < 0.2),
        ])
    }

    func validateTarget(cues: [SubtitlePivotCue], transform: SubtitlePivotTransform, heldOut: [JSONValue]) async throws -> JSONValue {
        guard (3...24).contains(heldOut.count) else { throw HarborError(code: "subtitle-pivot-windows") }
        var selected = Set<Int>()
        var requested: [SubtitlePivotAudio.Window] = []
        for (index, window) in heldOut.enumerated() {
            guard let source = window["sourceSec"].numericValue, source.isFinite,
                  let start = window["fromSec"].numericValue, let end = window["toSec"].numericValue,
                  start.isFinite, end.isFinite,
                  let nearest = cues.indices.min(by: { Self.distance(cues[$0], source) < Self.distance(cues[$1], source) }),
                  Self.distance(cues[nearest], source) <= 8 else { throw HarborError(code: "subtitle-pivot-windows") }
            selected.insert(nearest)
            requested.append(.init(id: "pivot-held-out-\(index + 1)", start: max(0, start), end: min(duration, end)))
        }
        guard selected.count >= 4, let windows = SubtitlePivotAudio.verified(requested, duration: duration) else {
            throw HarborError(code: "subtitle-pivot-windows")
        }
        let raw: [SubtitlePivotAudio.Interval] = selected.sorted().map { (cues[$0].start, cues[$0].end) }
        let speech = try await measuredSpeech(windows)
        let (before, after) = try await Self.work {
            let before = try SubtitlePivotAudio.quality(speech: speech, cues: raw, windows: windows)
            let after = try SubtitlePivotAudio.quality(speech: speech, cues: raw.map { transform.times($0.start, $0.end) }, windows: windows)
            return (before, after)
        }
        guard let before, let after else { throw HarborError(code: "subtitle-pivot-unmeasured") }
        return .object(["qualityBefore": .number(before.ncc), "qualityAfter": .number(after.ncc),
                        "coverage": .number(after.coverage), "heldOutAudioMeasured": .bool(true),
                        "wrongCut": .bool(after.ncc < 0.3 || after.coverage < 0.25)])
    }

    private func measuredSpeech(_ windows: [SubtitlePivotAudio.Window]) async throws -> [SubtitlePivotAudio.Interval] {
        if let cached = speechByWindows[windows] { return cached }
        let source = source, audioID = audioID
        let speech = try await Self.work { try SubtitlePivotAudio.measureSpeech(source, windows: windows, audioID: audioID) }
        speechByWindows[windows] = speech
        return speech
    }

    private nonisolated static func distance(_ cue: SubtitlePivotCue, _ value: Double) -> Double {
        abs((cue.start + cue.end) / 2 - value)
    }

    nonisolated static func work<Result: Sendable>(_ operation: @escaping @Sendable () throws -> Result) async throws -> Result {
        let task = Task.detached(priority: .utility) { try operation() }
        return try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
    }
}

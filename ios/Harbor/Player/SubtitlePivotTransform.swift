import Foundation

/// Bounded transform returned by Desktop's pivot workflow. The scorer and
/// installed subtitle both use the segment containing the cue's start.
struct SubtitlePivotTransform: Sendable {
    struct Segment: Sendable {
        let start: Double
        let end: Double
        let offset: Double
        let ratio: Double

        func time(_ value: Double) -> Double { value * ratio + offset }
    }

    private let segments: [Segment]
    var piecewise: Bool { segments.count > 1 }

    init?(_ json: JSONValue) {
        switch json["kind"].string {
        case "affine":
            guard let segment = Self.segment(json, start: 0, end: .infinity) else { return nil }
            segments = [segment]
        case "piecewise":
            let raw = json["segments"].array
            guard (1...12).contains(raw.count) else { return nil }
            var parsed: [Segment] = []
            for value in raw {
                guard let start = value["fromSec"].numericValue, let end = value["toSec"].numericValue,
                      start.isFinite, end.isFinite, start < end,
                      let segment = Self.segment(value, start: start, end: end) else { return nil }
                parsed.append(segment)
            }
            let sorted = parsed.sorted { $0.start < $1.start }
            guard zip(sorted, sorted.dropFirst()).allSatisfy({ pair in pair.0.end <= pair.1.start }) else { return nil }
            segments = sorted
        default: return nil
        }
    }

    private static func segment(_ raw: JSONValue, start: Double, end: Double) -> Segment? {
        guard let offset = raw["offsetSec"].numericValue, let ratio = raw["ratio"].numericValue,
              offset.isFinite, abs(offset) <= 3_600, ratio.isFinite, (0.5...2).contains(ratio) else { return nil }
        return Segment(start: start, end: end, offset: offset, ratio: ratio)
    }

    func times(_ start: Double, _ end: Double) -> SubtitlePivotAudio.Interval {
        guard let segment = segments.first(where: { start >= $0.start && start < $0.end }) ?? segments.last else { return (start, end) }
        return (segment.time(start), segment.time(end))
    }

    func displayTimes(_ start: Double, _ end: Double) -> SubtitlePivotAudio.Interval {
        let transformed = times(start, end)
        let first = max(0, transformed.start)
        return (first, max(first + 0.001, transformed.end))
    }

    static func affine(offset: Double, ratio: Double) -> JSONValue {
        .object(["kind": .string("affine"), "offsetSec": .number(offset), "ratio": .number(ratio)])
    }
}

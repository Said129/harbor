import Foundation

/// One marked ad range as the player has it, in seconds.
struct AdReportRange: Equatable, Sendable {
    let startSec: Double
    let endSec: Double
}

/// A range as Desktop posts it: whole seconds with start before end.
struct AdReportWireRange: Equatable, Sendable {
    let start: Int
    let end: Int
}

/// Desktop's `submitAdReport` (`lib/ad-report/submit.ts`) without any screen. The transport is injectable so the
/// request can be checked without a network.
enum AdReportSubmitter {
    static let endpoint = "https://bugs.harbor.site/v1/adreport"

    /// Desktop's `Math.round`, which is floor(x + 0.5).
    private static func javaScriptRound(_ value: Double) -> Double {
        (value + 0.5).rounded(.down)
    }

    /// Start is the smaller end and end the larger, both rounded; ranges that end where they start are dropped.
    /// Values that are not finite, or too large to be seconds, are dropped too.
    static func normalizedRanges(_ ranges: [AdReportRange]) -> [AdReportWireRange] {
        ranges.compactMap { (range: AdReportRange) -> AdReportWireRange? in
            guard range.startSec.isFinite, range.endSec.isFinite,
                  abs(range.startSec) < 1e12, abs(range.endSec) < 1e12 else { return nil }
            let start = javaScriptRound(min(range.startSec, range.endSec))
            let end = javaScriptRound(max(range.startSec, range.endSec))
            guard end > start else { return nil }
            return AdReportWireRange(start: Int(start), end: Int(end))
        }
    }

    /// The JSON body Desktop posts, or nil when the source is not one the corpus holds or no range is left.
    static func body(content: String, source: String, ranges: [AdReportRange]) -> JSONValue? {
        guard AdCorpusRules.acceptsSource(source) else { return nil }
        let wire = normalizedRanges(ranges)
        guard !wire.isEmpty else { return nil }
        let items = wire.map { (range: AdReportWireRange) -> JSONValue in
            .object(["start": .integer(Int64(range.start)), "end": .integer(Int64(range.end))])
        }
        return .object(["content": .string(content), "source": .string(source), "ranges": .array(items)])
    }

    /// True when the report was accepted (a 2xx answer). Every failure gives false.
    static func submit(content: String, source: String, ranges: [AdReportRange],
                       transport: @Sendable (String, JSONValue) async throws -> Bool = { try await HTTPClient().postAdReport($0, body: $1) }) async -> Bool {
        guard let body = body(content: content, source: source, ranges: ranges) else { return false }
        do { return try await transport(endpoint, body) } catch { return false }
    }
}

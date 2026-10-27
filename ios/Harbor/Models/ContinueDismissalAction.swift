import Foundation

struct ContinueDismissalAction: Sendable {
    let target: ResumeTarget
    let clearsResume: Bool
    let cloudRecord: JSONValue?
    init(_ record: LibraryRecord, privateMode: Bool, authenticated: Bool, timestampMs: Double) {
        let coordinates = record.playbackCoordinates
        target = .init(id: record.id, season: coordinates.season, episode: coordinates.episode, videoId: record.raw["state"]["video_id"].string)
        let external = record.raw["external"].string != nil
        let hasState: Bool
        if case .object = record.raw["state"] { hasState = true } else { hasState = false }
        let sharedWrite = !privateMode && authenticated && hasState
        clearsResume = external || sharedWrite
        if sharedWrite && !external {
            var fields = record.raw.objectValue, state = record.raw["state"].objectValue
            state["timeOffset"] = .integer(0); fields["state"] = .object(state)
            fields["_mtime"] = .string(Self.iso(timestampMs)); cloudRecord = .object(fields)
        } else { cloudRecord = nil }
    }
    static func iso(_ milliseconds: Double) -> String {
        let value = UInt64(max(0, min(8_640_000_000_000_000, milliseconds.rounded(.down))))
        let fraction = String(value % 1_000)
        let whole = Date(timeIntervalSince1970: Double(value / 1_000)).ISO8601Format()
        return String(whole.dropLast()) + "." + String(repeating: "0", count: 3 - fraction.count) + fraction + "Z"
    }
}

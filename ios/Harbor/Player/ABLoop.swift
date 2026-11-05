import Foundation

/// Desktop's A-B loop (`views/player/hooks/use-ab-loop.ts`): a section of the video repeats from A to B.
/// mpv does the repeating once both points are set; this keeps Desktop's rules for the two points.
struct ABLoop: Equatable, Sendable {
    private(set) var a: Double?
    private(set) var b: Double?

    /// A loop needs both points with B after A.
    var active: Bool {
        guard let a, let b else { return false }
        return b > a
    }
    var isSet: Bool { a != nil || b != nil }

    /// Point A moves to the playhead; a B that is no longer after it is dropped.
    mutating func setA(at position: Double) {
        let time = max(0, position)
        a = time
        if let b, b <= time { self.b = nil }
    }
    /// Point B needs an A and must be after it; otherwise it stays where it was.
    mutating func setB(at position: Double) {
        guard let a else { return }
        let time = max(0, position)
        if time > a { b = time }
    }
    mutating func clear() { a = nil; b = nil }

    /// What mpv's `ab-loop-a` and `ab-loop-b` properties take: seconds, or "no" to clear.
    var mpvValues: (a: String, b: String) {
        (a.map { String($0) } ?? "no", b.map { String($0) } ?? "no")
    }

    /// "1:05 → 2:30" with a dash for a point that is not set, as Desktop's chip shows it.
    func summary() -> String {
        func time(_ value: Double?) -> String {
            guard let value else { return "—" }
            let seconds = max(0, Int(value))
            let hours = seconds / 3600, minutes = seconds % 3600 / 60, rest = seconds % 60
            return hours > 0 ? String(format: "%d:%02d:%02d", hours, minutes, rest) : String(format: "%d:%02d", minutes, rest)
        }
        return time(a) + " → " + time(b)
    }
}

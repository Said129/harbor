import Foundation

/// What a download says about its transfer, so the person can tell it is really moving: a percentage when the server gave
/// a size, the bytes received when it did not, and a plain "connecting" line while nothing has arrived yet.
struct DownloadProgressPresentation: Equatable {
    enum Phase: Equatable {
        /// Started, but the server has not sent a byte.
        case connecting
        /// Bytes are arriving and the total is known.
        case sized
        /// Bytes are arriving but the server never said how many to expect.
        case unsized
        case paused
    }

    /// A source that has sent nothing for this long gets a hint to cancel it and pick another.
    static let slowStartSeconds: TimeInterval = 30

    let phase: Phase
    /// Between 0 and 1 only when the total is known.
    let fraction: Double?
    /// "Descargando 37 %", "Conectando con la fuente…".
    let headline: String
    /// "120 MB de 1,4 GB · 3,2 MB/s · 6 min".
    let detail: String
    /// A note under the bar, set when the source is slow to answer.
    let hint: String?

    static func make(received: Int64, expected: Int64, paused: Bool, bytesPerSecond: Double?, started: Date, now: Date) -> DownloadProgressPresentation {
        let have = max(0, received), total = max(0, expected)
        let fraction: Double? = total > 0 ? min(1, max(0, Double(have) / Double(total))) : nil
        let phase: Phase
        if paused { phase = .paused }
        else if have == 0 { phase = .connecting }
        else if fraction != nil { phase = .sized }
        else { phase = .unsized }

        var headline = paused ? DownloadStatus.paused.title : DownloadStatus.downloading.title
        if phase == .connecting { headline = "Conectando con la fuente…" }
        else if let fraction { headline += " " + String(Int((fraction * 100).rounded())) + " %" }

        var parts: [String] = []
        if total > 0 { parts.append(size(have) + " de " + size(total)) }
        else if have > 0 { parts.append(size(have) + " descargados") }
        if !paused, let speed = bytesPerSecond, speed.isFinite, speed > 0 {
            parts.append(size(Int64(speed)) + "/s")
            if total > have {
                let seconds = Double(total - have) / speed
                if let remaining = remaining(seconds) { parts.append(remaining) }
            }
        }

        var hint: String?
        if phase == .connecting, now.timeIntervalSince(started) >= slowStartSeconds {
            hint = "La fuente tarda en responder. Si no avanza, cancela la descarga y elige otra fuente."
        } else if phase == .unsized {
            hint = "La fuente no indica el tamaño total, por eso no hay porcentaje."
        }
        return DownloadProgressPresentation(phase: phase, fraction: fraction, headline: headline, detail: parts.joined(separator: " · "), hint: hint)
    }

    static func make(item: DownloadItem, bytesPerSecond: Double?, now: Date = Date()) -> DownloadProgressPresentation {
        make(received: item.received, expected: item.expected, paused: item.status == .paused, bytesPerSecond: bytesPerSecond, started: item.started, now: now)
    }

    /// The size the server reported, or what the task itself expects, or none: `-1` means unknown to URLSession.
    static func expectedBytes(reported: Int64, taskExpectation: Int64) -> Int64 {
        if reported > 0 { return reported }
        return max(0, taskExpectation)
    }

    /// A smoothed speed from the last reading and the new one; nil until two readings a second apart exist.
    static func smoothedSpeed(previous: Double?, bytes: Int64, lastBytes: Int64, seconds: TimeInterval) -> Double? {
        guard seconds >= 1, bytes >= lastBytes else { return previous }
        let instant = Double(bytes - lastBytes) / seconds
        guard let previous else { return instant }
        return previous * 0.6 + instant * 0.4
    }

    private static func size(_ bytes: Int64) -> String { ByteCountFormatter.string(fromByteCount: max(0, bytes), countStyle: .file) }

    private static func remaining(_ seconds: Double) -> String? {
        guard seconds.isFinite, seconds >= 0, seconds < 48 * 3600 else { return nil }
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .abbreviated
        formatter.maximumUnitCount = 2
        return formatter.string(from: max(1, seconds.rounded()))
    }
}

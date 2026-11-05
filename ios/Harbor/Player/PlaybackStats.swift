import SwiftUI

/// What Desktop's stats overlay (`components/player/stats-overlay.tsx`) reads from mpv once a second.
struct PlaybackStats: Equatable, Sendable {
    var videoBitrate: Double?
    var audioBitrate: Double?
    var decoderDrops: Int?
    var outputDrops: Int?
    var estimatedFPS: Double?
    var containerFPS: Double?
    var videoCodec: String?
    var audioCodec: String?
    var hardwareDecoder: String?
    var cacheBuffering: Double?

    /// `property` answers mpv's string form of a property, or nil when it has none.
    static func read(_ property: (String) -> String?) -> PlaybackStats {
        func number(_ name: String) -> Double? { property(name).flatMap { Double($0) }.flatMap { $0.isFinite ? $0 : nil } }
        func count(_ name: String) -> Int? { number(name).map { Int($0) } }
        func text(_ name: String) -> String? { property(name).flatMap { $0.isEmpty || $0 == "no" ? nil : $0 } }
        return PlaybackStats(videoBitrate: number("video-bitrate"), audioBitrate: number("audio-bitrate"),
                             decoderDrops: count("decoder-frame-drop-count"), outputDrops: count("frame-drop-count"),
                             estimatedFPS: number("estimated-vf-fps"), containerFPS: number("container-fps"),
                             videoCodec: text("video-codec"), audioCodec: text("audio-codec"), hardwareDecoder: text("hwdec-current"),
                             cacheBuffering: number("cache-buffering-state"))
    }

    /// Desktop's `formatBitrate`.
    static func bitrate(_ bitsPerSecond: Double) -> String {
        if bitsPerSecond >= 1_000_000 { return String(format: "%.2f Mbps", bitsPerSecond / 1_000_000) }
        if bitsPerSecond >= 1_000 { return String(format: "%.0f kbps", bitsPerSecond / 1_000) }
        return String(format: "%.0f bps", bitsPerSecond)
    }

    struct Context: Sendable {
        var width = 0
        var height = 0
        var audioTrack: String?
        var subtitleTrack: String?
        var speed = 1.0
        var volume = 100.0
        var muted = false
    }

    /// The rows Desktop lists, in its order; a row whose value is unknown is left out, as there.
    func rows(_ context: Context, text: (String) -> String = { $0 }) -> [(label: String, value: String)] {
        var rows: [(label: String, value: String)] = [(text("Engine"), "libmpv")]
        rows.append((text("Resolution"), context.width > 0 && context.height > 0 ? "\(context.width)×\(context.height)" : "—"))
        if let fps = estimatedFPS ?? containerFPS { rows.append((text("Frame rate"), String(format: "%.2f fps", fps))) }
        if let videoCodec { rows.append((text("Video codec"), videoCodec)) }
        if let audioCodec { rows.append((text("Audio codec"), audioCodec)) }
        if let hardwareDecoder { rows.append((text("HW decode"), hardwareDecoder)) }
        if let videoBitrate { rows.append((text("Video bitrate"), Self.bitrate(videoBitrate))) }
        if let audioBitrate { rows.append((text("Audio bitrate"), Self.bitrate(audioBitrate))) }
        if decoderDrops != nil || outputDrops != nil {
            rows.append((text("Dropped (decode / vo)"), "\(decoderDrops.map(String.init) ?? "—") / \(outputDrops.map(String.init) ?? "—")"))
        }
        if let cacheBuffering { rows.append((text("Cache buffering"), String(format: "%.0f%%", cacheBuffering))) }
        rows.append((text("Audio track"), context.audioTrack ?? "—"))
        rows.append((text("Subtitle track"), context.subtitleTrack ?? text("Off")))
        rows.append((text("Speed"), String(format: "%.2f×", context.speed)))
        rows.append((text("Volume"), "\(Int(context.volume.rounded()))%" + (context.muted ? text(" · muted") : "")))
        return rows
    }
}

/// Desktop's playback stats card, drawn over the video's top-left corner.
struct PlayerStatsOverlay: View {
    let state: PlayerState

    private func name(_ track: PlayerState.Track?) -> String? {
        guard let track else { return nil }
        for candidate in [track.title, track.language, track.label] where !candidate.isEmpty { return candidate }
        return String(track.id)
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            let stats = PlaybackStats.read { state.controller?.stat($0) }
            let context = PlaybackStats.Context(width: state.videoWidth, height: state.videoHeight,
                                                audioTrack: name(state.tracks.first { $0.type == "audio" && $0.selected }),
                                                subtitleTrack: name(state.primarySubtitle), speed: state.speed, volume: state.volume, muted: state.muted)
            VStack(alignment: .leading, spacing: 8) {
                Text(DesktopInterfaceText.value("Playback stats · press I to hide")).font(.system(size: 10, weight: .bold)).textCase(.uppercase)
                    .tracking(1.6).foregroundStyle(.white.opacity(0.55))
                VStack(spacing: 2) {
                    ForEach(Array(stats.rows(context, text: { DesktopInterfaceText.value($0) }).enumerated()), id: \.offset) { _, row in
                        HStack(alignment: .firstTextBaseline, spacing: 14) {
                            Text(row.label).foregroundStyle(.white.opacity(0.6))
                            Spacer(minLength: 8)
                            Text(row.value).lineLimit(1).multilineTextAlignment(.trailing)
                        }
                    }
                }.font(.system(size: 11.5, design: .monospaced))
            }
            .padding(14).frame(maxWidth: 320)
            .background(.black.opacity(0.78), in: .rect(cornerRadius: 16))
            .overlay { RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.1), lineWidth: 1) }
        }
        .allowsHitTesting(false).accessibilityIdentifier("player-stats")
    }
}

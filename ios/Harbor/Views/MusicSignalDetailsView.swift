import AVFoundation
import SwiftUI

/// Desktop's music-signal-details: the declared source stage and the actual
/// output stage. A value that cannot be read stays absent; none is inferred.
@MainActor struct MusicSignalDetailsView: View {
    let player: MusicPlayback
    @State private var outputRate: Double?
    private func text(_ key: String) -> String { DesktopInterfaceText.value(key) }
    var body: some View {
        let quality = player.currentTrack.flatMap { MusicTrackQuality($0) }
        let tier = quality?.tier ?? .unverified
        let settings = player.playbackSession?.audio?.options
        let route = AVAudioSession.sharedInstance().currentRoute.outputs.map(\.portName).joined(separator: ", ")
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: tier == .unverified ? "questionmark.circle" : "waveform").font(.title3)
                    .foregroundStyle(tier == .lossless || tier == .hiRes ? HarborTheme.accent : HarborTheme.ink.opacity(0.6))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(text(MusicTrackQuality.labelKey(tier))).font(.headline)
                    Text(text(MusicTrackQuality.helpKey(tier))).font(.caption).foregroundStyle(.secondary)
                }
            }
            stage(text("music.quality.source"), help: nil) {
                if let format = quality?.format { row("music.quality.codec", format) }
                if let depth = quality?.bitDepth {
                    row("music.quality.sourceDepth", DesktopInterfaceText.value("music.quality.bits", variables: ["depth": Self.number(depth)]))
                }
                if let rate = quality?.sampleRateHz { row("music.quality.decodedRate", MusicTrackQuality.sampleRateLabel(rate)) }
                if let bitrate = quality?.bitrateKbps { row("music.quality.bitrate", String(Int(bitrate.rounded())) + " kbps") }
                if quality == nil { Text(text("music.quality.unavailable")).font(.caption).foregroundStyle(.secondary) }
            }
            stage(text("music.quality.output"), help: text("music.quality.outputHelp")) {
                row("music.quality.selectedOutput", !route.isEmpty ? route : text(settings?.device == "auto" ? "music.audio.system" : "music.quality.unavailable"))
                if let outputRate { row("music.quality.outputRate", MusicTrackQuality.sampleRateLabel(outputRate)) }
                if let settings {
                    row("music.lab.equalizer", text(settings.eqEnabled && !settings.dspBypass ? (settings.eqMode == "parametric" ? "music.lab.parametric" : "music.audio.equalizer") : "music.audio.replayOff"))
                    row("music.audio.replayGain", text(settings.replayGain == "off" || settings.dspBypass ? "music.audio.replayOff" : settings.replayGain == "track" ? "music.audio.replayTrack" : "music.audio.replayAlbum"))
                    row("music.lab.crossfeed", settings.dspBypass ? "0%" : String(Int((settings.crossfeed * 100).rounded())) + "%")
                }
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .contain).accessibilityLabel(text("music.quality.title")).accessibilityIdentifier("music-signal-details")
            .task(id: (player.currentItem?.id ?? "") + "|" + String(player.loaded)) {
                // The actual negotiated output rate, read from the playing decoder.
                let rate = await player.audioSignal()?.outputRate
                guard !Task.isCancelled else { return }
                outputRate = rate.flatMap { $0 > 0 && $0 <= 3_072_000 ? $0 : nil }
            }
    }
    private func stage<Content: View>(_ title: String, help: String?, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                Text(title).font(.subheadline.weight(.semibold))
                if let help { Image(systemName: "info.circle").font(.caption2).foregroundStyle(.secondary).accessibilityLabel(help) }
            }
            content()
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private func row(_ key: String, _ value: String) -> some View {
        LabeledContent(text(key), value: value).font(.caption)
    }
    private static func number(_ value: Double) -> String {
        value.rounded() == value && abs(value) < 1_000_000 ? String(Int(value)) : String(value)
    }
}

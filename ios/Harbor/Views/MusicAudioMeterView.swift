import SwiftUI

enum MusicMeterPresentation: Equatable { case levels, spectrum }

@MainActor struct MusicAudioMeterView: View {
    let player: MusicPlayback
    var presentation = MusicMeterPresentation.levels
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var measurement: MusicMeterMeasurement?
    @State private var measuredTrack = ""
    @State private var failed = false
    private var playing: Bool { scenePhase == .active && player.phase == .playing && (presentation == .levels || !reduceMotion) }
    private var trackKey: String { player.currentItem?.id ?? "" }
    private var activity: String { trackKey + "|" + String(playing) + "|" + String(reduceMotion) }
    var body: some View {
        Group {
            if presentation == .spectrum { spectrum.accessibilityHidden(true) }
            else { levels }
        }.task(id: activity) {
            if measuredTrack != trackKey { measurement = nil; measuredTrack = trackKey; failed = false }
            guard playing else { return }
            let lease = player.acquireMeter()
            defer { Task { @MainActor in await player.releaseMeter(lease) } }
            var retry = 100
            while !Task.isCancelled {
                do {
                    let value = try await player.meterSnapshot(lease)
                    guard value?.trackID == player.currentTrack?.id, value?.connectorID == player.currentTrack?.connectorId else { throw CancellationError() }
                    measurement = value?.measurement; failed = false; retry = 100
                    try await Task.sleep(for: .milliseconds(reduceMotion ? 200 : 50))
                } catch is CancellationError { return }
                catch {
                    failed = true; measurement = nil
                    do { try await Task.sleep(for: .milliseconds(retry)) } catch { return }
                    retry = min(2000, retry * 2)
                }
            }
        }
    }
    private var live: Bool { playing && measurement?.active == true }
    private func text(_ key: String) -> String { DesktopInterfaceText.value(key) }
    private var levels: some View {
        VStack(spacing: 8) {
            HStack {
                Text(text("music.quality.levels")); Spacer()
                Text(!playing ? text("music.quality.inactive") : measurement?.channels.isEmpty == false ? "dBFS" : text(failed || measurement != nil ? "music.quality.unavailable" : "Loading"))
                    .foregroundStyle(.secondary)
            }.font(.caption)
            if let channels = measurement?.channels, !channels.isEmpty {
                VStack(spacing: 7) {
                    ForEach(channels.indices, id: \.self) { index in
                        HStack(spacing: 8) {
                            Text(channels.count == 2 ? (index == 0 ? "L" : "R") : String(index + 1)).frame(width: 14)
                            GeometryReader { geometry in
                                ZStack(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 2).fill(ThemePreferences.shared.color("raised"))
                                    RoundedRectangle(cornerRadius: 2).fill(ThemePreferences.shared.color("ink-muted"))
                                        .frame(width: geometry.size.width * CGFloat(fraction(channels[index].rmsDb)))
                                        .animation(reduceMotion ? nil : .linear(duration: 0.095), value: fraction(channels[index].rmsDb))
                                    if live { Rectangle().fill(HarborTheme.accent).frame(width: 2).offset(x: max(0, geometry.size.width * CGFloat(fraction(channels[index].peakDb)) - 2)) }
                                }
                            }.frame(height: 8).accessibilityElement(children: .ignore)
                                .accessibilityLabel(DesktopInterfaceText.value("music.quality.channel", variables: ["number": String(index + 1)]))
                                .accessibilityValue(live ? channels[index].rmsDb.formatted(.number.precision(.fractionLength(1))) + " dBFS RMS" : text("music.quality.inactive"))
                            Text(live ? channels[index].rmsDb.formatted(.number.precision(.fractionLength(1))) : "—").frame(width: 42, alignment: .trailing)
                        }
                    }
                    HStack { Text("−60"); Spacer(); Text("−30"); Spacer(); Text("0") }.padding(.leading, 22).padding(.trailing, 50).foregroundStyle(.secondary)
                }.font(.caption2.monospacedDigit()).environment(\.layoutDirection, .leftToRight)
            }
            Text(text("music.quality.meterHelp")).font(.caption2).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
        }.accessibilityIdentifier("music-native-levels")
    }
    private var spectrum: some View {
        GeometryReader { geometry in
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(0..<8, id: \.self) { index in
                    let level = live && measurement?.spectrumDb.count == 8 ? measurement?.spectrumDb[index] ?? -120 : -120
                    let amplitude = live ? pow(min(1, max(0, (level + 60) / 50)), 1.5) : 0
                    MusicSpectrumBar(amplitude: amplitude,
                                     resting: !live || measurement?.spectrumDb.contains(where: { $0 > -60 }) != true,
                                     reduceMotion: reduceMotion)
                        .frame(height: geometry.size.height)
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }.environment(\.layoutDirection, .leftToRight).accessibilityIdentifier("music-native-spectrum")
    }
    private func fraction(_ db: Double) -> Double { live && db.isFinite ? min(1, max(0, (db + 60) / 60)) : 0 }
}

private struct MusicSpectrumBar: View {
    let amplitude: Double
    let resting: Bool
    let reduceMotion: Bool
    @State private var height = 0.08
    @State private var opacity = 0.25
    var body: some View {
        RoundedRectangle(cornerRadius: 2).fill(ThemePreferences.shared.color("ink-muted"))
            .overlay { RoundedRectangle(cornerRadius: 2).fill(HarborTheme.accent.opacity(0.35)) }
            .scaleEffect(x: 1, y: height, anchor: .bottom).opacity(opacity)
            .onChange(of: amplitude, initial: true) { previous, next in
                withAnimation(reduceMotion ? nil : .easeOut(duration: next > previous ? 0.045 : 0.180)) {
                    height = 0.08 + next * 0.92
                }
                updateOpacity()
            }
            .onChange(of: resting) { _, _ in updateOpacity() }
    }
    private func updateOpacity() {
        withAnimation(reduceMotion ? nil : .linear(duration: 0.080)) {
            opacity = resting ? 0.25 : 0.55 + amplitude * 0.45
        }
    }
}

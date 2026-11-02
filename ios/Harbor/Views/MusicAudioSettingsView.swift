import AVKit
import SwiftUI

@MainActor struct MusicAudioSettingsView: View {
    let session: MusicPlaybackSession
    @Bindable var player: MusicPlayback
    @State private var draft = MusicAudioOptions()
    @State private var name = ""
    @State private var failed = false
    @State private var saved = false
    @State private var signal: MusicAudioSignal?
    @Environment(\.dismiss) private var dismiss
    private func text(_ key: String) -> String { DesktopInterfaceText.value(key) }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(text("music.audio.scope")).font(.footnote)
                    Text(text("music.audio.spotify")).font(.footnote).foregroundStyle(.secondary)
                    HStack { Text(text("music.audio.output")); Spacer(); MusicOutputPicker().frame(width: 44, height: 44) }
                    TextField(text("music.audio.equipment"), text: $draft.equipmentLabel)
                    Text(text("music.audio.equipmentHelp")).font(.caption).foregroundStyle(.secondary)
                }
                Section(text("music.lab.equalizer")) {
                    Toggle(text("music.lab.bypass"), isOn: $draft.dspBypass)
                    Text(text("music.lab.bypassHelp")).font(.caption).foregroundStyle(.secondary)
                    Toggle(text("music.audio.equalizer"), isOn: $draft.eqEnabled)
                    Picker(text("music.audio.presets"), selection: preset) {
                        Text(text("music.eq.preset.custom")).tag("custom")
                        ForEach(MusicEQPresetCatalog.original?.presets ?? []) { value in Text(text(value.labelKey)).tag(value.id) }
                    }.disabled(draft.dspBypass)
                    MusicGraphicEQ(bands: $draft.eqBands).disabled(draft.dspBypass || !draft.eqEnabled)
                    ForEach(Array(MusicEQPresetCatalog.frequencies.enumerated()), id: \.offset) { index, frequency in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(frequency.formatted() + " Hz"); Spacer()
                                Text(String(format: "%+.1f dB", draft.eqBands[index])).monospacedDigit()
                            }.font(.caption)
                            Slider(value: $draft.eqBands[index], in: -12...12, step: 0.5)
                                .accessibilityLabel(DesktopInterfaceText.value("music.audio.band", variables: ["frequency": frequency.formatted()]))
                        }.disabled(draft.dspBypass || !draft.eqEnabled)
                    }
                    Button(text("music.audio.reset")) { draft.eqMode = "graphic"; draft.eqBands = Array(repeating: 0, count: 10) }
                    Toggle(text("music.audio.headroom"), isOn: $draft.autoHeadroom).disabled(draft.dspBypass)
                    Text(text("music.audio.headroomHelp")).font(.caption).foregroundStyle(.secondary)
                    dial("music.lab.preamp", value: $draft.preampDb, range: -60...12, step: 0.5, unit: " dB")
                }
                Section(text("music.audio.title")) {
                    dial("music.audio.balance", value: $draft.balance, range: -1...1, step: 0.05, unit: "")
                    Text(text("music.audio.balanceHelp")).font(.caption).foregroundStyle(.secondary)
                    Picker(text("music.audio.replayGain"), selection: $draft.replayGain) {
                        Text(text("music.audio.replayOff")).tag("off")
                        Text(text("music.audio.replayTrack")).tag("track")
                        Text(text("music.audio.replayAlbum")).tag("album")
                    }.disabled(draft.dspBypass)
                    Text(text("music.audio.replayHelp")).font(.caption).foregroundStyle(.secondary)
                    Toggle(text("music.audio.boost"), isOn: $draft.boostEnabled)
                    if draft.boostEnabled { dial("music.audio.ceiling", value: $draft.volumeLimit, range: 1...5, step: 0.1, unit: "×") }
                    Text(text("music.audio.boostHelp")).font(.caption).foregroundStyle(.secondary)
                }
                Section(text("music.speed.title")) {
                    dial("music.speed.speed", value: $draft.speed, range: 0.5...1.6, step: 0.01, unit: "×")
                    Toggle(text("music.speed.keepPitch"), isOn: $draft.keepPitch)
                    Text(text("music.speed.keepPitchHelp")).font(.caption).foregroundStyle(.secondary)
                    dial("music.speed.pitch", value: $draft.pitch, range: -12...12, step: 0.5, unit: "")
                    Button(text("music.speed.reset")) { draft.speed = 1; draft.pitch = 0; draft.keepPitch = false }
                }
                if let signal {
                    Section(text("music.now.signal")) {
                        if let codec = signal.codec { LabeledContent(text("music.quality.codec"), value: codec) }
                        if let rate = signal.sourceRate { LabeledContent(text("Source"), value: rate.formatted() + " Hz · " + (signal.sourceChannels ?? "—")) }
                        if let rate = signal.outputRate { LabeledContent(text("music.lab.sampleRate"), value: rate.formatted() + " Hz · " + (signal.outputChannels ?? "—")) }
                        if let bitrate = signal.bitrate, bitrate > 0 { LabeledContent(text("music.quality.bitrate"), value: (bitrate / 1000).formatted(.number.precision(.fractionLength(0))) + " kbps") }
                        LabeledContent(text("music.audio.output"), value: AVAudioSession.sharedInstance().currentRoute.outputs.map(\.portName).joined(separator: ", "))
                    }
                }
                if let preferences = session.audio {
                    Section(text("music.lab.profiles")) {
                        Text(text("music.lab.profilesHelp")).font(.caption).foregroundStyle(.secondary)
                        TextField(text("music.lab.profileName"), text: $name)
                        Button(text("music.lab.saveProfile")) {
                            do { try session.validate(); try preferences.saveProfile(name: name, settings: draft); name = "" }
                            catch { failed = true }
                        }.disabled(!preferences.profilesReady || preferences.profiles.count >= 20 || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        ForEach(preferences.profiles) { profile in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(profile.name)
                                    Button(text("music.lab.loadProfile")) { draft = profile.loading(into: draft); saved = false }
                                        .font(.caption).buttonStyle(.borderless)
                                }
                                Spacer()
                                Button(role: .destructive) {
                                    do { try session.validate(); try preferences.deleteProfile(profile.id) } catch { failed = true }
                                } label: { Image(systemName: "trash").frame(width: 44, height: 44) }.buttonStyle(.borderless).accessibilityLabel(text("music.lab.delete") + " " + profile.name)
                            }
                        }
                    }
                }
                Section {
                    if failed { Text(text("music.audio.saveError")).foregroundStyle(.orange) }
                    if saved { Label(text("music.audio.saved"), systemImage: "checkmark.circle").foregroundStyle(.secondary) }
                    Button(player.audioApplying ? text("music.audio.saving") : text("music.audio.apply")) {
                        failed = false; saved = false
                        Task { @MainActor in
                            do { try await player.applyAudio(draft, using: session); draft = session.audio?.options ?? draft; saved = true }
                            catch is CancellationError { }
                            catch { failed = true }
                        }
                    }.disabled(player.audioApplying || session.audio == nil)
                }
            }.navigationTitle(text("music.audio.title")).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button(text("Close")) { dismiss() } } }
        }.onAppear { draft = session.audio?.options ?? .init() }
            .task { while !Task.isCancelled { signal = await player.audioSignal(); do { try await Task.sleep(for: .seconds(1)) } catch { return } } }
            .onChange(of: draft) { _, _ in saved = false }
            .accessibilityIdentifier("music-audio-settings")
    }
    private var preset: Binding<String> {
        Binding(get: {
            guard draft.eqMode == "graphic" else { return "custom" }
            return MusicEQPresetCatalog.original?.presets.first { value in zip(value.bands, draft.eqBands).allSatisfy { abs($0.0 - $0.1) < 0.25 } }?.id ?? "custom"
        }, set: { id in
            guard let value = MusicEQPresetCatalog.original?.presets.first(where: { $0.id == id }) else { return }
            draft.eqMode = "graphic"; draft.eqBands = value.bands; draft.eqEnabled = true
        })
    }
    private func dial(_ key: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double, unit: String) -> some View {
        VStack(alignment: .leading) {
            HStack { Text(text(key)); Spacer(); Text(value.wrappedValue.formatted(.number.precision(.fractionLength(0...2))) + unit).monospacedDigit() }.font(.subheadline)
            Slider(value: value, in: range, step: step).accessibilityLabel(text(key))
        }.disabled(draft.dspBypass && key != "music.audio.ceiling" && key != "music.speed.speed")
    }
}

/// The same Catmull–Rom graphic-EQ curve as Desktop, with native touch handles.
private struct MusicGraphicEQ: View {
    @Binding var bands: [Double]
    @State private var dragging: Int?
    var body: some View {
        GeometryReader { geometry in
            let inset = 14.0, width = max(1, geometry.size.width - inset * 2), height = geometry.size.height - 24
            let points = bands.enumerated().map { index, gain in CGPoint(x: inset + width * Double(index) / 9, y: 12 + height / 2 - min(12, max(-12, gain)) / 12 * height / 2) }
            ZStack {
                Path { path in
                    for gain in [-12.0, 0, 12] { let y = 12 + height / 2 - gain / 12 * height / 2; path.move(to: CGPoint(x: inset, y: y)); path.addLine(to: CGPoint(x: inset + width, y: y)) }
                }.stroke(.secondary.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
                Path { path in
                    guard let first = points.first else { return }; path.move(to: first)
                    for index in 0..<(points.count - 1) {
                        let p0 = points[max(0, index - 1)], p1 = points[index], p2 = points[index + 1], p3 = points[min(points.count - 1, index + 2)]
                        path.addCurve(to: p2, control1: CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6), control2: CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6))
                    }
                }.stroke(HarborTheme.accent, lineWidth: 2)
                ForEach(points.indices, id: \.self) { index in Circle().fill(HarborTheme.accent).frame(width: 9, height: 9).position(points[index]) }
            }.contentShape(.rect).gesture(DragGesture(minimumDistance: 0).onChanged { event in
                let index = dragging ?? min(9, max(0, Int(((event.location.x - inset) / width * 9).rounded())))
                dragging = index
                bands[index] = (min(12, max(-12, ((12 + height / 2 - event.location.y) / (height / 2)) * 12)) * 2).rounded() / 2
            }.onEnded { _ in dragging = nil })
        }.frame(height: 160).accessibilityHidden(true)
    }
}

@MainActor struct MusicOutputPicker: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView(); view.prioritizesVideoDevices = false
        view.accessibilityLabel = DesktopInterfaceText.value("music.audio.output")
        view.accessibilityIdentifier = "music-airplay-output"
        return view
    }
    func updateUIView(_ view: AVRoutePickerView, context: Context) { }
}

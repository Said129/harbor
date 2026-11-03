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
    @State private var effectsOwner = UUID()
    @Environment(\.dismiss) private var dismiss
    private func text(_ key: String) -> String { DesktopInterfaceText.value(key) }
    var body: some View {
        NavigationStack {
            Form {
                outputSection
                equalizerSection
                processingSection
                speedSection
                savedSpeedSection
                if player.playbackSession === session, player.currentItem != nil, session.audio != nil {
                    MusicBeatEffectsSection(player: player, session: session, owner: effectsOwner)
                }
                signalSection
                profilesSection
                saveSection
            }.navigationTitle(text("music.audio.title")).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button(text("Close")) { dismiss() } } }
        }.onAppear { draft = session.audio?.options ?? .init() }
            .onDisappear { Task { await player.endEffects(effectsOwner, using: session) } }
            .task { while !Task.isCancelled { signal = await player.audioSignal(); do { try await Task.sleep(for: .seconds(1)) } catch { return } } }
            .onChange(of: draft) { _, _ in saved = false }
            .accessibilityIdentifier("music-audio-settings")
    }
    @ViewBuilder private var outputSection: some View {
        Section {
            Text(text("music.audio.scope")).font(.footnote)
            Text(text("music.audio.spotify")).font(.footnote).foregroundStyle(.secondary)
            HStack { Text(text("music.audio.output")); Spacer(); MusicOutputPicker().frame(width: 44, height: 44) }
            Picker(text("music.lab.sampleRate"), selection: $draft.sampleRate) {
                Text(text("music.lab.sourceRate")).tag(0)
                ForEach([44100, 48000, 88200, 96000, 176400, 192000], id: \.self) { rate in Text((Double(rate) / 1000).formatted() + " kHz").tag(rate) }
            }
            Text(text("music.lab.rateHelp")).font(.caption).foregroundStyle(.secondary)
            TextField(text("music.audio.equipment"), text: $draft.equipmentLabel)
            Text(text("music.audio.equipmentHelp")).font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var equalizerSection: some View {
        Section(text("music.lab.equalizer")) {
            Toggle(text("music.lab.bypass"), isOn: $draft.dspBypass)
            Text(text("music.lab.bypassHelp")).font(.caption).foregroundStyle(.secondary)
            Toggle(text("music.audio.equalizer"), isOn: $draft.eqEnabled)
            VStack(alignment: .leading, spacing: 6) {
                Text(text("music.lab.mode"))
                Picker(text("music.lab.mode"), selection: $draft.eqMode) {
                    Text(text("music.audio.equalizer")).tag("graphic")
                    Text(text("music.lab.parametric")).tag("parametric")
                }.labelsHidden()
            }.disabled(draft.dspBypass)
            Picker(text("music.audio.presets"), selection: preset) {
                Text(text("music.eq.preset.custom")).tag("custom")
                ForEach(MusicEQPresetCatalog.original?.presets ?? []) { value in Text(text(value.labelKey)).tag(value.id) }
            }.disabled(draft.dspBypass)
            if draft.eqMode == "parametric" {
                MusicParametricEditor(draft: $draft, applied: session.audio?.options ?? .init())
            } else {
                graphicEqualizer
            }
            Button(text("music.audio.reset")) {
                if draft.eqMode == "parametric" { draft.peqFilters = [] }
                else { draft.eqBands = Array(repeating: 0, count: 10) }
            }
            Toggle(text("music.audio.headroom"), isOn: $draft.autoHeadroom).disabled(draft.dspBypass)
            Text(text("music.audio.headroomHelp")).font(.caption).foregroundStyle(.secondary)
            dial("music.lab.preamp", value: $draft.preampDb, range: -60...12, step: 0.5, unit: " dB")
        }
    }

    @ViewBuilder private var graphicEqualizer: some View {
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
    }

    @ViewBuilder private var processingSection: some View {
        Section(text("music.audio.title")) {
            dial("music.audio.balance", value: $draft.balance, range: -1...1, step: 0.05, unit: "")
            Text(text("music.audio.balanceHelp")).font(.caption).foregroundStyle(.secondary)
            if MusicAudioRuntime.supports(["crossfeed"]) {
                dial("music.lab.crossfeed", value: $draft.crossfeed, range: 0...1, step: 0.01, unit: "", percentage: true)
                Text(text("music.lab.crossfeedHelp")).font(.caption).foregroundStyle(.secondary)
            }
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
    }

    @ViewBuilder private var speedSection: some View {
        Section(text("music.speed.title")) {
            speedPresets
            dial("music.speed.speed", value: $draft.speed, range: 0.5...1.6, step: 0.01, unit: "×")
            Toggle(text("music.speed.keepPitch"), isOn: $draft.keepPitch)
            Text(text("music.speed.keepPitchHelp")).font(.caption).foregroundStyle(.secondary)
            dial("music.speed.pitch", value: $draft.pitch, range: -12...12, step: 0.5, unit: "")
            if MusicAudioRuntime.supports(["aecho"]) {
                dial("music.speed.reverb", value: $draft.reverb, range: 0...1, step: 0.01, unit: "", percentage: true)
            }
            Button(text("music.speed.reset")) { draft.speed = 1; draft.pitch = 0; draft.reverb = 0; draft.keepPitch = false }
        }
    }

    private var speedPresets: some View {
        ScrollView(.horizontal) {
            HStack {
                speedPreset("music.speed.normal", speed: 1, reverb: 0)
                speedPreset("music.speed.nightcore", speed: 1.25, reverb: 0)
                speedPreset("music.speed.slowed", speed: 0.85, reverb: 0)
                if MusicAudioRuntime.supports(["aecho"]) {
                    speedPreset("music.speed.slowedReverb", speed: 0.8, reverb: 0.6)
                    speedPreset("music.speed.daycore", speed: 0.75, reverb: 0.3)
                }
            }.padding(.vertical, 3)
        }.scrollIndicators(.hidden)
    }
    private func speedPreset(_ label: String, speed: Double, reverb: Double) -> some View {
        let active = abs(draft.speed - speed) < 0.001 && abs(draft.reverb - reverb) < 0.001 && abs(draft.pitch) < 0.001 && !draft.keepPitch
        return Button(text(label)) { draft.speed = speed; draft.reverb = reverb; draft.pitch = 0; draft.keepPitch = false }
            .buttonStyle(.bordered).tint(active ? HarborTheme.accent : .secondary)
            .accessibilityAddTraits(active ? .isSelected : [])
    }

    @ViewBuilder private var savedSpeedSection: some View {
        if let preferences = session.audio {
            MusicSavedSpeedPresets(draft: $draft, preferences: preferences, validate: { try session.validate() })
        }
    }

    @ViewBuilder private var signalSection: some View {
        if let signal {
            Section(text("music.now.signal")) {
                if let codec = signal.codec { LabeledContent(text("music.quality.codec"), value: codec) }
                if let rate = signal.sourceRate { LabeledContent(text("Source"), value: rate.formatted() + " Hz · " + (signal.sourceChannels ?? "—")) }
                if let rate = signal.outputRate { LabeledContent(text("music.lab.sampleRate"), value: rate.formatted() + " Hz · " + (signal.outputChannels ?? "—")) }
                if let bitrate = signal.bitrate, bitrate > 0 { LabeledContent(text("music.quality.bitrate"), value: (bitrate / 1000).formatted(.number.precision(.fractionLength(0))) + " kbps") }
                LabeledContent(text("music.audio.output"), value: AVAudioSession.sharedInstance().currentRoute.outputs.map(\.portName).joined(separator: ", "))
            }
        }
    }

    @ViewBuilder private var profilesSection: some View {
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
    }

    @ViewBuilder private var saveSection: some View {
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
    }

    private var preset: Binding<String> {
        Binding(get: {
            if draft.eqMode == "parametric" {
                return MusicEQPresetCatalog.original?.presets.first { value in
                    value.filters.count == draft.peqFilters.count && value.filters.allSatisfy { wanted in
                        draft.peqFilters.contains { have in
                            have.type == wanted.type && abs(have.frequency - wanted.frequency) < 0.5 && abs(have.gain - wanted.gain) < 0.25 && abs(have.q - wanted.q) < 0.05
                        }
                    }
                }?.id ?? "custom"
            }
            return MusicEQPresetCatalog.original?.presets.first { value in zip(value.bands, draft.eqBands).allSatisfy { abs($0.0 - $0.1) < 0.25 } }?.id ?? "custom"
        }, set: { id in
            guard let value = MusicEQPresetCatalog.original?.presets.first(where: { $0.id == id }) else { return }
            if draft.eqMode == "parametric" { draft.peqFilters = value.filters }
            else { draft.eqBands = value.bands }
            draft.eqEnabled = true
        })
    }
    private func dial(_ key: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double, unit: String, percentage: Bool = false) -> some View {
        VStack(alignment: .leading) {
            HStack {
                Text(text(key)); Spacer()
                Text(percentage ? value.wrappedValue.formatted(.percent.precision(.fractionLength(0))) : value.wrappedValue.formatted(.number.precision(.fractionLength(0...2))) + unit).monospacedDigit()
            }.font(.subheadline)
            Slider(value: value, in: range, step: step).accessibilityLabel(text(key))
        }.disabled(draft.dspBypass && key != "music.audio.ceiling" && key != "music.speed.speed")
    }
}

@MainActor struct MusicSavedSpeedPresets: View {
    @Binding var draft: MusicAudioOptions
    let preferences: MusicAudioPreferences
    let validate: @MainActor () throws -> Void
    @State private var name = ""
    @State private var failed = false
    private func text(_ key: String) -> String { DesktopInterfaceText.value(key) }
    var body: some View {
        Section(text("music.speed.saveCurrent")) {
            TextField(text("music.speed.namePlaceholder"), text: $name)
            Button(text("music.speed.save")) {
                do { try validate(); try preferences.saveSpeedPreset(name: name, settings: draft); name = ""; failed = false }
                catch { failed = true }
            }.disabled(!preferences.speedPresetsReady || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            ForEach(preferences.speedPresets) { preset in
                HStack {
                    Button(preset.name) { draft = preset.loading(into: draft) }.buttonStyle(.borderless)
                    Spacer()
                    Button(role: .destructive) {
                        do { try validate(); try preferences.deleteSpeedPreset(preset.id); failed = false }
                        catch { failed = true }
                    } label: { Image(systemName: "trash").frame(width: 44, height: 44) }
                        .buttonStyle(.borderless).accessibilityLabel(DesktopInterfaceText.value("music.speed.forget", variables: ["name": preset.name]))
                }
            }
            if failed { Text(text("music.audio.saveError")).foregroundStyle(.orange) }
        }
    }
}

/// The same Catmull–Rom graphic-EQ curve as Desktop, with native touch handles.
private struct MusicGraphicEQ: View {
    @Binding var bands: [Double]
    @State private var dragging: Int?
    var body: some View {
        GeometryReader { geometry in
            let inset: CGFloat = 14
            let width: CGFloat = max(1, geometry.size.width - inset * 2)
            let height: CGFloat = geometry.size.height - 24
            let points: [CGPoint] = bands.enumerated().map { index, gain in
                let x = inset + width * CGFloat(index) / 9
                let y = 12 + height / 2 - CGFloat(min(12, max(-12, gain))) / 12 * height / 2
                return CGPoint(x: x, y: y)
            }
            ZStack {
                Path { path in
                    for gain in [CGFloat(-12), CGFloat(0), CGFloat(12)] { let y = 12 + height / 2 - gain / 12 * height / 2; path.move(to: CGPoint(x: inset, y: y)); path.addLine(to: CGPoint(x: inset + width, y: y)) }
                }.stroke(Color.secondary.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
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
                let gain = Double((12 + height / 2 - event.location.y) / (height / 2)) * 12
                bands[index] = (min(12, max(-12, gain)) * 2).rounded() / 2
            }.onEnded { _ in dragging = nil })
        }.frame(height: 160).environment(\.layoutDirection, .leftToRight).accessibilityHidden(true)
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

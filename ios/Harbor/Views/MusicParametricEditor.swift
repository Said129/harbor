import SwiftUI

@MainActor struct MusicParametricEditor: View {
    @Binding var draft: MusicAudioOptions
    let applied: MusicAudioOptions
    @State private var response: MusicEQResponse?
    @State private var correction = ""
    @State private var invalid = false
    @State private var responseFailed = false
    private let processor = MusicParametricEQ()
    private func text(_ key: String) -> String { DesktopInterfaceText.value(key) }

    var body: some View {
        Group {
            MusicParametricCurve(response: response)
            Text(DesktopInterfaceText.value("music.lab.curveHelp", variables: ["rate": Double(draft.sampleRate == 0 ? 48000 : draft.sampleRate).formatted(.number.scale(0.001))]))
                .font(.caption).foregroundStyle(.secondary)
            if responseFailed { Text(text("music.audio.saveError")).foregroundStyle(.orange) }
            VStack(alignment: .leading) {
                HStack { Text(text("music.lab.strength")); Spacer(); Text(draft.eqStrength.formatted(.percent.precision(.fractionLength(0)))).monospacedDigit() }
                Slider(value: $draft.eqStrength, in: 0...1, step: 0.01).accessibilityLabel(text("music.lab.strength"))
            }
            Text(text("music.lab.strengthHelp")).font(.caption).foregroundStyle(.secondary)
            ForEach(Array(draft.peqFilters.indices), id: \.self) { index in
                NavigationLink {
                    MusicParametricFilterEditor(filter: binding(index), index: index)
                } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(text("music.lab.filter") + " \(index + 1) · " + text("music.lab." + draft.peqFilters[index].type))
                        Text(summary(draft.peqFilters[index])).font(.caption).foregroundStyle(.secondary)
                    }
                }.accessibilityIdentifier("music-peq-filter-\(index)")
                    .swipeActions { Button(role: .destructive) { draft.peqFilters.remove(at: index) } label: { Label(text("music.lab.delete"), systemImage: "trash") } }
            }
            HStack {
                Button { draft.peqFilters.append(.init()) } label: { Label(text("music.lab.addFilter"), systemImage: "plus") }
                    .disabled(draft.peqFilters.count >= 24).accessibilityIdentifier("music-peq-add")
                Spacer(); Text("\(draft.peqFilters.count) / 24").foregroundStyle(.secondary).font(.caption)
            }
            Text(DesktopInterfaceText.value("music.lab.headroomHelp", variables: ["db": (response?.headroom ?? 0).formatted(.number.precision(.fractionLength(1)))]))
                .font(.caption).foregroundStyle(.secondary)
            DisclosureGroup(text("music.lab.importExport")) { correctionEditor }
        }.disabled(draft.dspBypass || !draft.eqEnabled)
            .task(id: [draft, applied]) {
                do {
                    try await Task.sleep(for: .milliseconds(140))
                    let next = try processor.response(draft, applied: applied)
                    try Task.checkCancellation(); response = next; responseFailed = false
                } catch is CancellationError { }
                catch { responseFailed = true }
            }
    }

    private var correctionEditor: some View {
        Group {
            Text(text("music.lab.importHelp")).font(.caption).foregroundStyle(.secondary)
            TextEditor(text: $correction).font(.system(.caption, design: .monospaced)).frame(minHeight: 160)
                .autocorrectionDisabled().textInputAutocapitalization(.never)
                .accessibilityLabel(text("music.lab.correctionText"))
                .onChange(of: correction) { _, value in
                    if value.count > 32768 { correction = String(value.prefix(32768)) }
                    invalid = false
                }
            Button(text("music.lab.import")) {
                do { draft = try processor.importText(correction).loading(into: draft); invalid = false }
                catch { invalid = true }
            }.disabled(correction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Button(text("music.lab.export")) {
                do { correction = try processor.exportText(draft); invalid = false }
                catch { invalid = true }
            }.disabled(draft.peqFilters.isEmpty)
            if !correction.isEmpty { ShareLink(item: correction) { Label(text("music.lab.export"), systemImage: "square.and.arrow.up") } }
            if invalid { Text(text("music.lab.importError")).foregroundStyle(.orange) }
        }
    }
    private func binding(_ index: Int) -> Binding<MusicPEQFilter> {
        Binding(get: { draft.peqFilters.indices.contains(index) ? draft.peqFilters[index] : .init() },
                set: { if draft.peqFilters.indices.contains(index) { draft.peqFilters[index] = $0 } })
    }
    private func summary(_ value: MusicPEQFilter) -> String {
        let status = value.enabled ? text("music.lab.enabled") : text("Off")
        return status + " · " + value.frequency.formatted() + " Hz · " + value.gain.formatted(.number.precision(.fractionLength(1))) + " dB · Q " + value.q.formatted(.number.precision(.fractionLength(2)))
    }
}

@MainActor struct MusicParametricFilterEditor: View {
    @Binding var filter: MusicPEQFilter
    let index: Int
    private let types = ["peak", "lowShelf", "highShelf", "lowPass", "highPass", "notch"]
    private func text(_ key: String) -> String { DesktopInterfaceText.value(key) }
    var body: some View {
        Form {
            Toggle(text("music.lab.enabled"), isOn: $filter.enabled)
            Picker(text("music.lab.filter"), selection: $filter.type) {
                ForEach(types, id: \.self) { value in Text(text("music.lab." + value)).tag(value) }
            }
            MusicEQNumericField(label: "Hz", value: $filter.frequency, range: 20...20000, step: 1)
            MusicEQNumericField(label: "dB", value: $filter.gain, range: -18...18, step: 0.1)
                .disabled(!["peak", "lowShelf", "highShelf"].contains(filter.type))
            MusicEQNumericField(label: "Q", value: $filter.q, range: 0.1...12, step: 0.01)
        }.navigationTitle(text("music.lab.filter") + " \(index + 1)").navigationBarTitleDisplayMode(.inline)
            .accessibilityIdentifier("music-peq-filter-editor")
    }
}

private struct MusicEQNumericField: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    @State private var input = ""
    @FocusState private var editing: Bool
    var body: some View {
        HStack {
            Text(label); Spacer()
            TextField(label, text: $input).keyboardType(.numbersAndPunctuation).multilineTextAlignment(.trailing)
                .focused($editing).submitLabel(.done).onSubmit { commit(); editing = false }
                .accessibilityLabel(label)
            Stepper(label, value: $value, in: range, step: step).labelsHidden().accessibilityLabel(label)
        }.onAppear { input = formatted }
            .onChange(of: editing) { _, active in if !active { commit() } }
            .onChange(of: value) { _, _ in if !editing { input = formatted } }
    }
    private var formatted: String { value.formatted(.number.grouping(.never).precision(.fractionLength(0...4))) }
    private func commit() {
        if let parsed = try? Double(input, format: .number), parsed.isFinite { value = min(range.upperBound, max(range.lowerBound, parsed)) }
        input = formatted
    }
}

private struct MusicParametricCurve: View {
    let response: MusicEQResponse?
    var body: some View {
        VStack(spacing: 5) {
            GeometryReader { geometry in
                let width = max(1, geometry.size.width - 30), height = geometry.size.height
                ZStack {
                    ForEach([-24, -12, 0, 12, 24], id: \.self) { gain in
                        let y = height / 2 - CGFloat(gain) / 48 * height
                        Path { path in path.move(to: CGPoint(x: 30, y: y)); path.addLine(to: CGPoint(x: width + 30, y: y)) }
                            .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
                        Text(String(gain)).font(.system(size: 9)).foregroundStyle(.secondary).position(x: 12, y: y)
                    }
                    curve(response?.applied ?? [], width: width, height: height).stroke(Color.secondary, style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                    curve(response?.draft ?? [], width: width, height: height).stroke(HarborTheme.accent, lineWidth: 2)
                }
            }.frame(height: 140).padding(.vertical, 8)
            GeometryReader { geometry in
                ForEach([20.0, 100, 1000, 10000, 20000], id: \.self) { value in
                    Text(value >= 1000 ? (value / 1000).formatted() + "k" : value.formatted())
                        .font(.system(size: 9)).foregroundStyle(.secondary)
                        .position(x: 30 + max(1, geometry.size.width - 38) * CGFloat(log10(value / 20) / 3), y: 7)
                }
            }.frame(height: 14)
        }.accessibilityElement(children: .ignore).accessibilityLabel(DesktopInterfaceText.value("music.lab.response"))
    }
    private func curve(_ values: [Double], width: CGFloat, height: CGFloat) -> Path {
        Path { path in
            for (index, gain) in values.enumerated() where gain.isFinite {
                let point = CGPoint(x: 30 + width * CGFloat(index) / 360, y: height / 2 - CGFloat(min(24, max(-24, gain))) / 48 * height)
                if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
        }
    }
}

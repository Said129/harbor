import SwiftUI

/// The sleep timer section of Desktop's speed menu: 30 min, 1 hour, end of episode and end of the
/// next one, plus the minutes the user adds ("Customize").
struct SleepTimerSettings: View {
    private struct Row: Identifiable {
        let id: String
        let label: String
        let mode: SleepMode
        let custom: Bool
        var minutes: Int? { if case .minutes(let value) = mode { return value }; return nil }
    }
    private let timer = SleepTimer.shared
    @State private var custom = SleepTimer.customMinutes()
    @State private var editing = false
    @State private var draft = ""
    private func text(_ key: String) -> String { DesktopInterfaceText.value(key) }

    private var rows: [Row] {
        var minutes: [Int: Bool] = [:]
        for preset in SleepTimer.presets where SleepTimer.curatedIDs.contains(preset.id) {
            if case .minutes(let total) = preset.mode { minutes[total] = false }
        }
        for total in custom where minutes[total] == nil { minutes[total] = true }
        let minuteRows = minutes.sorted { $0.key < $1.key }.map {
            Row(id: "m\($0.key)", label: SleepTimer.minutesLabel($0.key), mode: .minutes($0.key), custom: $0.value)
        }
        let episodeRows = SleepTimer.presets.filter { SleepTimer.curatedIDs.contains($0.id) && $0.mode.minutesValue == nil }
            .map { Row(id: $0.id, label: text($0.label), mode: $0.mode, custom: false) }
        return minuteRows + episodeRows
    }
    private func selected(_ row: Row) -> Bool {
        switch (timer.mode, row.mode) {
        case (.minutes(let a), .minutes(let b)): a == b
        case (.endEpisode, .endEpisode): true
        case (.endNextEpisode, .endNextEpisode): true
        default: false
        }
    }

    var body: some View {
        HarborSettingsSection("Sleep timer") {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(rows) { row in
                    HStack(spacing: 4) {
                        Button { timer.set(row.mode) } label: {
                            HStack {
                                Text(row.label).font(HarborTheme.font(15, weight: selected(row) ? .semibold : .regular))
                                Spacer(minLength: 8)
                                if selected(row) {
                                    TimelineView(.periodic(from: .now, by: 1)) { context in
                                        if let hint = timer.badge(at: context.date), row.minutes != nil {
                                            Text(hint).font(HarborTheme.font(12, weight: .semibold)).monospacedDigit().foregroundStyle(.secondary)
                                        }
                                    }
                                    Image(systemName: "checkmark").font(.system(size: 13, weight: .bold)).foregroundStyle(HarborTheme.accent)
                                }
                            }.frame(minHeight: 44).contentShape(Rectangle())
                        }.buttonStyle(.plain).accessibilityAddTraits(selected(row) ? [.isSelected] : [])
                            .accessibilityIdentifier("sleep-timer-" + row.id)
                        if editing, row.custom, let minutes = row.minutes {
                            Button { SleepTimer.removeCustom(minutes); custom = SleepTimer.customMinutes() } label: {
                                Image(systemName: "xmark").font(.system(size: 13, weight: .semibold)).frame(width: 44, height: 44)
                            }.buttonStyle(.plain).accessibilityLabel(text("Remove preset"))
                        }
                    }
                }
            }
            if editing {
                HStack(spacing: 10) {
                    TextField(text("e.g. 20"), text: $draft).keyboardType(.numberPad).textFieldStyle(.roundedBorder).frame(minHeight: 44)
                        .accessibilityIdentifier("sleep-timer-custom-minutes")
                    Text(text("min")).font(HarborTheme.font(13)).foregroundStyle(.secondary)
                    Button(text("Add preset")) {
                        if let minutes = Int(draft.trimmingCharacters(in: .whitespaces)), SleepTimer.addCustom(minutes) {
                            custom = SleepTimer.customMinutes(); draft = ""
                        }
                    }.disabled(Int(draft.trimmingCharacters(in: .whitespaces)) == nil).accessibilityIdentifier("sleep-timer-add")
                }
            }
            HStack {
                if timer.isActive && !editing {
                    Button(text("Cancel timer"), role: .destructive) { timer.cancel() }.accessibilityIdentifier("sleep-timer-cancel")
                }
                Spacer(minLength: 0)
                Button(text(editing ? "Done" : "Customize")) { editing.toggle() }.accessibilityIdentifier("sleep-timer-customize")
            }
        }
    }
}

/// Desktop's "Customize" for speeds: add a speed such as 1.35, or remove the ones added.
struct CustomSpeedRow: View {
    let current: Double
    @State private var custom = PlaybackSpeeds.custom()
    @State private var draft = ""
    private func text(_ key: String) -> String { DesktopInterfaceText.value(key) }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                TextField(text("e.g. 1.35"), text: $draft).keyboardType(.decimalPad).textFieldStyle(.roundedBorder).frame(minHeight: 44)
                    .accessibilityIdentifier("custom-speed-field")
                Text("×").font(HarborTheme.font(13)).foregroundStyle(.secondary)
                Button(text("Add preset")) {
                    if let value = Double(draft.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")), PlaybackSpeeds.add(value) {
                        custom = PlaybackSpeeds.custom(); draft = ""
                    }
                }.accessibilityIdentifier("custom-speed-add")
            }
            ForEach(custom, id: \.self) { speed in
                HStack {
                    Text("\(speed.formatted())×").font(HarborTheme.font(14))
                    Spacer(minLength: 0)
                    Button { PlaybackSpeeds.remove(speed); custom = PlaybackSpeeds.custom() } label: {
                        Image(systemName: "xmark").font(.system(size: 13, weight: .semibold)).frame(width: 44, height: 44)
                    }.buttonStyle(.plain).accessibilityLabel(text("Remove preset"))
                }
            }
        }
    }
}

/// Desktop's A-B loop for touch: its Shift+I, Shift+O and Shift+L shortcuts become three buttons.
struct ABLoopSettings: View {
    let state: PlayerState
    private func text(_ key: String) -> String { DesktopInterfaceText.value(key) }

    private func apply() {
        let values = state.abLoop.mpvValues
        state.controller?.set("ab-loop-a", values.a)
        state.controller?.set("ab-loop-b", values.b)
    }
    var body: some View {
        HarborSettingsSection("A-B loop") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "repeat").font(.system(size: 13, weight: .semibold))
                    Text(state.abLoop.summary()).font(HarborTheme.font(15, weight: .medium)).monospacedDigit()
                        .accessibilityIdentifier("ab-loop-summary")
                    if state.abLoop.active { Text(text("Looping")).font(HarborTheme.font(12, weight: .semibold)).foregroundStyle(HarborTheme.accent) }
                }
                HStack(spacing: 10) {
                    Button(text("Set A")) { state.abLoop.setA(at: state.position); apply() }.accessibilityIdentifier("ab-loop-set-a")
                    Button(text("Set B")) { state.abLoop.setB(at: state.position); apply() }
                        .disabled(state.abLoop.a == nil).accessibilityIdentifier("ab-loop-set-b")
                    if state.abLoop.isSet {
                        Button(text("Clear A-B loop"), role: .destructive) { state.abLoop.clear(); apply() }.accessibilityIdentifier("ab-loop-clear")
                    }
                }
            }
        }
    }
}

private extension SleepMode {
    var minutesValue: Int? { if case .minutes(let value) = self { return value }; return nil }
}

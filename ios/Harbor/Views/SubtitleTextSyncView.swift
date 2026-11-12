import SwiftUI

/// Desktop's "Live sync" (`text-sync-overlay.tsx`): pick a line you can hear, align it to now, correct drift with a second line, nudge,
/// or shift one section. Saving writes a new synced track from the selected external subtitle and restores nothing by itself:
/// "Restore the original subtitle" in the subtitle panel brings the previous track back. Embedded tracks have no readable lines on iOS.
struct SubtitleTextSyncView: View {
    let state: PlayerState
    @Environment(\.dismiss) private var dismiss
    @State private var document: SubtitleDocument?
    @State private var session: SubtitleTextSyncSession?
    @State private var phase = Phase.loading
    @State private var query = ""
    @State private var selected: Int?
    @State private var sectionMode = false
    @State private var saveFailed = false

    private enum Phase { case loading, ready, unreadable }
    private func text(_ original: String) -> String { DesktopInterfaceText.value(original) }

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .loading:
                    ProgressView(text("Reading subtitles...")).frame(maxWidth: .infinity, maxHeight: .infinity)
                case .unreadable:
                    Text(text("Could not read this subtitle track. Pick a different subtitle, then try again."))
                        .multilineTextAlignment(.center).foregroundStyle(.secondary).padding(32)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .ready:
                    content
                }
            }
            .background(HarborTheme.background).foregroundStyle(HarborTheme.ink)
            .navigationTitle(sectionMode ? text("Fix one section") : text("Live sync")).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(text("Close")) { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
        .task { await load() }
        .accessibilityIdentifier("subtitle-text-sync")
    }

    @ViewBuilder private var content: some View {
        if let session {
            VStack(spacing: 0) {
                Text(hint(session)).font(HarborTheme.font(13)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 18).padding(.vertical, 10)
                searchField
                cueList(session)
                controls(session)
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            TextField(text("Search a line by its words"), text: $query)
                .textInputAutocapitalization(.never).autocorrectionDisabled().frame(minHeight: 44)
                .accessibilityIdentifier("subtitle-text-sync-search")
            if !query.isEmpty {
                Button { query = "" } label: { Image(systemName: "xmark.circle.fill").frame(width: 44, height: 44) }
                    .buttonStyle(.plain).accessibilityLabel(text("Clear search"))
            }
        }
        .padding(.horizontal, 14).background(HarborTheme.surface, in: .rect(cornerRadius: 10)).padding(.horizontal, 18).padding(.bottom, 8)
    }

    private func cueList(_ session: SubtitleTextSyncSession) -> some View {
        let active = SubtitleTextSync.activeIndex(in: session.corrected, position: state.position)
        let found = Set(session.matches(query))
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(session.texts.indices, id: \.self) { index in
                        row(session, index: index, active: active == index, found: found.contains(index))
                    }
                }
            }
            .onChange(of: query) { _, _ in
                if let first = session.matches(query).first { proxy.scrollTo(first, anchor: .center) }
            }
            .onAppear {
                if let active { proxy.scrollTo(active, anchor: .center) }
            }
        }
    }

    private func row(_ session: SubtitleTextSyncSession, index: Int, active: Bool, found: Bool) -> some View {
        let range = session.range
        let inRange = range.map { index >= $0.low && index <= $0.high } ?? false
        let isStart = session.rangeStart == index
        let fixed = session.segments.contains { index >= $0.startIndex && index <= $0.endIndex }
        let pointNumber = session.points.firstIndex { $0.t == session.cues[index].start }
        let highlighted = active || inRange || isStart
        return VStack(spacing: 0) {
            Button { tap(index) } label: {
                HStack(alignment: .top, spacing: 12) {
                    Text(SubtitleTextSync.clock(session.cues[index].start)).font(HarborTheme.font(12)).monospacedDigit()
                        .foregroundStyle(active ? HarborTheme.accent : HarborTheme.ink.opacity(0.55)).frame(width: 46, alignment: .leading)
                    Text(session.texts[index]).font(HarborTheme.font(15, weight: active ? .medium : .regular))
                        .multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading)
                    if let pointNumber {
                        Text(text(pointNumber == 0 ? "Aligned" : "Drift fixed")).font(HarborTheme.font(10, weight: .bold)).foregroundStyle(HarborTheme.accent)
                    } else if active {
                        Text(text("Now")).font(HarborTheme.font(10, weight: .bold)).foregroundStyle(HarborTheme.accent)
                    } else if fixed {
                        Image(systemName: "checkmark").font(HarborTheme.font(11)).foregroundStyle(HarborTheme.accent)
                    }
                }
                .padding(.horizontal, 18).padding(.vertical, 12).frame(minHeight: 44).contentShape(Rectangle())
                .background(highlighted ? HarborTheme.accent.opacity(0.12) : (found ? HarborTheme.accent.opacity(0.06) : Color.clear))
            }
            .buttonStyle(.plain).accessibilityAddTraits(selected == index ? .isSelected : [])
            if selected == index { actions(index) }
        }
    }

    private func actions(_ index: Int) -> some View {
        HStack(spacing: 10) {
            Button { alignToNow(index) } label: {
                Label(text("Align to now"), systemImage: "checkmark").frame(minHeight: 44).padding(.horizontal, 12)
            }
            .buttonStyle(.borderedProminent).tint(HarborTheme.accent).accessibilityIdentifier("subtitle-text-sync-align")
            Button { jump(index) } label: {
                Label(text("Jump here"), systemImage: "play.fill").frame(minHeight: 44).padding(.horizontal, 12)
            }
            .buttonStyle(.bordered)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18).padding(.vertical, 8)
    }

    private func controls(_ session: SubtitleTextSyncSession) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Button("\u{2212}0.1") { self.session?.adjustNudge(by: -0.1) }.buttonStyle(.bordered).frame(minHeight: 44)
                Text(deltaLabel(session)).font(HarborTheme.font(15, weight: .bold)).monospacedDigit().frame(minWidth: 84)
                Button("+0.1") { self.session?.adjustNudge(by: 0.1) }.buttonStyle(.bordered).frame(minHeight: 44)
                Spacer(minLength: 0)
                Button { toggleSectionMode() } label: {
                    Label(text("Fix one section"), systemImage: "scissors").font(HarborTheme.font(13, weight: .semibold)).frame(minHeight: 44)
                }
                .buttonStyle(.bordered).tint(sectionMode ? HarborTheme.accent : nil)
            }
            if session.dirty {
                Button(resetTitle(session)) { reset() }.font(HarborTheme.font(13)).frame(minHeight: 44)
            }
            if saveFailed {
                Text(text("Couldn't save the synced subtitle. Try again.")).font(HarborTheme.font(12)).foregroundStyle(.secondary)
            }
            Button { save() } label: {
                Text(text("Save")).font(HarborTheme.font(15, weight: .semibold)).frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent).tint(HarborTheme.accent)
            .disabled(!session.dirty || state.subtitleChanging).accessibilityIdentifier("subtitle-text-sync-save")
        }
        .padding(18)
    }

    private func hint(_ session: SubtitleTextSyncSession) -> String {
        if sectionMode {
            if session.rangeStart == nil { return text("Tap the first line of the section you want to fix.") }
            if session.rangeEnd == nil { return text("Now tap the last line of that section.") }
            return text("Play until you hear a line inside this section, tap it, then choose Align to now.")
        }
        if session.points.isEmpty { return text("Play until you hear a line. Tap that same line below, then choose Align to now.") }
        if session.points.count == 1 { return text("Timing is aligned. If it becomes early or late later, repeat this at another line.") }
        return text("Timing and drift are corrected. Check playback, then save.")
    }

    private func deltaLabel(_ session: SubtitleTextSyncSession) -> String {
        let value = session.currentDelta(at: state.position)
        return (value >= 0 ? "+" : "\u{2212}") + String(format: "%.2f", abs(value)) + " s"
    }

    private func resetTitle(_ session: SubtitleTextSyncSession) -> String {
        if session.segments.isEmpty { return text("Reset") }
        return DesktopInterfaceText.value("{n} section fixes. Reset all", variables: ["n": String(session.segments.count)])
    }

    // MARK: Actions

    private func tap(_ index: Int) {
        guard let current = session else { return }
        if sectionMode {
            if current.rangeStart == nil { session?.chooseRangeStart(index); return }
            if current.rangeEnd == nil { session?.chooseRangeEnd(index); return }
        }
        selected = selected == index ? nil : index
    }

    private func alignToNow(_ index: Int) {
        session?.syncFromHere(cueIndex: index, position: state.position)
        selected = nil
    }

    private func jump(_ index: Int) {
        guard let current = session, current.cues.indices.contains(index) else { return }
        state.controller?.run(["seek", String(current.cues[index].start), "absolute+exact"])
    }

    private func toggleSectionMode() {
        sectionMode.toggle()
        selected = nil
        session?.clearRange()
    }

    private func reset() {
        session?.reset()
        selected = nil
        saveFailed = false
    }

    private func save() {
        guard let document, let current = session else { return }
        let times = current.corrected.map { (start: $0.start, end: $0.end) }
        guard let rewritten = document.applying(cueTimes: times), let corrected = try? SubtitleDocument(rewritten) else {
            saveFailed = true
            return
        }
        saveFailed = false
        state.controller?.applyManualTextSync(corrected)
        dismiss()
    }

    private func load() async {
        guard let track = state.primarySubtitle, track.external, track.isTextSubtitle,
              SubtitleTextSync.supportsFile(named: track.externalFilename) else {
            phase = .unreadable
            return
        }
        let delay = state.subtitleDelay
        do {
            let loaded = try await SubtitleAutoSync.load(track.externalFilename)
            let lines = try await Task.detached(priority: .userInitiated) { () throws -> [SubtitlePivotCue] in
                try loaded.cuesInFileOrder()
            }.value
            guard lines.count == loaded.cues.count else {
                phase = .unreadable
                return
            }
            let timings = loaded.cues.map { SubtitleTextSync.Timing(start: $0.start, end: $0.end) }
            document = loaded
            session = SubtitleTextSyncSession(cues: timings, texts: lines.map { $0.text }, baseOffset: delay)
            phase = .ready
        } catch {
            phase = .unreadable
        }
    }
}

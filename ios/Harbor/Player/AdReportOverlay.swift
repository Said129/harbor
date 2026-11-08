import SwiftUI

/// Pure rules of the ad report screen: Desktop's `RangeRow` (`fmt`, `parse`) and `AdReportModal` (adding and checking ranges).
enum AdReportEntry {
    /// `m:ss`, or `h:mm:ss` from one hour. A negative or unusable time shows as zero.
    static func format(_ seconds: Double) -> String {
        let total = seconds.isFinite ? max(0, Int(seconds.rounded())) : 0
        let hours = total / 3_600, minutes = (total % 3_600) / 60, rest = total % 60
        return hours > 0 ? String(format: "%d:%02d:%02d", hours, minutes, rest) : String(format: "%d:%02d", minutes, rest)
    }

    /// One to three parts split by colons, each made only of ASCII digits; nil for anything else.
    static func parse(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let parts = trimmed.split(separator: ":", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count <= 3, parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy { $0.isASCII && $0.isNumber } }) else { return nil }
        let numbers = parts.compactMap { Double($0) }
        guard numbers.count == parts.count else { return nil }
        return numbers.reduce(0) { $0 * 60 + $1 }
    }

    /// "Add an ad starting at the current time": thirty seconds from the rounded position.
    static func newRange(at position: Double) -> AdReportRange {
        let start = position.isFinite ? max(0, position.rounded()) : 0
        return AdReportRange(startSec: start, endSec: start + 30)
    }

    /// Something to send, and every range ends after it starts.
    static func canSubmit(_ ranges: [AdReportRange]) -> Bool {
        !ranges.isEmpty && ranges.allSatisfy { $0.endSec > $0.startSec }
    }
}

/// Desktop's `AdReportButton` (`components/player/ad-report-button.tsx`): a small button with a first-time tip that opens the report
/// screen. It shows with the player controls on a stream the corpus can name, for a recent release or when asked to always show
/// (`AdReportRules.shouldShow`). A modifier of its own keeps the player's modifier chain quick to type-check. Desktop also hides the
/// button while a skip button or the next-episode button takes its place; the player's segments are not visible from here.
struct AdReportDriver: ViewModifier {
    let session: PlaybackSession
    let media: Media?
    let state: PlayerState
    let visible: Bool
    @AppStorage("adSkipEnabled") private var enabled = false
    @AppStorage("adReportAlwaysShow") private var alwaysShow = false
    @AppStorage("adReportFirstSeen") private var firstSeen = false
    @State private var open = false

    private var fingerprint: AdSkipFingerprint.Key? {
        guard let stream = session.adSkipStream else { return nil }
        return AdSkipFingerprint.fingerprint(metaID: media?.id ?? session.target.id, imdbID: media?.imdbID, infoHash: stream.infoHash,
                                             fileIdx: stream.fileIdx, releaseGroup: stream.releaseGroup, size: stream.size,
                                             parsedTitle: stream.parsedTitle, url: stream.url)
    }

    private var shown: Bool {
        guard let fingerprint, !session.target.id.hasPrefix("iptv:") else { return false }
        return AdReportRules.shouldShow(enabled: enabled, alwaysShow: alwaysShow, isDirectStream: fingerprint.source.hasPrefix("u_"),
                                        recentRelease: AdReportRules.withinAdWindow(releaseDate: media?.released, releaseInfo: media?.releaseInfo))
    }

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottomTrailing) { reportLayer }
            .sheet(isPresented: $open) { AdReportSheet(state: state, submit: submit) }
    }

    @ViewBuilder private var reportLayer: some View {
        if visible, state.loaded, state.error == nil, shown {
            VStack(alignment: .trailing, spacing: 8) {
                if !firstSeen { tip }
                Button { firstSeen = true; open = true } label: {
                    Image(systemName: "flag.fill").font(.system(size: 16, weight: .semibold)).frame(width: 44, height: 44)
                        .background(.black.opacity(0.65), in: .circle).overlay { Circle().stroke(.white.opacity(0.15), lineWidth: 1) }
                }
                .buttonStyle(.plain).foregroundStyle(.white.opacity(0.9))
                .accessibilityLabel(DesktopInterfaceText.value("Report an injected ad")).accessibilityIdentifier("player-ad-report")
            }
            .padding(.trailing, 20).padding(.bottom, 150)
        }
    }

    private var tip: some View {
        HStack(alignment: .top, spacing: 6) {
            Text(DesktopInterfaceText.value("See an injected ad? Report it")).font(HarborTheme.font(12)).foregroundStyle(.white.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
            Button { firstSeen = true } label: { Image(systemName: "xmark").font(.system(size: 11, weight: .bold)).frame(width: 28, height: 28) }
                .buttonStyle(.plain).foregroundStyle(.white.opacity(0.55)).accessibilityLabel(DesktopInterfaceText.value("Dismiss"))
        }
        .padding(10).frame(width: 224, alignment: .leading).background(.black.opacity(0.85), in: .rect(cornerRadius: 12))
    }

    private func submit(_ ranges: [AdReportRange]) async -> Bool {
        guard let fingerprint else { return false }
        return await AdReportSubmitter.submit(content: fingerprint.content, source: fingerprint.source, ranges: ranges)
    }
}

/// Desktop's `AdReportModal`: add the ranges of the ad, check them and send them for review.
private struct AdReportSheet: View {
    let state: PlayerState
    let submit: ([AdReportRange]) async -> Bool
    @Environment(\.dismiss) private var dismiss
    @State private var showingAbout = false
    @State private var ranges: [AdReportRange] = []
    @State private var status = Status.idle

    private enum Status { case idle, sending, sent, error }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if showingAbout { about } else { report }
                }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(HarborTheme.background.ignoresSafeArea())
            .foregroundStyle(HarborTheme.ink)
            .navigationTitle(showingAbout ? DesktopInterfaceText.value("What is this?") : DesktopInterfaceText.value("Report an injected ad"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(DesktopInterfaceText.value("Close")) { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    if !showingAbout { Button(DesktopInterfaceText.value("What is this?")) { showingAbout = true } }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    @ViewBuilder private var report: some View {
        Text(DesktopInterfaceText.value("Play to where the ad starts and add it, then play to the end and tap Now. You can also type the times. Add more than one if there are several."))
            .font(HarborTheme.font(13)).foregroundStyle(HarborTheme.ink.opacity(0.7))
        ForEach(ranges.indices, id: \.self) { index in
            AdRangeRow(index: index, range: ranges[index], position: state.position,
                       onChange: { if ranges.indices.contains(index) { ranges[index] = $0 } },
                       onRemove: { if ranges.indices.contains(index) { ranges.remove(at: index) } })
        }
        Button { ranges.append(AdReportEntry.newRange(at: state.position)) } label: {
            Label(DesktopInterfaceText.value("Add an ad starting at the current time"), systemImage: "plus")
                .font(HarborTheme.font(14, weight: .medium)).frame(maxWidth: .infinity, minHeight: 44)
                .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [5, 4])).foregroundStyle(HarborTheme.ink.opacity(0.3)) }
        }.buttonStyle(.plain)
        if status == .error { Text(DesktopInterfaceText.value("Could not send. Try again.")).font(HarborTheme.font(12)).foregroundStyle(.red) }
        if status == .sent { Text(DesktopInterfaceText.value("Thanks. Sent for review.")).font(HarborTheme.font(12)).foregroundStyle(HarborTheme.accent) }
        Button { Task { await send() } } label: {
            Text(status == .sending ? DesktopInterfaceText.value("Sending...") : DesktopInterfaceText.value("Submit report"))
                .font(HarborTheme.font(14, weight: .semibold)).frame(maxWidth: .infinity, minHeight: 44)
                .background(HarborTheme.ink, in: .rect(cornerRadius: 12)).foregroundStyle(ThemePreferences.shared.color("canvas"))
        }
        .buttonStyle(.plain).disabled(!AdReportEntry.canSubmit(ranges) || status == .sending)
        .opacity(AdReportEntry.canSubmit(ranges) && status != .sending ? 1 : 0.4)
    }

    @ViewBuilder private var about: some View {
        Text(DesktopInterfaceText.value("Some copies of new releases have ads spliced into the video itself. This is experimental: the community marks where those ads are so others can skip them."))
            .font(HarborTheme.font(14)).foregroundStyle(HarborTheme.ink.opacity(0.7))
        Text(DesktopInterfaceText.value("Your report is sent for review before it ever skips anything for anyone. Nothing about the video is uploaded, just the timestamps you mark. It is off by default and you can turn it off anytime in Settings."))
            .font(HarborTheme.font(14)).foregroundStyle(HarborTheme.ink.opacity(0.7))
        Button { showingAbout = false } label: { Label(DesktopInterfaceText.value("Back"), systemImage: "chevron.backward").frame(minHeight: 44) }
    }

    private func send() async {
        guard AdReportEntry.canSubmit(ranges), status != .sending else { return }
        status = .sending
        let ok = await submit(ranges)
        status = ok ? .sent : .error
        if ok {
            try? await Task.sleep(for: .milliseconds(1_200))
            dismiss()
        }
    }
}

/// Desktop's `RangeRow`: one ad with its start and end, each typed or set to where the video is now.
private struct AdRangeRow: View {
    let index: Int
    let range: AdReportRange
    let position: Double
    let onChange: (AdReportRange) -> Void
    let onRemove: () -> Void

    private var invalid: Bool { range.endSec <= range.startSec }
    private var now: Double { position.isFinite ? max(0, position.rounded()) : 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(DesktopInterfaceText.value("Ad {n}", variables: ["n": String(index + 1)]).uppercased())
                    .font(HarborTheme.font(11, weight: .semibold)).tracking(1).foregroundStyle(HarborTheme.ink.opacity(0.55))
                Spacer(minLength: 0)
                Button(DesktopInterfaceText.value("Remove"), action: onRemove).font(HarborTheme.font(12, weight: .medium)).foregroundStyle(.red)
            }
            AdTimeField(label: DesktopInterfaceText.value("Starts at"), seconds: range.startSec, danger: false,
                        onCommit: { onChange(AdReportRange(startSec: $0, endSec: range.endSec)) },
                        onUseNow: { onChange(AdReportRange(startSec: now, endSec: range.endSec)) })
            AdTimeField(label: DesktopInterfaceText.value("Ends at"), seconds: range.endSec, danger: invalid,
                        onCommit: { onChange(AdReportRange(startSec: range.startSec, endSec: $0)) },
                        onUseNow: { onChange(AdReportRange(startSec: range.startSec, endSec: now)) })
            if invalid {
                Text(DesktopInterfaceText.value("The end time has to be after the start.")).font(HarborTheme.font(12)).foregroundStyle(.red)
            }
        }
        .padding(14)
        .background(HarborTheme.surface.opacity(0.6), in: .rect(cornerRadius: 12))
    }
}

/// Desktop's `TimeField`: the text shows the time and is read back when editing ends; a typo restores the old time.
private struct AdTimeField: View {
    let label: String
    let seconds: Double
    let danger: Bool
    let onCommit: (Double) -> Void
    let onUseNow: () -> Void
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 10) {
            Text(label).font(HarborTheme.font(12, weight: .medium)).foregroundStyle(HarborTheme.ink.opacity(0.7)).frame(width: 64, alignment: .leading)
            TextField(label, text: $text)
                .focused($focused).keyboardType(.numbersAndPunctuation).multilineTextAlignment(.center)
                .font(.system(size: 15, weight: .semibold, design: .monospaced)).foregroundStyle(danger ? Color.red : HarborTheme.ink)
                .frame(minHeight: 44).background(HarborTheme.surface, in: .rect(cornerRadius: 10))
                .overlay { RoundedRectangle(cornerRadius: 10).stroke(danger ? Color.red : ThemePreferences.shared.color("edge-soft"), lineWidth: 1) }
                .onSubmit { commit() }
                .onChange(of: focused) { _, isFocused in if !isFocused { commit() } }
            Button(action: onUseNow) {
                Label(DesktopInterfaceText.value("Now"), systemImage: "clock").font(HarborTheme.font(12, weight: .semibold))
                    .padding(.horizontal, 12).frame(minHeight: 44).background(HarborTheme.surface, in: .rect(cornerRadius: 10))
            }
            .buttonStyle(.plain).accessibilityHint(DesktopInterfaceText.value("Set to where the video is right now"))
        }
        .onAppear { text = AdReportEntry.format(seconds) }
        .onChange(of: seconds) { _, value in if !focused { text = AdReportEntry.format(value) } }
    }

    private func commit() {
        if let parsed = AdReportEntry.parse(text) { onCommit(parsed) } else { text = AdReportEntry.format(seconds) }
    }
}

import SwiftUI

@MainActor struct MusicSourcePickerView: View {
    @Bindable var player: MusicPlayback
    let session: MusicPlaybackSession
    var queuedSelection: MusicQueueSourceSelection? = nil
    /// Reports the settled candidate count once the current lookup finishes.
    var onLookupFinished: (@MainActor (Int) -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var candidates: [MusicSourceCandidate] = []
    // Desktop's picker starts in its search state; "none" requires a finished lookup.
    @State private var loading = true
    @State private var failed = false
    @State private var retry = 0
    @State private var lookup = UUID()
    private var requested: MusicTrack? { queuedSelection?.item.track ?? player.currentTrack }
    private var queryID: String { (queuedSelection?.id.uuidString ?? requested.map { ($0.connectorId ?? "") + ":" + $0.id } ?? "") + "|" + String(retry) }
    var body: some View {
        List {
            if loading { ProgressView(DesktopInterfaceText.value("music.source.loading")) }
            if failed {
                Text(DesktopInterfaceText.value("music.source.none")).foregroundStyle(.secondary)
                Button(DesktopInterfaceText.value("Retry")) { retry += 1 }
            }
            ForEach(candidates) { candidate in
                Button {
                    do {
                        if let selection = queuedSelection {
                            try player.replaceQueuedSource(candidate.track, for: selection.item, in: selection.queue)
                        } else { try player.switchSource(candidate.track) }
                        dismiss()
                    } catch is CancellationError { dismiss() }
                    catch { failed = true }
                } label: {
                    HStack(spacing: 12) {
                        MusicPlaybackCover(item: .init(track: candidate.track, localRecord: session.localRecord(candidate.track)), owner: session.scope.owner).frame(width: 48, height: 48)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(candidate.track.title).lineLimit(2)
                            Text(candidate.track.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            Text(candidate.connectorName + " · " + candidate.track.durationLabel).font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                        if queuedSelection == nil, player.currentTrack.map(MusicQueueOrder.key) == MusicQueueOrder.key(candidate.track) { Image(systemName: "checkmark").foregroundStyle(HarborTheme.accent) }
                    }.frame(minHeight: 56)
                }.buttonStyle(.plain).accessibilityIdentifier("music-source-choice-" + candidate.id)
            }
            if !loading, candidates.isEmpty, !failed { Text(DesktopInterfaceText.value("music.source.none")).foregroundStyle(.secondary) }
        }.listStyle(.plain).navigationTitle(DesktopInterfaceText.value(queuedSelection == nil ? "music.source.playOn" : "music.source.another")).navigationBarTitleDisplayMode(.inline)
            .task(id: queryID) {
                let token = UUID(); lookup = token; candidates = []; loading = true; failed = false
                defer { if lookup == token { loading = false; onLookupFinished?(candidates.count) } }
                guard let track = requested else { return }
                do {
                    let values: [MusicSourceCandidate]
                    if let selection = queuedSelection {
                        guard player.ownsQueue(selection.queue) else { throw CancellationError() }
                        values = try await session.alternativeSources(for: track)
                        guard player.ownsQueue(selection.queue) else { throw CancellationError() }
                    } else { values = try await session.sources(for: track) }
                    try Task.checkCancellation()
                    guard lookup == token else { throw CancellationError() }
                    candidates = values
                }
                catch is CancellationError { }
                catch { if lookup == token { failed = true } }
            }.onChange(of: player.queueRevision) { _, _ in
                if let selection = queuedSelection, !player.ownsQueue(selection.queue) { dismiss() }
            }.environment(\.musicPlaybackSession, session).accessibilityIdentifier("music-source-picker")
    }
}

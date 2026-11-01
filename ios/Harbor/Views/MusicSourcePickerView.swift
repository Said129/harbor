import SwiftUI

@MainActor struct MusicSourcePickerView: View {
    @Bindable var player: MusicPlayback
    let session: MusicPlaybackSession
    @Environment(\.dismiss) private var dismiss
    @State private var candidates: [MusicSourceCandidate] = []
    @State private var loading = false
    @State private var failed = false
    @State private var retry = 0
    var body: some View {
        List {
            if loading { ProgressView(DesktopInterfaceText.value("music.source.searching")) }
            if failed {
                Text(DesktopInterfaceText.value("music.source.none")).foregroundStyle(.secondary)
                Button(DesktopInterfaceText.value("Retry")) { retry += 1 }
            }
            ForEach(candidates) { candidate in
                Button {
                    do { try player.switchSource(candidate.track); dismiss() } catch { failed = true }
                } label: {
                    HStack(spacing: 12) {
                        MusicPlaybackCover(item: .init(track: candidate.track, localRecord: session.localRecord(candidate.track)), owner: session.scope.owner).frame(width: 48, height: 48)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(candidate.track.title).lineLimit(2)
                            Text(candidate.track.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            Text(candidate.connectorName + " · " + candidate.track.durationLabel).font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                        if player.currentTrack.map(MusicQueueOrder.key) == MusicQueueOrder.key(candidate.track) { Image(systemName: "checkmark").foregroundStyle(HarborTheme.accent) }
                    }.frame(minHeight: 56)
                }.buttonStyle(.plain)
            }
            if !loading, candidates.isEmpty, !failed { Text(DesktopInterfaceText.value("music.source.none")).foregroundStyle(.secondary) }
        }.listStyle(.plain).navigationTitle(DesktopInterfaceText.value("music.source.title")).navigationBarTitleDisplayMode(.inline)
            .task(id: (player.currentTrack?.id ?? "") + "|" + String(retry)) {
                loading = true; failed = false; defer { loading = false }
                guard let track = player.currentTrack else { return }
                do { let values = try await session.sources(for: track); try Task.checkCancellation(); candidates = values }
                catch is CancellationError { }
                catch { failed = true }
            }.accessibilityIdentifier("music-source-picker")
    }
}

import SwiftUI

private struct MusicPlaybackSessionKey: EnvironmentKey { static let defaultValue: MusicPlaybackSession? = nil }
extension EnvironmentValues {
    var musicPlaybackSession: MusicPlaybackSession? {
        get { self[MusicPlaybackSessionKey.self] }
        set { self[MusicPlaybackSessionKey.self] = newValue }
    }
}

@MainActor struct MusicPlaybackCover: View {
    let item: MusicPlaybackItem
    let owner: String
    var body: some View {
        Group {
            if let local = item.localRecord { MusicCover(record: local, owner: owner) }
            else { Artwork(url: item.track.artwork, maxPixels: 720, failureIcon: "nav-music").clipShape(.rect(cornerRadius: 8)) }
        }.accessibilityHidden(true)
    }
}
@MainActor struct MusicPlaybackRow: View {
    let item: MusicPlaybackItem
    let owner: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                MusicPlaybackCover(item: item, owner: owner).frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 4) { Text(item.track.title).lineLimit(1); Text(item.track.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                Spacer()
                Text(item.track.durationLabel).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }.frame(minHeight: 44).contentShape(.rect)
        }.buttonStyle(.plain).accessibilityLabel(item.track.title + ", " + item.track.artist).accessibilityIdentifier("music-shared-track-" + item.id)
    }
}

@MainActor struct MusicMiniPlayer: View {
    @Bindable var player: MusicPlayback
    @State private var expanded = false
    init() { player = .shared }
    init(player: MusicPlayback) { self.player = player }
    var body: some View {
        if let item = player.currentItem {
            HStack(spacing: 12) {
                Button { expanded = true } label: {
                    HStack(spacing: 10) {
                        MusicPlaybackCover(item: item, owner: player.owner).frame(width: 42, height: 42)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.track.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                            Text(player.pausedForVideo ? DesktopInterfaceText.value("music.mobile.resume") : item.track.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                }.buttonStyle(.plain).accessibilityLabel(DesktopInterfaceText.value("Music"))
                Button { player.togglePause() } label: {
                    Group { if player.phase == .resolving { ProgressView().tint(HarborTheme.ink) } else { MusicGlyph(player.paused ? "play" : "pause") } }.frame(width: 44, height: 44)
                }.accessibilityLabel(DesktopInterfaceText.value(player.paused ? "music.play" : "music.pause"))
                Button { player.next() } label: { MusicGlyph("next").frame(width: 44, height: 44) }.accessibilityLabel(DesktopInterfaceText.value("music.next"))
            }.padding(.horizontal, 14).padding(.vertical, 7).background(HarborTheme.surface).accessibilityIdentifier("music-shared-mini-player")
                .sheet(isPresented: $expanded) { NavigationStack { MusicPlayerView(player: player).toolbar { ToolbarItem(placement: .topBarTrailing) { Button(DesktopInterfaceText.value("Close")) { expanded = false } } } } }
        }
    }
}

@MainActor struct MusicPlayerView: View {
    @Bindable var player: MusicPlayback
    @Environment(\.dismiss) private var dismiss
    init() { player = .shared }
    init(player: MusicPlayback) { self.player = player }
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 22) {
                if let item = player.currentItem {
                    MusicPlaybackCover(item: item, owner: player.owner).frame(width: 180, height: 180)
                    VStack(spacing: 5) {
                        Text(item.track.title).font(.title2.bold()); Text(item.track.artist).foregroundStyle(.secondary)
                        if let album = item.track.album { Text(album).font(.caption).foregroundStyle(.secondary) }
                    }.multilineTextAlignment(.center).accessibilityIdentifier("music-shared-current-metadata")
                    MusicTransportControls(player: player)
                    if let error = player.error { Text(error).font(.caption).foregroundStyle(.orange).accessibilityIdentifier("music-shared-error") }
                    if let error = player.scrobbleError { Text(error).font(.caption).foregroundStyle(.secondary) }
                    VStack(alignment: .leading, spacing: 12) {
                        Label(DesktopInterfaceText.value("music.now.next"), image: "music-queue").font(.headline)
                        ForEach(player.upcomingItems) { entry in row(entry) }
                        DisclosureGroup(DesktopInterfaceText.value("music.search.tracks")) {
                            ForEach(player.items) { entry in row(entry) }
                        }
                    }.accessibilityIdentifier("music-shared-queue")
                    Button(DesktopInterfaceText.value("music.player.close"), role: .destructive) { player.stop(); dismiss() }
                } else { ContentUnavailableView(DesktopInterfaceText.value("Music"), image: "nav-music") }
            }.padding(24).frame(maxWidth: 800).frame(maxWidth: .infinity)
        }.background(HarborTheme.background).navigationTitle(DesktopInterfaceText.value("Music")).navigationBarTitleDisplayMode(.inline)
            .accessibilityIdentifier("music-shared-player")
    }
    private func row(_ item: MusicPlaybackItem) -> some View {
        MusicPlaybackRow(item: item, owner: player.owner) { player.play(item) }
            .contextMenu {
                Button(DesktopInterfaceText.value("music.queue.playNext")) { player.moveAfterCurrent(item) }
                Button(DesktopInterfaceText.value("music.queue.remove", variables: ["title": item.track.title]), role: .destructive) { player.removeFromQueue(item) }
            }
    }
}

/// Only the transport observes the playback clock. Metadata, artwork and the
/// queue do not rebuild and re-encode its listening order on every position tick.
@MainActor private struct MusicTransportControls: View {
    @Bindable var player: MusicPlayback
    @State private var seek = 0.0
    @State private var editing = false
    var body: some View {
        VStack(spacing: 14) {
            Slider(value: $seek, in: 0...max(player.duration, 1)) { edit in editing = edit; if !edit { player.seek(seek) } }.accessibilityLabel(DesktopInterfaceText.value("music.position"))
            HStack { Text(time(editing ? seek : player.position)); Spacer(); Text(time(player.duration)) }.font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            HStack(spacing: 10) {
                Button { player.shuffle.toggle() } label: { MusicGlyph("shuffle").foregroundStyle(player.shuffle ? HarborTheme.accent : .secondary).frame(width: 44, height: 44) }.accessibilityLabel(DesktopInterfaceText.value("music.transport.shuffle")).accessibilityAddTraits(player.shuffle ? .isSelected : [])
                Button { player.previous() } label: { MusicGlyph("previous").frame(width: 44, height: 44) }.accessibilityLabel(DesktopInterfaceText.value("music.previous"))
                Button { player.togglePause() } label: {
                    Group { if player.phase == .resolving { ProgressView().tint(HarborTheme.background) } else { MusicGlyph(player.paused ? "play" : "pause", size: 28) } }
                        .foregroundStyle(HarborTheme.background).frame(width: 54, height: 54).background(HarborTheme.ink, in: .circle)
                }.accessibilityLabel(DesktopInterfaceText.value(player.paused ? "music.play" : "music.pause"))
                Button { player.next() } label: { MusicGlyph("next").frame(width: 44, height: 44) }.accessibilityLabel(DesktopInterfaceText.value("music.next"))
                Menu { Picker(DesktopInterfaceText.value("music.transport.repeat"), selection: $player.repeatMode) { ForEach(MusicRepeat.allCases) { Text($0.title).tag($0) } } } label: {
                    MusicGlyph(player.repeatMode == .one ? "repeat-one" : "repeat").foregroundStyle(player.repeatMode == .off ? .secondary : HarborTheme.accent).frame(width: 44, height: 44)
                }.accessibilityLabel(DesktopInterfaceText.value("music.transport.repeat")).accessibilityValue(player.repeatMode.title)
            }.buttonStyle(.plain)
            Slider(value: Binding(get: { player.volume }, set: { player.changeVolume($0) }), in: 0...100) { Text(DesktopInterfaceText.value("music.volume")) } minimumValueLabel: { MusicGlyph("volume-low") } maximumValueLabel: { MusicGlyph("volume-high") }
        }.onChange(of: player.position) { _, value in if !editing { seek = value } }
            .onChange(of: player.currentItem?.id) { _, _ in editing = false; seek = 0 }
            .onAppear { seek = player.position }
    }
    private func time(_ seconds: Double) -> String {
        let value = seconds.isFinite ? Int(max(0, min(seconds, 31_536_000))) : 0
        return String(format: "%d:%02d", value / 60, value % 60)
    }
}

@MainActor struct MusicRecordingActions: View {
    let track: MusicTrack
    let session: MusicPlaybackSession
    var body: some View {
        let collections = MusicCollections.shared
        let liked = collections.isLiked(track.id, owner: session.scope.owner)
        Button {
            guard (try? session.validate()) != nil, session.playlists.remember([track]) else { return }
            collections.setLiked(track.id, liked: !liked, owner: session.scope.owner)
        } label: {
            Label(DesktopInterfaceText.value(liked ? "Remove from saved tracks" : "Save track"), systemImage: liked ? "heart.slash" : "heart")
        }.disabled(!session.playlists.ready).accessibilityIdentifier("music-shared-like")
        Button(DesktopInterfaceText.value("music.queue.playNext")) { MusicPlayback.shared.enqueue(track, using: session, next: true) }
        Button(DesktopInterfaceText.value("music.card.addToQueue")) { MusicPlayback.shared.enqueue(track, using: session) }
        Menu(DesktopInterfaceText.value("music.card.addToPlaylist")) {
            ForEach(session.playlists.playlists) { playlist in
                Button(playlist.name) { session.playlists.add([track], to: playlist.id) }.disabled(playlist.trackIds.contains(track.id))
            }
        }.disabled(!session.playlists.ready || session.playlists.playlists.isEmpty)
    }
}

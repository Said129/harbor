import SwiftUI
import UIKit

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
            else { MusicArtwork(url: item.track.artwork, maxPixels: 720).clipShape(.rect(cornerRadius: 8)) }
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
                        GeometryReader { geometry in
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(item.track.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                                    Text(player.pausedForVideo ? DesktopInterfaceText.value("music.mobile.resume") : item.track.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                }.frame(maxWidth: .infinity, alignment: .leading)
                                if geometry.size.width >= 220, MusicAudioMeter.supported, player.playbackSession?.audio?.dockVisualizer == true {
                                    MusicAudioMeterView(player: player, presentation: .spectrum).frame(width: 76, height: 16)
                                }
                            }.frame(height: geometry.size.height)
                        }.frame(height: 44)
                    }
                }.buttonStyle(.plain).accessibilityLabel(DesktopInterfaceText.value("Music"))
                MusicPlayButton(player: player, diameter: 44)
                Button { player.next() } label: { MusicGlyph("next").frame(width: 44, height: 44) }.accessibilityLabel(DesktopInterfaceText.value("music.next"))
            }.padding(.horizontal, 14).padding(.vertical, 7).background { MusicArtworkBackground() }.accessibilityIdentifier("music-shared-mini-player")
                .environment(\.musicPlaybackSession, player.playbackSession)
                .sheet(isPresented: $expanded) { NavigationStack { MusicPlayerView(player: player).toolbar { ToolbarItem(placement: .topBarTrailing) { Button(DesktopInterfaceText.value("Close")) { expanded = false } } } } }
                .modifier(MusicArtworkTheme(player: player))
        } else if let spotify = SpotifyMusicSelection.shared.active {
            SpotifyMiniPlayer(service: spotify)
        }
    }
}

@MainActor struct MusicPlayerView: View {
    @Bindable var player: MusicPlayback
    @Environment(\.dismiss) private var dismiss
    @State private var choosingSource = false
    @State private var audioSettings = false
    init() { player = .shared }
    init(player: MusicPlayback) { self.player = player }
    var body: some View {
        GeometryReader { geometry in
            let edge = min(72, max(20, geometry.size.width * 0.038))
            let width = min(1240, max(0, geometry.size.width - 2 * edge))
            let gap = min(88, max(32, geometry.size.width * 0.05))
            ScrollView {
                VStack(spacing: 30) {
                    if let item = player.currentItem {
                        if let preferences = player.playbackSession?.audio { MusicAppearanceControls(preferences: preferences) }
                        if width >= 650 {
                            HStack(alignment: .top, spacing: gap) {
                                artwork(item, width: min(540, (width - gap) / 2))
                                recording(item).frame(maxWidth: .infinity)
                            }.accessibilityIdentifier("music-now-two-columns")
                        } else {
                            artwork(item, width: min(540, width))
                            recording(item)
                        }
                        MusicNowPanels(player: player)
                        Button(DesktopInterfaceText.value("music.player.close"), role: .destructive) { player.stop(); dismiss() }
                    } else { ContentUnavailableView(DesktopInterfaceText.value("Music"), image: "nav-music") }
                }.frame(width: width).padding(edge).frame(maxWidth: .infinity)
            }
        }.background { MusicArtworkBackground(expanded: true) }.navigationTitle(DesktopInterfaceText.value("Music")).navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $choosingSource) {
                if let session = player.playbackSession {
                    NavigationStack { MusicSourcePickerView(player: player, session: session).toolbar {
                        ToolbarItem(placement: .topBarTrailing) { Button(DesktopInterfaceText.value("Close")) { choosingSource = false } }
                    } }
                }
            }
            .accessibilityIdentifier("music-shared-player")
            .environment(\.musicPlaybackSession, player.playbackSession)
            .sheet(isPresented: $audioSettings) {
                if let session = player.playbackSession { MusicAudioSettingsView(session: session, player: player) }
            }
            .modifier(MusicArtworkTheme(player: player))
    }
    private func artwork(_ item: MusicPlaybackItem, width: CGFloat) -> some View {
        VStack(spacing: 24) {
            MusicPlaybackCover(item: item, owner: player.owner).frame(width: width, height: width)
                .clipShape(.rect(cornerRadius: 12)).accessibilityIdentifier("music-now-artwork")
            if MusicAudioMeter.supported {
                if player.playbackSession?.audio?.showLevels != false { MusicAudioMeterView(player: player) }
                if player.playbackSession?.audio?.dockVisualizer == true {
                    MusicAudioMeterView(player: player, presentation: .spectrum).frame(width: 152, height: 32)
                }
            }
        }.frame(width: width)
    }
    private func recording(_ item: MusicPlaybackItem) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 5) {
                Text(item.track.title).font(.title.bold()); Text(item.track.artist).foregroundStyle(.secondary)
                if let album = item.track.album { Text(album).font(.caption).foregroundStyle(.secondary) }
            }.accessibilityIdentifier("music-shared-current-metadata")
            MusicTransportControls(player: player)
            if player.playbackSession != nil {
                Button(DesktopInterfaceText.value("music.source.playOn")) { choosingSource = true }.disabled(player.resolving)
                Button(DesktopInterfaceText.value("music.audio.title")) { audioSettings = true }
            }
            if let error = player.error { Text(error).font(.caption).foregroundStyle(.orange).accessibilityIdentifier("music-shared-error") }
            if let error = player.scrobbleError { Text(error).font(.caption).foregroundStyle(.secondary) }
        }
    }
}

/// Desktop's now-playing detail tabs, in its order: up next, about, lyrics and
/// signal. About needs a playback session for its profile-scoped metadata
/// client, so it is offered only while one exists.
@MainActor private struct MusicNowPanels: View {
    enum Panel: String, CaseIterable, Identifiable {
        case queue, about, lyrics, signal
        var id: String { rawValue }
        var label: String {
            switch self {
            case .queue: "music.now.next"
            case .about: "music.artist.about"
            case .lyrics: "Lyrics"
            case .signal: "music.now.signal"
            }
        }
    }
    @Bindable var player: MusicPlayback
    @State private var panel = Panel.queue
    private var panels: [Panel] { Panel.allCases.filter { $0 != .about || player.playbackSession != nil } }
    var body: some View {
        let remaining = player.upcomingItems.count
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Picker(DesktopInterfaceText.value("music.now.details"), selection: $panel) {
                    ForEach(panels) { Text(DesktopInterfaceText.value($0.label)).tag($0) }
                }.pickerStyle(.segmented).accessibilityIdentifier("music-now-tabs")
                NavigationLink { MusicQueueView(player: player) } label: {
                    Image("music-queue").frame(width: 44, height: 44)
                }.accessibilityLabel(DesktopInterfaceText.value("music.transport.openQueue")).accessibilityIdentifier("music-now-open-queue")
            }
            switch panel {
            case .queue:
                VStack(alignment: .leading, spacing: 12) {
                    MusicQueueContinuationControls(player: player)
                    ForEach(player.upcomingItems) { entry in row(entry) }
                    DisclosureGroup(DesktopInterfaceText.value("music.search.tracks")) {
                        ForEach(player.items) { entry in row(entry) }
                    }
                    if remaining < 5 {
                        MusicQueueContinuationPlaceholders(count: 5 - remaining)
                    }
                }.accessibilityIdentifier("music-shared-queue")
            case .about:
                MusicAboutPanel(player: player)
            case .lyrics:
                MusicLyricsView(player: player, client: player.lyricsClient).accessibilityIdentifier("music-now-panel-lyrics")
            case .signal:
                MusicSignalDetailsView(player: player)
            }
        }
    }
    private func row(_ item: MusicPlaybackItem) -> some View {
        MusicPlaybackRow(item: item, owner: player.owner) { player.play(item) }
            .contextMenu {
                Button(DesktopInterfaceText.value("music.queue.playNext")) { player.moveAfterCurrent(item) }
                Button(DesktopInterfaceText.value("music.queue.remove", variables: ["title": item.track.title]), role: .destructive) { player.removeFromQueue(item) }
            }
    }
}

@MainActor private struct MusicQueueContinuationControls: View {
    @Bindable var player: MusicPlayback
    private var sourceName: String {
        if let name = player.origin?.name.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty { return name }
        switch player.currentTrack?.connectorId {
        case .some("subsonic"): return "Subsonic"
        case .some("soundcloud"): return "SoundCloud"
        case .some("jellyfin"): return "Jellyfin"
        case .some("plex"): return "Plex"
        case .some("local"): return DesktopInterfaceText.value("music.library.permanent")
        case .some(let value): return value.capitalized
        case .none: return DesktopInterfaceText.value("Music")
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Button {
                    player.loadMoreMusic()
                } label: {
                    HStack(spacing: 7) {
                        if player.queueContinuationLoading { ProgressView().controlSize(.small) }
                        else { Image(systemName: "plus") }
                        Text(DesktopInterfaceText.value(player.queueContinuationLoading ? "music.loading" : "music.library.loadMore"))
                    }
                }
                .buttonStyle(.bordered)
                .disabled(player.queueContinuationLoading || player.playbackSession == nil || player.currentTrack == nil)
                .accessibilityIdentifier("music-now-load-more")

                Picker(selection: Binding(
                    get: { player.queueContinuationMode },
                    set: { player.setQueueContinuationMode($0) }
                )) {
                    Text(DesktopInterfaceText.value("music.now.sameContext")).tag(MusicQueueContinuationMode.context)
                    Text(DesktopInterfaceText.value("music.now.discoverNew")).tag(MusicQueueContinuationMode.discover)
                } label: {
                    Label(DesktopInterfaceText.value(player.queueContinuationMode == .context
                        ? "music.now.sameContext" : "music.now.discoverNew"), systemImage: "chevron.down")
                }
                .pickerStyle(.menu)
                .accessibilityLabel(DesktopInterfaceText.value("music.now.moreMode"))
                .accessibilityHint(DesktopInterfaceText.value(player.queueContinuationMode == .context
                    ? "music.now.continueFrom" : "music.now.discoverHint", variables: ["name": sourceName]))
                .accessibilityIdentifier("music-now-more-mode")
            }
            .accessibilityIdentifier("music-now-more-controls")
            if let notice = player.queueContinuationNotice {
                Text(notice).font(.caption).foregroundStyle(.secondary)
                    .accessibilityElement().accessibilityIdentifier("music-now-more-notice")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("music-now-continuation")
    }
}

private struct MusicQueueContinuationPlaceholders: View {
    let count: Int
    var body: some View {
        VStack(spacing: 10) {
            ForEach(0..<count, id: \.self) { _ in
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 7).fill(.quaternary).frame(width: 42, height: 42)
                    VStack(alignment: .leading, spacing: 7) {
                        Capsule().fill(.quaternary).frame(width: 132, height: 8)
                        Capsule().fill(.quaternary).frame(width: 86, height: 7)
                    }
                    Spacer()
                    Capsule().fill(.quaternary).frame(width: 28, height: 7)
                }.padding(.vertical, 3)
            }
        }
        .accessibilityHidden(true)
        .accessibilityIdentifier("music-now-queue-placeholders")
    }
}

/// Desktop's MusicListeningDetails: the artist overview, the recording credits
/// and where to buy. The soundtrack link is not ported yet. The metadata client
/// is created for this panel because the expanded player is mounted by the app
/// shell, outside the music screen that owns the shared one.
@MainActor private struct MusicAboutPanel: View {
    @Bindable var player: MusicPlayback
    @State private var client: MusicArtistClient?
    @State private var recording: MusicRecordingProfile?
    @State private var resolved: MusicArtistReference?
    private let catalog: any MusicCatalogCalling = MusicCatalogClient()
    private var artist: MusicArtistReference? { recording?.primaryArtist ?? resolved }
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            if let track = player.currentTrack, let client {
                if let artist { MusicArtistOverviewView(artist: artist, client: client, catalog: catalog) }
                MusicRecordingCreditsView(track: track, metadata: client, catalog: catalog)
                MusicWhereToBuyView(track: track, artist: artist, client: client)
            }
        }.frame(maxWidth: .infinity, alignment: .leading).accessibilityIdentifier("music-now-panel-about")
            .task(id: player.currentItem?.id ?? "") {
                recording = nil; resolved = nil
                if client == nil { client = player.playbackSession?.makeArtistMetadataClient() }
                guard let client, let track = player.currentTrack else { return }
                do {
                    let value = try await client.recording(track)
                    try Task.checkCancellation(); recording = value
                    if value == nil { let canonical = try await client.canonicalArtist(for: track); try Task.checkCancellation(); resolved = canonical }
                } catch { }
            }
            .onDisappear { client?.dispose(); client = nil }
    }
}

/// Only the transport observes the playback clock. Metadata, artwork and the
/// queue do not rebuild and re-encode its listening order on every position tick.
@MainActor private struct MusicTransportControls: View {
    @Bindable var player: MusicPlayback
    @State private var seek = 0.0
    @State private var editing = false
    @Environment(\.musicArtworkPalette) private var palette
    var body: some View {
        VStack(spacing: 14) {
            Slider(value: $seek, in: 0...max(player.duration, 1)) { edit in editing = edit; if !edit { player.seek(seek) } }.accessibilityLabel(DesktopInterfaceText.value("music.position"))
            HStack { Text(time(editing ? seek : player.position)); Spacer(); Text(time(player.duration)) }.font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            HStack(spacing: 10) {
                Button { player.shuffle.toggle() } label: { MusicGlyph("shuffle").foregroundStyle(player.shuffle ? HarborTheme.accent : .secondary).frame(width: 44, height: 44) }.accessibilityLabel(DesktopInterfaceText.value("music.transport.shuffle")).accessibilityAddTraits(player.shuffle ? .isSelected : [])
                Button { player.previous() } label: { MusicGlyph("previous").frame(width: 44, height: 44) }.accessibilityLabel(DesktopInterfaceText.value("music.previous"))
                MusicPlayButton(player: player, diameter: 54)
                Button { player.next() } label: { MusicGlyph("next").frame(width: 44, height: 44) }.accessibilityLabel(DesktopInterfaceText.value("music.next"))
                Menu { Picker(DesktopInterfaceText.value("music.transport.repeat"), selection: $player.repeatMode) { ForEach(MusicRepeat.allCases) { Text($0.title).tag($0) } } } label: {
                    MusicGlyph(player.repeatMode == .one ? "repeat-one" : "repeat").foregroundStyle(player.repeatMode == .off ? .secondary : HarborTheme.accent).frame(width: 44, height: 44)
                }.accessibilityLabel(DesktopInterfaceText.value("music.transport.repeat")).accessibilityValue(player.repeatMode.title)
            }.buttonStyle(.plain)
            Slider(value: Binding(get: { min(player.volumeMaximum, player.volume) }, set: { player.changeVolume($0) }), in: 0...player.volumeMaximum) { Text(DesktopInterfaceText.value("music.volume")) } minimumValueLabel: { MusicGlyph("volume-low") } maximumValueLabel: { MusicGlyph("volume-high") }
        }.tint(MusicArtworkStyle.seek(palette))
            .onChange(of: player.position) { _, value in if !editing { seek = value } }
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
        // Desktop's music.card.copyTitle: "title - artist", the same text the local library menu copies.
        Button(DesktopInterfaceText.value("music.card.copyTitle")) { UIPasteboard.general.string = track.title + " - " + track.artist }
    }
}

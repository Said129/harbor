import SwiftUI

@MainActor struct MusicCollectionCover: View {
    let tracks: [MusicTrack]
    let local: [MusicRecord]
    let owner: String
    var playlist: String?
    var onCustomChange: ((Bool) -> Void)?
    @State private var custom: DecodedArtworkBitmap?
    @State private var customIdentity = ""
    private var tiles: [MusicPlaybackItem] {
        let imported = Dictionary(local.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var seen = Set<String>(), result: [MusicPlaybackItem] = []
        for track in tracks {
            let record = imported[track.id], artwork = track.artwork.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = !artwork.isEmpty ? artwork : record?.cover.map { "local:" + $0 } ?? ""
            if !key.isEmpty, seen.insert(key).inserted { result.append(.init(track: track, localRecord: record)) }
            if result.count == 4 { break }
        }
        return result
    }
    var body: some View {
        let identity = owner + "|" + (playlist ?? "")
        let revision = playlist.map { MusicPlaylistCoverStore.shared.revision(owner: owner, playlist: $0) } ?? 0
        Group {
            if customIdentity == identity, let custom { BoundedArtworkImage(image: custom.image, fit: .fill).clipShape(.rect(cornerRadius: 8)) }
            else { mosaic }
        }.accessibilityHidden(true).task(id: identity + "|" + String(revision)) {
            if customIdentity != identity { custom = nil; customIdentity = identity; onCustomChange?(false) }
            guard let playlist else { custom = nil; onCustomChange?(false); return }
            do {
                let image = try await MusicPlaylistCoverStore.shared.image(owner: owner, playlist: playlist)
                try Task.checkCancellation(); custom = image; onCustomChange?(image != nil)
            } catch is CancellationError { }
            catch { custom = nil; onCustomChange?(false) }
        }
    }
    private var mosaic: some View {
        GeometryReader { geometry in
            let entries = tiles, width = geometry.size.width, height = geometry.size.height
            Group {
                if entries.isEmpty { Image("music-queue").resizable().scaledToFit().padding(width * 0.24).frame(width: width, height: height).background(HarborTheme.surface) }
                else if entries.count == 1 { tile(entries[0], width: width, height: height) }
                else if entries.count == 2 { HStack(spacing: 0) { tile(entries[0], width: width / 2, height: height); tile(entries[1], width: width / 2, height: height) } }
                else {
                    VStack(spacing: 0) {
                        HStack(spacing: 0) { tile(entries[0], width: width / 2, height: height / 2); tile(entries[1], width: width / 2, height: height / 2) }
                        if entries.count == 3 { tile(entries[2], width: width, height: height / 2) }
                        else { HStack(spacing: 0) { tile(entries[2], width: width / 2, height: height / 2); tile(entries[3], width: width / 2, height: height / 2) } }
                    }
                }
            }.frame(width: width, height: height)
        }.clipped().clipShape(.rect(cornerRadius: 8)).accessibilityHidden(true)
    }
    private func tile(_ item: MusicPlaybackItem, width: CGFloat, height: CGFloat) -> some View {
        Group {
            if let record = item.localRecord { MusicCover(record: record, owner: owner, cornerRadius: 0) }
            else { Artwork(url: item.track.artwork.trimmingCharacters(in: .whitespacesAndNewlines), maxPixels: 480, failureIcon: "nav-music") }
        }.frame(width: width, height: height).clipped()
    }
}

@MainActor struct MusicCollectionTrackRow: View {
    let track: MusicTrack
    let record: MusicRecord?
    let owner: String
    let play: () -> Void
    @AppStorage("harbor.music.playlistView") private var layout = "list"
    private var compact: Bool { layout == "compact" }
    private var missingFile: Bool { track.connectorId == "local" && record == nil }
    private var current: Bool { MusicPlayback.shared.owner == owner && MusicPlayback.shared.currentTrack.map { MusicQueueOrder.key($0) == MusicQueueOrder.key(track) } == true }
    var body: some View {
        Button(action: play) {
            HStack(spacing: 12) {
                MusicPlaybackCover(item: .init(track: track, localRecord: record), owner: owner).frame(width: compact ? 32 : 44, height: compact ? 32 : 44)
                VStack(alignment: .leading, spacing: 4) {
                    Text(track.title).font(compact ? .subheadline : .body).lineLimit(1)
                    Text(missingFile ? DesktopInterfaceText.value("music.mobile.missingFile") : track.artist + (track.album.map { " · " + $0 } ?? "")).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }.frame(maxWidth: .infinity, alignment: .leading)
                if MusicCollections.shared.isLiked(track.id, owner: owner) { Image(systemName: "heart.fill").font(.caption).foregroundStyle(HarborTheme.accent) }
                if current { MusicGlyph(MusicPlayback.shared.paused ? "pause" : "waveform").foregroundStyle(HarborTheme.accent) }
                Text(track.durationLabel).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }.frame(minHeight: 44).contentShape(.rect)
        }.buttonStyle(.plain).disabled(missingFile).accessibilityLabel(track.title + ", " + track.artist)
            .accessibilityValue(MusicCollections.shared.isLiked(track.id, owner: owner) ? DesktopInterfaceText.value("Saved") : "")
            .accessibilityIdentifier("music-collection-recording-" + track.id)
    }
}

@MainActor struct MusicCollectionToolsView: View {
    @Binding var filters: MusicCollectionFilters
    let model: MusicCollectionModel
    var canSortAdded = true
    @AppStorage("harbor.music.playlistView") private var layout = "list"
    var body: some View {
        HStack(spacing: 10) {
            Text(DesktopInterfaceText.value("music.card.trackCount", variables: ["count": String(model.tracks.count)])).font(.caption).foregroundStyle(.secondary)
            if filters.active { Button(DesktopInterfaceText.value("music.playlistTools.clear")) { filters.reset() }.font(.caption) }
            Spacer(minLength: 2)
            if model.loading { ProgressView().controlSize(.small) }
            Menu {
                Section(DesktopInterfaceText.value("music.sort.label")) {
                    ForEach(MusicSort.allCases.filter { canSortAdded || $0 != .added }) { sort in
                        Button {
                            filters.descending = filters.sort == sort ? !filters.descending : false; filters.sort = sort
                        } label: {
                            let selected = MusicCollectionFilters(sort: sort)
                            if filters.sort == sort { Label(selected.sortTitle, image: "music-check") } else { Text(selected.sortTitle) }
                        }
                    }
                    Toggle(DesktopInterfaceText.value("music.mobile.reverseOrder"), isOn: $filters.descending).disabled(filters.sort == .original)
                }
                Picker(DesktopInterfaceText.value("music.playlistTools.view"), selection: $layout) {
                    Text(DesktopInterfaceText.value("music.playlistTools.list")).tag("list")
                    Text(DesktopInterfaceText.value("music.playlistTools.compact")).tag("compact")
                }
                if model.sources.count > 1 {
                    Picker(DesktopInterfaceText.value("music.playlistTools.source"), selection: $filters.source) {
                        Text(DesktopInterfaceText.value("music.filter.all")).tag("all")
                        ForEach(model.sources, id: \.self) { source in Text(model.sourceLabels[source] ?? source).tag(source) }
                    }
                }
                Picker(DesktopInterfaceText.value("music.playlistTools.content"), selection: $filters.content) {
                    Text(DesktopInterfaceText.value("music.filter.all")).tag(MusicContentFilter.all)
                    Text(DesktopInterfaceText.value("music.playlistTools.explicit")).tag(MusicContentFilter.explicit)
                    Text(DesktopInterfaceText.value("music.playlistTools.clean")).tag(MusicContentFilter.clean)
                }
            } label: {
                HStack(spacing: 5) {
                    Text(filters.sortTitle).font(.caption).lineLimit(1)
                    if filters.descending && filters.sort != .original { Image(systemName: "arrow.up").font(.caption) }
                    MusicGlyph("filter")
                }.frame(minHeight: 44)
            }.accessibilityLabel(DesktopInterfaceText.value("music.playlistTools.options")).accessibilityValue(filters.sortTitle)
                .accessibilityIdentifier("music-mixed-collection-tools")
        }
    }
}

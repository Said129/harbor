import SwiftUI

/// Desktop's "New Episodes" row (`views/home/new-episodes-section.tsx`), shown under Continue Watching when `homeNewEpisodes` is on.
/// Home places it only when the setting is on, so the empty VStack below never adds a gap while the setting is off.
struct NewEpisodesRow: View {
    let app: AppModel
    @State private var found: [NewEpisode] = []
    @State private var dismissed: [String] = NewEpisodeDismissals.load()

    private var enabled: Bool { InterfacePreferences.shared.homeNewEpisodes }
    private var visible: [NewEpisode] { NewEpisodeRule.visible(found, dismissed: Set(dismissed)) }
    /// Reloads when the setting, the owner, or any Continue Watching record changes.
    private var signature: String {
        let records = app.library.continuing.map { $0.id + "|" + $0.modified }.joined(separator: ",")
        return [String(enabled), app.library.owner, records].joined(separator: "|")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if enabled && !visible.isEmpty {
                header
                ScrollView(.horizontal) {
                    LazyHStack(alignment: .top, spacing: 12) {
                        ForEach(visible) { episode in
                            NewEpisodeCard(app: app, episode: episode) { dismiss([episode.key]) }
                        }
                    }.padding(.horizontal)
                }.scrollIndicators(.hidden)
            }
        }
        .task(id: signature) { await load() }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text("\(visible.count)").font(HarborTheme.font(12, weight: .bold)).padding(.horizontal, 7).padding(.vertical, 2)
                .background(HarborTheme.accent, in: .capsule).foregroundStyle(HarborTheme.background)
            Text(DesktopInterfaceText.value("New Episodes")).font(HarborTheme.font(17, weight: .medium))
                .accessibilityAddTraits(.isHeader).accessibilityIdentifier("new-episodes-title")
            Spacer()
            Button(DesktopInterfaceText.value("Dismiss all")) { dismiss(found.map(\.key)) }
                .font(HarborTheme.font(13, weight: .medium)).frame(minHeight: 44)
                .accessibilityIdentifier("new-episodes-dismiss-all")
        }.padding(.horizontal)
    }

    private func dismiss(_ keys: [String]) {
        dismissed = NewEpisodeDismissals.adding(keys, to: dismissed)
        NewEpisodeDismissals.save(dismissed)
    }

    /// Desktop's `newEpisodesFor` per series, using the metadata the Continue Watching cards already load and cache.
    private func load() async {
        guard enabled else { found = []; return }
        let rows = HomeCatalogFilter.continueWatching(app.library.continuing, animeOnlyInAnimeRoom: InterfacePreferences.shared.animeOnlyInAnimeRoom, detectedAnime: app.animeDetection.identifiers)
        let now = Date()
        var lists: [[NewEpisode]] = []
        for record in NewEpisodeRule.candidates(rows) {
            guard !Task.isCancelled, let media = record.media, let lastWatched = NewEpisodeRule.lastWatched(record) else { continue }
            guard let detailed = try? await app.continuationMetadata(media) else { continue }
            lists.append(NewEpisodeRule.episodes(in: detailed, seriesID: record.id, seriesName: media.name, poster: media.poster, lastWatched: lastWatched, now: now))
        }
        guard !Task.isCancelled, enabled else { return }
        found = NewEpisodeRule.merged(lists)
    }
}

private struct NewEpisodeCard: View {
    let app: AppModel
    let episode: NewEpisode
    let onDismiss: () -> Void

    private var series: Media? { app.library.continuing.first(where: { $0.id == episode.seriesID })?.media }
    private var caption: String {
        episode.title.isEmpty ? EpisodePresentation.Coordinates(season: episode.season, episode: episode.episode).compactCaption : episode.title
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            face
            Button(action: onDismiss) {
                Image(systemName: "xmark").font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white).frame(width: 28, height: 28)
                    .background(.black.opacity(0.75), in: .circle)
                    .frame(width: 44, height: 44).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel(DesktopInterfaceText.value("Dismiss"))
                .accessibilityIdentifier("new-episode-dismiss")
        }.frame(width: 260, alignment: .leading)
    }

    @ViewBuilder private var face: some View {
        if let series {
            NavigationLink { DetailView(media: series, app: app) } label: { artwork }
                .buttonStyle(.plain).accessibilityIdentifier("new-episode-open")
        } else {
            artwork
        }
    }

    private var artwork: some View {
        Artwork(url: episode.still ?? episode.poster, maxPixels: 650)
            .frame(width: 260, height: 260 * 9 / 16)
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(episode.seriesName).font(HarborTheme.font(13, weight: .semibold)).lineLimit(1)
                    Text(caption).font(HarborTheme.font(12)).lineLimit(1).opacity(0.75)
                }
                .foregroundStyle(.white).padding(10)
            }
            .clipShape(.rect(cornerRadius: 8))
    }
}

import SwiftUI

struct EpisodeList: View {
    let media: Media
    let library: LibraryModel
    var animeGrouping: Binding<AnimeEpisodeGrouping>? = nil
    var ordering: EpisodeOrderProjection? = nil
    var pool: AnimeEpisodePool? = nil
    var orderOptions: [TVDBEpisodeOrderOption] = []
    var selectOrder: (TVDBEpisodeOrderKind) -> Void = { _ in }
    var richOrderPanel = true
    var orderLoading = false
    var franchise: [AnimeFranchiseEntry] = []
    var activeFranchiseID: String? = nil
    var selectFranchise: (AnimeFranchiseEntry) -> Void = { _ in }
    var franchiseLoading = false
    var loadingExtras = Set<String>()
    var playExtra: (AnimeFranchiseExtra) -> Void = { _ in }
    var toggleExtraWatched: (AnimeFranchiseExtra) -> Void = { _ in }
    let play: (Episode?) -> Void
    @State private var season = 1
    @State private var orderSection = ""
    @State private var revealed = Set<String>()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var videos: [Episode] { ordering?.videos ?? WatchedCodec.ordered(media.videos ?? []) }
    private var seasons: [Int] { Array(Set(videos.compactMap(\.listedSeason))).sorted() }
    private var sections: [EpisodeOrderSection] { ordering?.sections ?? [] }
    private var currentSection: EpisodeOrderSection? { sections.first { $0.id == orderSection } ?? sections.first }
    private var visible: [Episode] { currentSection?.episodes ?? videos.filter { ($0.listedSeason ?? season) == season } }
    private var visibleRows: [EpisodeOrderRow] { currentSection?.rows ?? visible.map(EpisodeOrderRow.episode) }
    private var episodeSummary: String {
        let count = ordering == nil ? seasons.filter { $0 > 0 }.count : sections.filter { !$0.extra }.count
        return "\(videos.filter { ($0.listedSeason ?? 1) > 0 }.count) episodios · \(count) \(count == 1 ? "temporada" : "temporadas")"
    }
    var body: some View {
        let watched = pool?.watched(in: library) ?? [media.id: library.watchedEpisodes(media)]
        LazyVStack(alignment: .leading, spacing: 18) {
            if let animeGrouping {
                Picker(DesktopInterfaceText.value("Episodes"), selection: animeGrouping) {
                    Text(DesktopInterfaceText.value("Seasons")).tag(AnimeEpisodeGrouping.seasons)
                    Text(DesktopInterfaceText.value("All")).tag(AnimeEpisodeGrouping.continuous)
                }.pickerStyle(.segmented).accessibilityIdentifier("anime-episode-grouping")
            }
            HStack {
                Text("Episodios").font(.title2.bold()).accessibilityIdentifier("detail-episode-summary")
                    .accessibilityValue(episodeSummary)
                Spacer()
                if let ordering, richOrderPanel {
                    TVDBOrderPanel(sections: sections, options: orderOptions, activeKind: ordering.kind,
                        selection: Binding(get: { currentSection?.id ?? "" }, set: { orderSection = $0 }), selectOrder: selectOrder, loading: orderLoading)
                } else if ordering != nil {
                    Picker(DesktopInterfaceText.value("Seasons"), selection: Binding(get: { currentSection?.id ?? "" }, set: { orderSection = $0 })) {
                        ForEach(sections) { Text($0.label).tag($0.id) }
                    }.pickerStyle(.menu).accessibilityIdentifier("episode-season")
                } else if seasons.count > 1 { Picker("Temporada", selection: $season) {
                    ForEach(seasons, id: \.self) { Text($0 == 0 ? "Especiales" : "Temporada \($0)").tag($0) }
                }.pickerStyle(.menu).accessibilityIdentifier("episode-season") }
                else if franchise.count > 1 {
                    AnimeSeasonPicker(entries: franchise, activeID: activeFranchiseID, select: selectFranchise, loading: franchiseLoading)
                }
            }
            ForEach(visibleRows) { row in
                switch row {
                case .episode(let episode): sourceRow(episode, watched: watched)
                case .franchise(let extra):
                    AnimeFranchiseExtraRow(extra: extra, watched: library.items.first(where: { $0.id == extra.entry.id })?.watched == true,
                        loading: loadingExtras.contains(extra.entry.id), play: { playExtra(extra) }, toggleWatched: { toggleExtraWatched(extra) })
                }
            }
        }.animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: revealed)
            .task(id: media.identity) { if !seasons.contains(season) { season = seasons.first(where: { $0 > 0 }) ?? seasons.first ?? 1 } }
            .onChange(of: seasons) { _, _ in if !seasons.contains(season) { season = seasons.first(where: { $0 > 0 }) ?? seasons.first ?? 1 } }
            .onChange(of: sections.map(\.id)) { _, ids in
                if !ids.contains(orderSection) {
                    let record = library.items.first { $0.id == media.id }
                    let next = ordering.flatMap { pool?.startingEpisode(in: library, presentation: $0) }
                        ?? EpisodeSequence.startingEpisode(media.videos ?? [], record: record, watched: library.watchedEpisodes(media), presentation: ordering)
                    orderSection = sections.first(where: { $0.episodes.contains(where: { $0.id == next?.id }) })?.id ?? ids.first ?? ""
                }
            }
    }
    @ViewBuilder private func sourceRow(_ episode: Episode, watched: [String: Set<String>]) -> some View {
        let source = pool?.source(for: episode) ?? media
        let seen = watched[source.id]?.contains(episode.watchedKey) == true
        let hidden = InterfacePreferences.shared.hideSpoilers && !seen && !revealed.contains(episode.routingKey)
        let episodeLabel = DesktopInterfaceText.value("Episode {n}").replacingOccurrences(of: "{n}", with: String(episode.listedEpisode ?? 0))
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .top, spacing: 0) {
                Button { play(episode) } label: {
                    VStack(alignment: .leading, spacing: 9) {
                        HStack(alignment: .top, spacing: 12) {
                            Artwork(url: episode.thumbnail, fallback: source.background, maxPixels: 400)
                                .blur(radius: hidden && InterfacePreferences.shared.blurEpisodes ? 14 : 0)
                                .scaleEffect(hidden && InterfacePreferences.shared.blurEpisodes ? 1.04 : 1)
                                .frame(width: 125, height: 74).overlay { Image("ui-play-filled").resizable().scaledToFit().frame(width: 24, height: 24).foregroundStyle(.white).shadow(radius: 5) }.clipShape(.rect(cornerRadius: 8))
                            VStack(alignment: .leading, spacing: 6) {
                                Text(episode.name ?? episode.title ?? episodeLabel).font(.subheadline.weight(.semibold)).lineLimit(2)
                                    .blur(radius: hidden && InterfacePreferences.shared.spoilerHideTitles ? 5 : 0)
                                    .accessibilityLabel(hidden && InterfacePreferences.shared.spoilerHideTitles ? episodeLabel : episode.name ?? episode.title ?? episodeLabel)
                                Text("T\(episode.listedSeason ?? 0) · E\(episode.listedEpisode ?? 0)").font(.caption).foregroundStyle(.secondary)
                                if let date = episode.releaseDate { Text(date, style: .date).font(.caption2).foregroundStyle(.secondary) }
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }
                        if InterfacePreferences.shared.showEpisodeDescription, let overview = episode.overview, !overview.isEmpty {
                            Text(overview).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                                .blur(radius: hidden && InterfacePreferences.shared.spoilerHideDescriptions ? 5 : 0)
                                .accessibilityLabel(hidden && InterfacePreferences.shared.spoilerHideDescriptions ? DesktopInterfaceText.value("Spoilers") : overview)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                }.buttonStyle(.plain).disabled(!episode.available)
                    .accessibilityLabel("Reproducir episodio \(episode.listedEpisode ?? 0)")
                    .accessibilityIdentifier("detail-episode-\(episode.id)")
                Button { Task { await library.toggleEpisode(source, episode: episode) } } label: {
                    Image(seen ? "ui-mark-unwatched" : "ui-mark-watched").resizable().scaledToFit().frame(width: 23, height: 23).frame(width: 44, height: 44).contentShape(Rectangle())
                }.buttonStyle(.plain).disabled(library.busy || !episode.available).accessibilityLabel(seen ? "Marcar episodio como no visto" : "Marcar episodio como visto")
            }
            if hidden && (InterfacePreferences.shared.blurEpisodes || InterfacePreferences.shared.spoilerHideTitles || InterfacePreferences.shared.spoilerHideDescriptions) {
                Button(DesktopInterfaceText.value("Reveal")) { revealed.insert(episode.routingKey) }.font(.caption).frame(minHeight: 44)
            }
            if !episode.available { Text("Próximamente").font(.caption).foregroundStyle(HarborTheme.accent) }
            Divider()
        }
    }

}

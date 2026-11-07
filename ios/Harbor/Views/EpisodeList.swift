import SwiftUI

struct EpisodeList: View {
    let media: Media
    let library: LibraryModel
    var preferredEpisode: Episode? = nil
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
    var selectSeasonArtwork: (EpisodeOrderSection?) -> Void = { _ in }
    var playExtra: (AnimeFranchiseExtra) -> Void = { _ in }
    var toggleExtraWatched: (AnimeFranchiseExtra) -> Void = { _ in }
    let play: (Episode?) -> Void
    @State private var season = 1
    @State private var preferredApplied = false
    @State private var orderSection = ""
    @State private var revealed = Set<String>()
    @State private var hiddenKeys = HiddenEpisodes.all()
    @State private var showHidden = false
    @State private var episodeRatings: [String: Double] = [:]
    @State private var arcMode = false
    @State private var arcID = ""
    @State private var arcs: [EpisodeArc] = []
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var videos: [Episode] { ordering?.videos ?? WatchedCodec.ordered(media.videos ?? []) }
    private var seasons: [Int] { Array(Set(videos.compactMap(\.listedSeason))).sorted() }
    private var sections: [EpisodeOrderSection] { ordering?.sections ?? [] }
    private var currentSection: EpisodeOrderSection? { sections.first { $0.id == orderSection } ?? sections.first }
    private var visible: [Episode] { currentSection?.episodes ?? videos.filter { ($0.listedSeason ?? season) == season } }
    private var orderedRows: [EpisodeOrderRow] {
        let rows = arcActive ? arcRows : (currentSection?.rows ?? visible.map(EpisodeOrderRow.episode))
        return InterfacePreferences.shared.episodeSort == "newest" ? rows.reversed() : rows
    }
    private func hiddenKey(_ episode: Episode) -> String {
        HiddenEpisodes.key(episode.sourceMetaID ?? media.id, season: episode.season ?? 0, episode: episode.episode ?? 0)
    }
    private func isHidden(_ row: EpisodeOrderRow) -> Bool {
        if case .episode(let episode) = row { return hiddenKeys.contains(hiddenKey(episode)) }
        return false
    }
    /// With "Hide and skip episodes" on, hidden episodes leave the list until "Show hidden episodes" is switched on.
    private var visibleRows: [EpisodeOrderRow] {
        guard InterfacePreferences.shared.episodeHiding, !showHidden, !hiddenKeys.isEmpty else { return orderedRows }
        return orderedRows.filter { !isHidden($0) }
    }
    private func setHidden(_ hidden: Bool, _ episode: Episode) {
        HiddenEpisodes.set(hidden, metaID: episode.sourceMetaID ?? media.id, season: episode.season ?? 0, episode: episode.episode ?? 0)
        hiddenKeys = HiddenEpisodes.all()
    }
    private var hiddenToggle: some View {
        let count = orderedRows.filter(isHidden).count
        return Button { showHidden.toggle() } label: {
            Label("\(count)", systemImage: showHidden ? "eye" : "eye.slash").font(.footnote.weight(.semibold)).monospacedDigit()
                .padding(.horizontal, 12).frame(minHeight: 40).foregroundStyle(showHidden ? HarborTheme.background : HarborTheme.ink)
                .background(showHidden ? HarborTheme.ink : Color.white.opacity(0.06), in: .capsule)
        }
        .accessibilityLabel(DesktopInterfaceText.value(showHidden ? "Hide hidden episodes" : "Show hidden episodes")).accessibilityIdentifier("episode-show-hidden")
    }
    private var seriesIMDb: String? { [media.imdbID ?? "", media.id].first { $0.range(of: "^tt[0-9]+$", options: .regularExpression) != nil } }
    private var ratingsTaskID: String {
        let shown = visibleEpisodes
        return [media.identity, String(InterfacePreferences.shared.showEpisodeRating), String(shown.count), shown.first?.id ?? "", shown.last?.id ?? ""].joined(separator: "|")
    }
    private var visibleEpisodes: [Episode] {
        orderedRows.compactMap { row -> Episode? in
            if case .episode(let episode) = row { return episode }
            return nil
        }
    }
    /// Desktop's `episodeLayout`: the list (default), the horizontal strip, or the grid of cards.
    private var layout: EpisodeLayoutPolicy.Layout { EpisodeLayoutPolicy.layout(InterfacePreferences.shared.episodeLayout) }
    /// The episodes the strip and grid show: hidden episodes stay out, as they do in the list.
    private var shownEpisodes: [Episode] {
        visibleRows.compactMap { row -> Episode? in
            if case .episode(let episode) = row { return episode }
            return nil
        }
    }
    private func isFranchiseRow(_ row: EpisodeOrderRow) -> Bool {
        if case .franchise = row { return true }
        return false
    }
    /// Desktop's story arcs (`use-arc-groups.ts`): available on a plain series when the setting is on and TMDB lists arcs.
    private var arcsAvailable: Bool { InterfacePreferences.shared.episodeArcGroups && !arcs.isEmpty && ordering == nil && pool == nil }
    private var arcActive: Bool { arcMode && arcsAvailable }
    /// The active arc's episodes in arc order, as list rows.
    private var arcRows: [EpisodeOrderRow] {
        guard let arc = arcs.first(where: { $0.id == arcID }) ?? arcs.first else { return [] }
        return EpisodeArcPolicy.episodes(of: arc, in: videos).map(EpisodeOrderRow.episode)
    }
    private var arcTaskID: String {
        [media.identity, String(InterfacePreferences.shared.episodeArcGroups), String(MetadataPreferences.shared.tmdbKey.hashValue), seriesIMDb ?? "", ordering == nil ? "plain" : "ordered"].joined(separator: "|")
    }
    /// Desktop's `useArcGroups`: the show's story-arc group from TMDB, found by its TMDB id or else its IMDb id.
    private func loadArcs() async {
        arcs = []
        let configuration = MetadataPreferences.shared.configuration()
        let key = configuration.tmdbKey
        guard InterfacePreferences.shared.episodeArcGroups, ordering == nil, pool == nil, !key.isEmpty else { return }
        let service = TMDBService()
        var resolved = EpisodeArcPolicy.tvID(forMediaID: media.id)
        if resolved == nil, let imdb = seriesIMDb, let reference = try? await service.pluginReference(imdb: imdb, type: "series", key: key), reference.kind == "tv" {
            resolved = reference.id
        }
        guard let tvID = resolved, let groups = try? await service.episodeGroups(tvID: tvID, configuration: configuration), let group = EpisodeArcPolicy.storyGroup(groups) else { return }
        guard let detail = try? await service.episodeGroup(group.id, configuration: configuration), !Task.isCancelled else { return }
        let found = EpisodeArcPolicy.arcs(detail)
        arcs = found
        if !found.contains(where: { $0.id == arcID }) { arcID = found.first?.id ?? "" }
    }
    /// Desktop's episode ratings: the community's IMDb ratings, completed with OMDb's season ratings when a key is set.
    private func loadRatings() async {
        guard InterfacePreferences.shared.showEpisodeRating, pool == nil, let imdb = seriesIMDb else { episodeRatings = [:]; return }
        let community = await HarborEpisodeRatings.shared.ratings(imdb)
        guard !Task.isCancelled else { return }
        episodeRatings = community
        let keys = ProviderKeyStore.forOwner(MetadataPreferences.shared.settingsOwner ?? "guest")
        if !keys.ready { try? keys.load() }
        let omdbKey = keys.key(.omdb)
        guard !omdbKey.isEmpty else { return }
        var seasons: [Int: [Int: Double]] = [:]
        for number in EpisodeRatings.seasons(of: visibleEpisodes) {
            let found = await OmdbService.shared.seasonRatings(key: omdbKey, imdbID: imdb, season: number)
            if !found.isEmpty { seasons[number] = found }
        }
        guard !Task.isCancelled else { return }
        episodeRatings = EpisodeRatings.merged(community: community, seasons: seasons)
    }
    /// Desktop's episode sort menu (`episode-grid-controls.tsx`).
    private var sortMenu: some View {
        let current = InterfacePreferences.shared.episodeSort
        return Menu {
            ForEach(["oldest", "newest"], id: \.self) { value in
                Button { InterfacePreferences.shared.episodeSort = value } label: {
                    if current == value { Label(DesktopInterfaceText.value(value == "newest" ? "Newest" : "Oldest"), systemImage: "checkmark") }
                    else { Text(DesktopInterfaceText.value(value == "newest" ? "Newest" : "Oldest")) }
                }
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down").frame(width: 40, height: 40).background(.white.opacity(0.06), in: .circle)
        }
        .accessibilityLabel(DesktopInterfaceText.value(current == "newest" ? "Newest" : "Oldest")).accessibilityIdentifier("episode-sort")
    }
    /// Desktop's `EpisodeLayoutToggle` (`episode-layout-toggle.tsx`), as a menu beside the sort menu.
    private var layoutMenu: some View {
        let current = layout
        return Menu {
            ForEach(EpisodeLayoutPolicy.Layout.allCases, id: \.self) { value in
                Button { InterfacePreferences.shared.episodeLayout = value.rawValue } label: {
                    if current == value { Label(layoutTitle(value), systemImage: "checkmark") }
                    else { Text(layoutTitle(value)) }
                }
            }
        } label: {
            Image(systemName: layoutIcon(current)).frame(width: 40, height: 40).background(.white.opacity(0.06), in: .circle)
        }
        .accessibilityLabel(layoutTitle(current)).accessibilityIdentifier("episode-layout")
    }
    /// Desktop's Seasons and Arcs switch (`season-arc-picker.tsx`), with the arc menu while Arcs is on.
    @ViewBuilder private var arcControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker(DesktopInterfaceText.value("Arcs"), selection: $arcMode) {
                Text(DesktopInterfaceText.value("Seasons")).tag(false)
                Text(DesktopInterfaceText.value("Arcs")).tag(true)
            }.pickerStyle(.segmented).accessibilityIdentifier("episode-arc-mode")
            if arcMode {
                Picker(DesktopInterfaceText.value("Arcs"), selection: $arcID) {
                    ForEach(arcs) { arc in Text(arc.name).tag(arc.id) }
                }.pickerStyle(.menu).accessibilityIdentifier("episode-arc")
            }
        }
    }
    private func layoutTitle(_ value: EpisodeLayoutPolicy.Layout) -> String {
        switch value {
        case .list: return DesktopInterfaceText.value("List view")
        case .strip: return DesktopInterfaceText.value("Horizontal view")
        case .grid: return DesktopInterfaceText.value("Grid view")
        }
    }
    private func layoutIcon(_ value: EpisodeLayoutPolicy.Layout) -> String {
        switch value {
        case .list: return "list.bullet"
        case .strip: return "rectangle.split.3x1"
        case .grid: return "square.grid.2x2"
        }
    }
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
                if InterfacePreferences.shared.episodeHiding && orderedRows.contains(where: isHidden) { hiddenToggle }
                layoutMenu
                sortMenu
                if let ordering, richOrderPanel {
                    TVDBOrderPanel(sections: sections, options: orderOptions, activeKind: ordering.kind,
                        selection: Binding(get: { currentSection?.id ?? "" }, set: { orderSection = $0 }), selectOrder: selectOrder, loading: orderLoading)
                } else if ordering != nil {
                    Picker(DesktopInterfaceText.value("Seasons"), selection: Binding(get: { currentSection?.id ?? "" }, set: { orderSection = $0 })) {
                        ForEach(sections) { Text($0.label).tag($0.id) }
                    }.pickerStyle(.menu).accessibilityIdentifier("episode-season")
                } else if seasons.count > 1, !arcActive { Picker("Temporada", selection: $season) {
                    ForEach(seasons, id: \.self) { Text($0 == 0 ? "Especiales" : "Temporada \($0)").tag($0) }
                }.pickerStyle(.menu).accessibilityIdentifier("episode-season") }
                else if franchise.count > 1 {
                    AnimeSeasonPicker(entries: franchise, activeID: activeFranchiseID, select: selectFranchise, loading: franchiseLoading)
                }
            }
            if arcsAvailable { arcControls }
            if layout == .list {
                ForEach(visibleRows) { row in rowView(row, watched: watched) }
            } else {
                episodeGallery(watched: watched)
                ForEach(visibleRows.filter { isFranchiseRow($0) }) { row in rowView(row, watched: watched) }
            }
        }.animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: revealed)
            .task(id: [media.identity, ordering?.kind.rawValue ?? "", currentSection?.id ?? "", currentSection?.from ?? "", currentSection?.to ?? ""].joined(separator: "|")) {
                selectSeasonArtwork(currentSection)
            }
            .task(id: media.identity) {
                preferredApplied = false; chooseInitialSeason()
            }
            .task(id: ratingsTaskID) { await loadRatings() }
            .task(id: arcTaskID) { await loadArcs() }
            .onChange(of: seasons) { _, _ in chooseInitialSeason() }
            .onChange(of: sections.map(\.id)) { _, ids in
                if !ids.contains(orderSection) {
                    let record = library.items.first { $0.id == media.id }
                    let next = preferredEpisode ?? ordering.flatMap { pool?.startingEpisode(in: library, presentation: $0) }
                        ?? EpisodeSequence.startingEpisode(media.videos ?? [], record: record, watched: library.watchedEpisodes(media), presentation: ordering)
                    orderSection = sections.first(where: { $0.episodes.contains(where: { episode in
                        episode.id == next?.id || (next != nil && episode.season == next?.season && episode.episode == next?.episode && (episode.sourceMetaID == nil || episode.sourceMetaID == media.id))
                    }) })?.id ?? ids.first ?? ""
                }
            }
    }
    private func chooseInitialSeason() {
        if !preferredApplied, let preferred = preferredEpisode?.season, seasons.contains(preferred) { season = preferred; preferredApplied = true }
        else if !seasons.contains(season) { season = seasons.first(where: { $0 > 0 }) ?? seasons.first ?? 1 }
    }
    @ViewBuilder private func rowView(_ row: EpisodeOrderRow, watched: [String: Set<String>]) -> some View {
        switch row {
        case .episode(let episode): sourceRow(episode, watched: watched)
        case .franchise(let extra):
            AnimeFranchiseExtraRow(extra: extra, watched: library.items.first(where: { $0.id == extra.entry.id })?.watched == true,
                loading: loadingExtras.contains(extra.entry.id), play: { playExtra(extra) }, toggleWatched: { toggleExtraWatched(extra) })
        }
    }
    /// Desktop's `EpisodeStrip` and `EpisodeGrid`: cards in one horizontal row, or a grid with as many columns as the width allows.
    @ViewBuilder private func episodeGallery(watched: [String: Set<String>]) -> some View {
        let scale = InterfacePreferences.shared.episodeCardScale
        if layout == .grid {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: CGFloat(EpisodeLayoutPolicy.gridMinimumWidth(scale))), spacing: 16, alignment: .top)], alignment: .leading, spacing: 18) {
                ForEach(shownEpisodes) { episode in episodeCard(episode, watched: watched, width: nil) }
            }
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 12) {
                    ForEach(shownEpisodes) { episode in episodeCard(episode, watched: watched, width: CGFloat(EpisodeLayoutPolicy.stripWidth(scale))) }
                }
            }
        }
    }
    /// One strip or grid card: play, mark watched, and the same spoiler rules as the list row.
    @ViewBuilder private func episodeCard(_ episode: Episode, watched: [String: Set<String>], width: CGFloat?) -> some View {
        let source = pool?.source(for: episode) ?? media
        let seen = watched[source.id]?.contains(episode.watchedKey) == true
        let hidden = InterfacePreferences.shared.hideSpoilers && !seen && !revealed.contains(episode.routingKey)
        let episodeLabel = DesktopInterfaceText.value("Episode {n}").replacingOccurrences(of: "{n}", with: String(episode.listedEpisode ?? 0))
        let title = episode.name ?? episode.title ?? episodeLabel
        let blurTitle = hidden && InterfacePreferences.shared.spoilerHideTitles
        let blurOverview = hidden && InterfacePreferences.shared.spoilerHideDescriptions
        let fill: CGFloat? = width == nil ? CGFloat.infinity : nil
        VStack(alignment: .leading, spacing: 8) {
            Button { play(episode) } label: {
                VStack(alignment: .leading, spacing: 8) {
                    cardStill(episode, source: source, hidden: hidden)
                    Text(title).font(.subheadline.weight(.semibold)).lineLimit(2)
                        .blur(radius: blurTitle ? 5 : 0)
                        .accessibilityLabel(blurTitle ? episodeLabel : title)
                    Text("T\(episode.listedSeason ?? 0) · E\(episode.listedEpisode ?? 0)").font(.caption).foregroundStyle(.secondary)
                    if InterfacePreferences.shared.showEpisodeDescription, let overview = episode.overview, !overview.isEmpty {
                        Text(overview).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                            .blur(radius: blurOverview ? 5 : 0)
                    }
                }.frame(width: width, alignment: .leading).frame(maxWidth: fill, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(.plain).disabled(!episode.available)
                .accessibilityIdentifier("detail-episode-\(episode.id)")
            HStack(spacing: 8) {
                Button { Task { await library.toggleEpisode(source, episode: episode) } } label: {
                    Image(seen ? "ui-mark-unwatched" : "ui-mark-watched").resizable().scaledToFit().frame(width: 23, height: 23).frame(width: 44, height: 44).contentShape(Rectangle())
                }.buttonStyle(.plain).disabled(library.busy || !episode.available)
                    .accessibilityLabel(DesktopInterfaceText.value(seen ? "Mark as unwatched" : "Mark as watched"))
                if hidden && (InterfacePreferences.shared.blurEpisodes || blurTitle || blurOverview) {
                    Button(DesktopInterfaceText.value("Reveal")) { revealed.insert(episode.routingKey) }.font(.caption).frame(minHeight: 44)
                }
            }
        }.frame(width: width, alignment: .leading).frame(maxWidth: fill, alignment: .leading)
            .contextMenu {
                if InterfacePreferences.shared.episodeHiding {
                    if hiddenKeys.contains(hiddenKey(episode)) {
                        Button(DesktopInterfaceText.value("Show episode"), systemImage: "eye") { setHidden(false, episode) }
                    } else {
                        Button(DesktopInterfaceText.value("Hide episode"), systemImage: "eye.slash") { setHidden(true, episode) }
                    }
                }
            }
    }
    /// The still of a strip or grid card, with the IMDb badge.
    @ViewBuilder private func cardStill(_ episode: Episode, source: Media, hidden: Bool) -> some View {
        Artwork(url: episode.thumbnail, fallback: source.background, maxPixels: 600)
            .aspectRatio(16.0 / 9.0, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .blur(radius: hidden && InterfacePreferences.shared.blurEpisodes ? 14 : 0)
            .overlay(alignment: .bottomLeading) {
                if InterfacePreferences.shared.showEpisodeRating, let rating = EpisodeRatings.rating(for: episode, in: episodeRatings) { EpisodeRatingBadge(value: rating).padding(5) }
            }
            .clipShape(.rect(cornerRadius: 8))
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
                                .frame(width: 125, height: 74).overlay { Image("ui-play-filled").resizable().scaledToFit().frame(width: 24, height: 24).foregroundStyle(.white).shadow(radius: 5) }
                                .overlay(alignment: .bottomLeading) {
                                    if InterfacePreferences.shared.showEpisodeRating, let rating = EpisodeRatings.rating(for: episode, in: episodeRatings) { EpisodeRatingBadge(value: rating).padding(5) }
                                }.clipShape(.rect(cornerRadius: 8))
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
        }.contextMenu {
            if InterfacePreferences.shared.episodeHiding {
                if hiddenKeys.contains(hiddenKey(episode)) {
                    Button(DesktopInterfaceText.value("Show episode"), systemImage: "eye") { setHidden(false, episode) }
                } else {
                    Button(DesktopInterfaceText.value("Hide episode"), systemImage: "eye.slash") { setHidden(true, episode) }
                }
            }
        }
    }

}

/// Desktop's `EpisodeRatingBadge`: the IMDb mark and the rating on the episode's picture.
struct EpisodeRatingBadge: View {
    let value: Double
    var body: some View {
        HStack(spacing: 4) {
            Text("IMDb").font(.system(size: 8, weight: .black)).foregroundStyle(.black).padding(.horizontal, 3).padding(.vertical, 1).background(Color.yellow, in: .rect(cornerRadius: 2))
            Text(EpisodeRatings.label(value)).font(HarborTheme.font(12, weight: .bold)).foregroundStyle(.white)
        }.padding(.horizontal, 6).padding(.vertical, 3).background(Color.black.opacity(0.55), in: .rect(cornerRadius: 6))
            .accessibilityElement(children: .ignore).accessibilityLabel("IMDb " + EpisodeRatings.label(value)).accessibilityIdentifier("episode-rating")
    }
}

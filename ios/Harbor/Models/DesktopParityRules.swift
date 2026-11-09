import Foundation

/// Desktop's Top 10 numeral gate (`views/home/customizable-rows.tsx`): a row takes the numeral look only
/// when the viewer chose it and the row has at least ten titles at render time.
enum TopTenGate {
    static let minimumTitles = 10
    static func renders(active: Bool, count: Int) -> Bool { active && count >= minimumTitles }
}

/// Desktop's hero slides (`views/home.tsx`, `heroSlides`): titles with backdrop artwork first, then
/// poster-only titles, one slide per title id, at most four. An empty artwork string counts as missing.
enum HomeHeroSlides {
    static let maximum = 4
    /// The chosen row: artwork ordering first, then the shared dedupe and cap.
    static func pick(_ metas: [Media]) -> [Media] {
        let backdrops = metas.filter { hasText($0.background) }
        let posters = metas.filter { !hasText($0.background) && hasText($0.poster) }
        return cap(backdrops + posters)
    }
    /// Desktop's `heroPool` (the Featured fallback): no reordering, one slide per id, at most four.
    static func cap(_ metas: [Media]) -> [Media] {
        var seen = Set<String>()
        var slides: [Media] = []
        for media in metas where seen.insert(media.id).inserted {
            slides.append(media)
            if slides.count == maximum { break }
        }
        return slides
    }

    /// Desktop's Home `displayed.top10`: exclude the hero ids from the first row's first twenty metas, then take ten.
    static func topTen(firstRow: [Media], heroSlides: [Media]) -> [Media] {
        let heroIDs = Set(heroSlides.map(\.id))
        return Array(firstRow.prefix(20).filter { !$0.id.isEmpty && !heroIDs.contains($0.id) }.prefix(10))
    }

    /// Desktop derives the ranked set from the base Home feed before it adds
    /// custom folders, saved lists and personal rails to the page layout.
    static func topTenFeed(_ rails: [PageRail], builtIDs: Set<String>) -> [Media] {
        rails.first { rail in
            switch rail {
            case .catalog(let row): return !row.plan.isPlaybackHistoryCatalog && !row.metas.isEmpty
            case .discovery(let row): return builtIDs.contains(row.id) && !row.metas.isEmpty
            case .continuing, .sources, .list: return false
            }
        }?.metas ?? []
    }

    /// The actual Home hero slide selection shared by `CustomizedHero` and Home's Top 10 membership.
    static func displayedHome(rails: [PageRail], defaults: [Media], heroSourceID: String?, feed: HeroLayoutPolicy.HeroFeed) -> [Media] {
        if let heroSourceID, let source = rails.first(where: { $0.id == heroSourceID }) {
            let selected = pick(source.metas)
            if !selected.isEmpty { return selected }
        }
        let candidates = rails.map { HeroLayoutPolicy.Candidate(title: $0.title, hasMetas: !$0.metas.isEmpty) }
        guard let index = HeroLayoutPolicy.featuredRailIndex(feed: feed, candidates: candidates) else { return cap(defaults) }
        return cap(rails[index].metas)
    }

    private static func hasText(_ value: String?) -> Bool { !(value ?? "").isEmpty }
}

/// Desktop's detail genre pills (`views/detail.tsx`): the first three genres, and the genre-filtered
/// discover list a pill opens when the name is one of Desktop's TMDB genres.
enum DetailGenreRules {
    static let maximum = 3
    static func visible(_ genres: [String]) -> [String] { Array(genres.prefix(maximum)) }
    static func browseRail(for genre: String, isSeries: Bool) -> DiscoveryRail? {
        let table = isSeries ? CustomCalendar.tvGenres : CustomCalendar.movieGenres
        guard let id = table.first(where: { $0.0 == genre })?.1 else { return nil }
        return DiscoveryRail(
            id: "detail-genre-" + (isSeries ? "tv" : "movie") + "-\(id)",
            title: genre,
            kind: isSeries ? "series" : "movie",
            path: isSeries ? "discover/tv" : "discover/movie",
            parameters: ["with_genres": String(id)])
    }
}

/// Desktop's initial season (`lib/episode-progress.ts`, `resumeDefaultSeason`). Season 0 (specials) is
/// only used when no real season exists.
enum SeasonResumeRules {
    struct SeasonInfo: Equatable, Sendable {
        let number: Int
        let episodeCount: Int
        let watchedCount: Int
    }

    static func defaultSeason(_ seasons: [SeasonInfo], hint: Int?, localHint: Int? = nil) -> Int {
        let real = seasons.filter { $0.number >= 1 }.sorted { $0.number < $1.number }
        let first = real.first?.number ?? seasons.first?.number ?? 1
        if real.count <= 1 { return first }

        func done(_ season: SeasonInfo) -> Bool { season.episodeCount > 0 && season.watchedCount >= season.episodeCount }
        let nextUnwatched = real.first(where: { !done($0) })?.number
        let latestWatched = real.last(where: { $0.watchedCount > 0 })?.number
        let hinted = [hint, localHint].compactMap { $0 }.first { value in
            real.contains { $0.number == value }
        }
        if let chosen = hinted ?? latestWatched, let season = real.first(where: { $0.number == chosen }) {
            if done(season), let nextUnwatched, nextUnwatched > chosen { return nextUnwatched }
            return chosen
        }
        return nextUnwatched ?? real.last?.number ?? first
    }
}

/// Desktop's sidecar cover names (`src-tauri/src/music/connectors/local/tags.rs`). Names match without
/// regard to case, and the lowest-ranked name wins.
enum MusicSidecarCover {
    static let names = [
        "cover.jpg", "cover.jpeg", "cover.png",
        "folder.jpg", "folder.jpeg", "folder.png",
        "front.jpg", "front.jpeg", "front.png",
    ]

    static func choose(_ fileNames: [String]) -> String? {
        var best: (rank: Int, name: String)?
        for name in fileNames {
            guard let rank = names.firstIndex(of: name.lowercased()) else { continue }
            if let current = best, current.rank <= rank { continue }
            best = (rank, name)
        }
        return best?.name
    }
}

/// Desktop's subtitle FPS availability (`lib/player/subtitle-fps.ts`, `subtitleFpsAvailability`), in Desktop's order.
enum SubtitleFPSAvailability {
    enum Unavailable: Equatable, Sendable {
        case noTrack, notTextBased, secondaryActive, autoSyncActive, videoFPSUnavailable, nativeUnavailable
    }

    /// "While auto-sync runs": only the analyzing and applying phases. iOS keeps `synced` after a finished run and
    /// has no reset when the subtitle track changes, so `synced` cannot be treated as running without locking the control.
    static func autoSyncActive(_ phase: SubtitleSyncPhase) -> Bool {
        phase.working
    }

    static func unavailable(hasTrack: Bool, textBased: Bool, hasSecondary: Bool, autoSyncActive: Bool,
                            videoFPSKnown: Bool, nativeSupported: Bool) -> Unavailable? {
        if !hasTrack { return .noTrack }
        if !textBased { return .notTextBased }
        if hasSecondary { return .secondaryActive }
        if autoSyncActive { return .autoSyncActive }
        if !videoFPSKnown { return .videoFPSUnavailable }
        if !nativeSupported { return .nativeUnavailable }
        return nil
    }
}

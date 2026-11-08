import Foundation

/// Desktop's Fanart use on the anime detail page (`src/lib/providers/anime-detail.ts`): which title qualifies, the TVDB id
/// Fanart is asked with, one request per title per session, and how the ranked art fills the hero. Desktop asks Fanart with
/// the TVDB id from the Kitsu mapping (`kitsuToTvdb`), which iOS already keeps as `AnimeEpisodeVariants.tvdbSeriesID`.
enum AnimeFanartArtwork {
    /// Desktop asks Fanart only for series (`kind === "tv"`) with a TVDB id. Anime movies would need a TMDB id, which iOS
    /// does not keep for anime titles, so they get nothing here. Without a usable key nothing is asked.
    static func tvdbID(for media: Media, seriesID: Int?, fanartKey: String) -> Int? {
        guard RatingPosterDB.isUsableKey(fanartKey), AnimeService.isAnime(media.id), media.type != "movie" else { return nil }
        guard let seriesID, seriesID > 0 else { return nil }
        return seriesID
    }

    /// Desktop's `fa.logo` fallback (`if (!logo && fa.logo)`): Fanart's logo fills in only when the title has none.
    /// The best backdrop becomes the hero backdrop only when the title has none, and every ranked backdrop joins the
    /// gallery, as Desktop's `addBackdrop` does.
    static func merged(_ media: Media, with art: FanartTV.Art) -> Media {
        var result = media
        if result.logo?.isEmpty ?? true, let logo = art.logo { result.logo = logo }
        if result.background?.isEmpty ?? true, let backdrop = art.backdrop { result.background = backdrop }
        var details = result.details ?? MediaDetails()
        var seen = Set(details.backdrops)
        let added = art.backdrops.filter { seen.insert($0).inserted }
        guard !added.isEmpty else { return result }
        details.backdrops += added
        result.details = details
        return result
    }

    /// Fanart's answer per TVDB id and key, asked once per session. The running request is shared, and nil answers stay cached.
    @MainActor private static var requests: [String: Task<FanartTV.Art?, Never>] = [:]

    @MainActor static func art(tvdbID: Int, fanartKey: String) async -> FanartTV.Art? {
        let cacheKey = "tv:\(tvdbID):" + EBookShelf.hash(fanartKey)
        if let running = requests[cacheKey] { return await running.value }
        let task: Task<FanartTV.Art?, Never> = Task { await FanartClient(key: fanartKey).tv(tvdbID: tvdbID) }
        requests[cacheKey] = task
        return await task.value
    }
}

extension DetailModel {
    /// Desktop's Fanart fill for an anime title. Every failure, missing id or empty answer leaves the detail as it is.
    func loadFanartArtwork(fanartKey: String, owner: String, library: LibraryModel, seriesID: Int?) async {
        guard metadataReady, owner == library.owner,
              let tvdbID = AnimeFanartArtwork.tvdbID(for: media, seriesID: seriesID, fanartKey: fanartKey) else { return }
        let selected = media
        guard let art = await AnimeFanartArtwork.art(tvdbID: tvdbID, fanartKey: fanartKey) else { return }
        guard !Task.isCancelled, owner == library.owner, media.identity == selected.identity else { return }
        let merged = AnimeFanartArtwork.merged(media, with: art)
        if merged != media { media = merged }
    }
}

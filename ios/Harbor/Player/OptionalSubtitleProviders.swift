import Foundation

/// Runs the subtitle sources the person turned on in Settings, Subtitle sources, besides the addon search that always runs.
/// OpenSubtitles stays with that addon search, so its results are never doubled. Zip archives and downloads that need the
/// person's key are left out: the player's download sends no headers and does not unpack archives yet.
enum OptionalSubtitleProviders {
    static func query(_ request: SubtitleRequest, languages: [String]) -> SubtitleProviderQuery {
        let media = request.media
        var imdb = media.imdbID
        if imdb == nil, media.id.range(of: "^tt[0-9]+$", options: .regularExpression) != nil { imdb = media.id }
        var query = SubtitleProviderQuery()
        query.imdbID = imdb
        query.title = media.name
        query.year = Int(String((media.releaseInfo ?? "").prefix(4)))
        query.series = media.episodic
        query.season = request.season
        query.episode = request.episode
        query.languages = languages
        return query
    }

    /// Candidates the player can load as they are, from the providers that are on.
    static func usable(_ found: [SubtitleProviderCandidate]) -> [PlaybackSource.Subtitle] {
        found.filter { !$0.archive && !$0.requiresKey }.map { $0.subtitle }
    }

    static func search(_ request: SubtitleRequest, owner: String) async -> [PlaybackSource.Subtitle] {
        let enabled = SubtitleProviderPreferences.enabledProviders().subtracting([SubtitleProviderID.opensubtitles])
        guard !enabled.isEmpty else { return [] }
        let setup: (keys: SubtitleProviderKeys, languages: [String]) = await MainActor.run {
            let store = SubtitleProviderKeyStore.forOwner(owner)
            if !store.ready { try? store.load() }
            let keys = SubtitleProviderKeys(subdl: store.key(.subdl), subsource: store.key(.subsource))
            let languages = SubtitleLanguages.preferredCodes(PlaybackPreferences.shared.options.subtitleLanguage)
            return (keys, languages)
        }
        let found = await SubtitleProviderService().search(query(request, languages: setup.languages), enabled: enabled, keys: setup.keys)
        return usable(found)
    }
}

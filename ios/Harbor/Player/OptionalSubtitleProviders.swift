import Foundation

/// Runs the subtitle sources the person turned on in Settings, Subtitle sources, besides the addon search that always runs.
/// The built-in OpenSubtitles search steps aside for a configured OpenSubtitles addon. Download context stays in memory.
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
        query.filename = request.filename
        if media.id.hasPrefix("tmdb:"), let id = media.id.split(separator: ":").last,
           !id.isEmpty, id.allSatisfy({ $0.isASCII && $0.isNumber }) { query.tmdbID = String(id) }
        return query
    }

    static func directProviders(_ enabled: Set<SubtitleProviderID>, addons: [Addon]) -> Set<SubtitleProviderID> {
        let installed = addons.contains { addon in
            guard addon.enabled else { return false }
            let id = addon.manifest["id"].string?.lowercased()
            let isOpenSubtitles = id == "org.stremio.opensubtitles" || id == "com.opensubtitles.v3" ||
                URL(string: addon.transportUrl)?.host?.lowercased() == "opensubtitles-v3.strem.io"
            return isOpenSubtitles && addon.manifest["resources"].array.contains {
                $0.string == "subtitles" || $0["name"].string == "subtitles"
            }
        }
        return installed ? enabled.subtracting([.opensubtitles]) : enabled
    }

    static func search(_ request: SubtitleRequest, owner: String, addonsEnabled: Bool) async -> [PlaybackSource.Subtitle] {
        let enabled = directProviders(SubtitleProviderPreferences.enabledProviders(), addons: addonsEnabled ? request.addons : [])
        guard !enabled.isEmpty else { return [] }
        let setup: (keys: SubtitleProviderKeys, languages: [String]) = await MainActor.run {
            let store = SubtitleProviderKeyStore.forOwner(owner)
            if !store.ready { try? store.load() }
            let keys = SubtitleProviderKeys(subdl: store.key(.subdl), subsource: store.key(.subsource))
            let languages = SubtitleLanguages.preferredCodes(PlaybackPreferences.shared.options.subtitleLanguage)
            return (keys, languages)
        }
        let lookup = query(request, languages: setup.languages)
        let found = await SubtitleProviderService().search(lookup, enabled: enabled, keys: setup.keys)
        return found.map { candidate in
            var subtitle = candidate.subtitle
            subtitle.searchIdentity = SubtitleSearchRanking.listIdentity(for: candidate)
            subtitle.providerDownload = SubtitleProviderDownload(owner: owner, provider: candidate.provider, requiresKey: candidate.requiresKey,
                season: request.season, episode: request.episode, release: candidate.release, filename: lookup.filename)
            return subtitle
        }
    }

    /// The pivot keeps each direct provider record beside its URL so preparation can retain the
    /// provider's format, archive, release, and episode metadata. Only the candidate projection
    /// crosses into JavaScriptCore.
    static func pivotCandidates(_ request: SubtitleRequest, audioLanguage: String, owner: String,
                                addonsEnabled: Bool) async -> [SubtitleProviderCandidate] {
        let enabled = directProviders(SubtitleProviderPreferences.enabledProviders(), addons: addonsEnabled ? request.addons : [])
        guard !enabled.isEmpty else { return [] }
        let language = SubtitleLanguages.normalize(audioLanguage)
        guard !language.isEmpty else { return [] }
        let setup: (keys: SubtitleProviderKeys, languages: [String]) = await MainActor.run {
            let store = SubtitleProviderKeyStore.forOwner(owner)
            if !store.ready { try? store.load() }
            let keys = SubtitleProviderKeys(subdl: store.key(.subdl), subsource: store.key(.subsource))
            return (keys, [language])
        }
        let lookup = query(request, languages: setup.languages)
        let found = await SubtitleProviderService().search(lookup, enabled: enabled, keys: setup.keys,
                                                           preferredLanguages: setup.languages)
        return found.map { provider in
            var candidate = provider
            candidate.subtitle.providerDownload = SubtitleProviderDownload(owner: owner, provider: candidate.provider,
                requiresKey: candidate.requiresKey, season: candidate.season ?? request.season,
                episode: candidate.episode ?? request.episode, release: candidate.release, filename: lookup.filename)
            return candidate
        }
    }
}

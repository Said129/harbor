import Foundation

/// Desktop's `StreamHints` (`lib/subtitles/stream-hints.ts`): what is known about the stream being played, used to rank subtitles against it.
struct SubtitleStreamHints: Equatable, Sendable {
    var release: String? = nil
    var source: String? = nil
    var resolution: String? = nil
    var season: Int? = nil
    var episode: Int? = nil
    var preferHearingImpaired = false

    /// Desktop `streamTagsOf`: the release name wins over the addon's broad source badge, and a stated resolution wins over the name's.
    func tags() -> SubtitleReleaseMatch.Tags {
        var tags = SubtitleReleaseMatch.parse(release)
        tags.source = tags.source ?? SubtitleReleaseMatch.detectSource(source)
        tags.resolution = Self.normalizeResolution(resolution) ?? tags.resolution
        tags.season = season ?? tags.season
        tags.episode = episode ?? tags.episode
        tags.episodeEnd = episode ?? tags.episodeEnd
        return tags
    }

    /// Desktop `normalizeResolution`: "4k", "uhd" and anything with 2160 are 2160p, otherwise the first of 2160, 1080, 720, 576 or 480 with a p.
    static func normalizeResolution(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty else { return nil }
        let value = raw.lowercased()
        if value == "4k" || value == "uhd" || value.contains("2160") { return "2160p" }
        for height in ["2160", "1080", "720", "576", "480"] where value.contains(height) { return height + "p" }
        return nil
    }

    /// The hints for the stream a subtitle request was made for: its file name or title, its quality tier and the episode.
    static func from(_ request: SubtitleRequest) -> SubtitleStreamHints {
        var hints = SubtitleStreamHints()
        hints.release = request.filename ?? request.stream["title"].string ?? request.stream["description"].string
        hints.resolution = request.stream["tier"].string
        hints.season = request.season
        hints.episode = request.episode
        return hints
    }
}

/// Desktop's `streamMatchDetail` result for one candidate.
struct SubtitleStreamMatch: Equatable, Sendable {
    let score: Int
    let reasons: [String]
    let sourceRank: Int
    let level: SubtitleMatchLevel
}

/// What a provider told Harbor about a subtitle, kept beside the subtitle so it can be ranked after the search lists it.
/// Addon subtitles carry none and rank as unknown.
struct SubtitleCandidateEvidence: Equatable, Sendable {
    var provider: String
    var searchTitle: String?
    var format: String?
    var archive: Bool
    var hearingImpaired: Bool
    var forced: Bool
    var foreignOnly: Bool
    var machineTranslated: Bool
    var fromTrusted: Bool
    var release: String?
    var downloads: Int
    var ratingScore: Double?
    var ratingTotal: Int?
    var matchConfidence: String?
    var matchScore: Double?
    var episodeConfirmed: Bool
    var season: Int?
    var episode: Int?

    init(_ candidate: SubtitleProviderCandidate) {
        provider = candidate.provider.rawValue
        searchTitle = candidate.searchTitle
        format = candidate.format
        archive = candidate.archive
        hearingImpaired = candidate.hearingImpaired
        forced = candidate.forced
        foreignOnly = candidate.foreignOnly
        machineTranslated = candidate.machineTranslated
        fromTrusted = candidate.fromTrusted
        release = candidate.release
        downloads = candidate.downloads
        ratingScore = candidate.ratingScore
        ratingTotal = candidate.ratingTotal
        matchConfidence = candidate.matchConfidence
        matchScore = candidate.matchScore
        episodeConfirmed = candidate.episodeConfirmed
        season = candidate.season
        episode = candidate.episode
    }

    /// The candidate again, for the ranking rules. Nil when the provider is not one Harbor knows.
    func candidate(for subtitle: PlaybackSource.Subtitle) -> SubtitleProviderCandidate? {
        guard let id = SubtitleProviderID(rawValue: provider) else { return nil }
        var value = SubtitleProviderCandidate(subtitle: subtitle, provider: id)
        value.searchTitle = searchTitle
        value.format = format
        value.archive = archive
        value.hearingImpaired = hearingImpaired
        value.forced = forced
        value.foreignOnly = foreignOnly
        value.machineTranslated = machineTranslated
        value.fromTrusted = fromTrusted
        value.release = release
        value.downloads = downloads
        value.ratingScore = ratingScore
        value.ratingTotal = ratingTotal
        value.matchConfidence = matchConfidence
        value.matchScore = matchScore
        value.episodeConfirmed = episodeConfirmed
        value.season = season
        value.episode = episode
        return value
    }
}

/// Desktop's automatic provider choice (`use-track-autoload.ts` with `loadFirstWorkingSubtitle`): when the player has no subtitle in the
/// person's language, the best-ranked search result is loaded for them. iOS fills that gap only; it never replaces a track the file
/// already offers in the language, which Desktop does when "Prefer embedded subtitles" is off.
enum SubtitleAutoProviderChoice {
    /// Desktop's `loadFirstWorkingSubtitle` limit.
    static let attempts = 5

    /// The results to try, best first. Direct-provider results are ranked against the stream's release name. An addon result carries
    /// nothing to rank, so addon results in the person's language follow them in the order the addon gave.
    static func picks(_ subtitles: [PlaybackSource.Subtitle], preferredLanguages: [String], hints: SubtitleStreamHints?) -> [PlaybackSource.Subtitle] {
        var candidates: [SubtitleProviderCandidate] = []
        var addonRows: [(offset: Int, score: Int, subtitle: PlaybackSource.Subtitle)] = []
        for (index, subtitle) in subtitles.enumerated() {
            if let evidence = subtitle.evidence {
                if let candidate = evidence.candidate(for: subtitle) { candidates.append(candidate) }
            } else if !preferredLanguages.isEmpty {
                let score = SubtitleSelectionPolicy.languageScore(subtitle.lang ?? "", preferred: preferredLanguages)
                if score >= 0 { addonRows.append((offset: index, score: score, subtitle: subtitle)) }
            }
        }
        let ranked = SubtitleCandidateRanking.rank(candidates, preferredLanguages: preferredLanguages, hints: hints).map { $0.subtitle }
        let addons = addonRows.sorted { left, right in
            left.score == right.score ? left.offset < right.offset : left.score > right.score
        }.map { $0.subtitle }
        return Array((ranked + addons).prefix(attempts))
    }

    /// Whether the player still lacks a subtitle in a preferred language: nothing preferred is selected, and none of the tracks the file
    /// reports (embedded or external) is in a preferred language either.
    static func playerNeedsOne(tracks: [SubtitleSelectionCandidate], languages: [String]) -> Bool {
        guard !languages.isEmpty else { return false }
        return !tracks.contains { track in
            !track.forced && SubtitleSelectionPolicy.languageScore(track.language, preferred: languages) >= 0
        }
    }
}

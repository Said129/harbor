import Foundation

struct SubtitlePivotCandidate: Encodable, Sendable {
    let id: String
    let language: String
    let exactRelease: Bool
    let releaseScore: Double
    let wrongEditionRisk: Double
    let popularity: Int
    let source: String
}

struct SubtitlePivotProviderEntry: Sendable {
    let id: String
    let candidate: SubtitlePivotCandidate
    let subtitle: PlaybackSource.Subtitle
    /// Retains the direct provider's parsed fields for preparation and archive selection.
    /// It is never encoded into the JavaScript workflow bridge.
    let providerRecord: SubtitleProviderCandidate?
}

struct SubtitlePivotPreparedCandidate: Sendable {
    let document: SubtitleDocument
    let cues: [SubtitlePivotCue]
    let formatSafe: Bool
}

enum SubtitlePivotProviders {
    private static let bridgeCandidateLimit = 100
    private static let confidenceBatchLimit = 512

    @MainActor static func search(request: SubtitleRequest, source: PlaybackSource, audioLanguage: String,
                                  owner: String, workflow: SubtitlePivotWorkflow? = nil) async -> [SubtitlePivotProviderEntry] {
        let wanted = languageFamily(audioLanguage)
        guard wanted != nil else { return [] }

        let addonsEnabled = SubtitleProviderPreferences.addonsEnabled()
        async let directResults = OptionalSubtitleProviders.pivotCandidates(request, audioLanguage: audioLanguage,
                                                                            owner: owner, addonsEnabled: addonsEnabled)
        async let addonResults = searchAddons(request, source: source, enabled: addonsEnabled)
        let direct = await directResults
        let addons = await addonResults

        var entries: [SubtitlePivotProviderEntry] = []
        entries.reserveCapacity(direct.count + addons.count)
        var ordinal = 0
        for record in direct {
            guard let language = normalizedLanguage(record.subtitle.lang), languageFamily(language) == wanted else { continue }
            entries.append(makeEntry(record: record, language: language, ordinal: ordinal))
            ordinal += 1
        }
        for subtitle in addons {
            guard let language = normalizedLanguage(subtitle.lang), languageFamily(language) == wanted else { continue }
            entries.append(makeAddonEntry(subtitle, language: language, request: request, owner: owner, ordinal: ordinal))
            ordinal += 1
        }

        let localConfidences = await localConfidences(for: entries, request: request, workflow: workflow)
        entries = entries.enumerated().compactMap { index, entry in
            let confidence = localConfidences[index]
            guard confidence != "incompatible" else { return nil }
            if let record = entry.providerRecord {
                guard !record.forced, !record.foreignOnly,
                      !hasEpisodeMismatch(record, season: request.season, episode: request.episode) else { return nil }
                return makeEntry(record: record, language: entry.candidate.language, ordinal: index,
                                 localConfidence: confidence)
            }
            return makeAddonEntry(entry.subtitle, language: entry.candidate.language, request: request,
                                  owner: owner, ordinal: index, localConfidence: confidence)
        }

        // The desktop workflow ranks these same fields before taking its top candidates.
        // Apply that ordering here only when the native bridge's bounded payload requires it.
        if entries.count > bridgeCandidateLimit {
            entries.sort(by: candidatePrecedes)
            entries = Array(entries.prefix(bridgeCandidateLimit))
        }
        return entries
    }

    static func prepare(_ entry: SubtitlePivotProviderEntry, language: String, request: SubtitleRequest,
                        duration: Double, session: UUID) async throws -> SubtitlePivotPreparedCandidate {
        guard duration.isFinite, duration >= 300 else { throw HarborError(code: "subtitle-pivot-duration") }
        guard let candidateLanguage = languageFamily(entry.candidate.language),
              let wantedLanguage = languageFamily(language), candidateLanguage == wantedLanguage else {
            throw HarborError(code: "subtitle-pivot-language")
        }
        if let record = entry.providerRecord,
           hasEpisodeMismatch(record, season: request.season, episode: request.episode) {
            throw HarborError(code: "subtitle-pivot-episode")
        }
        try Task.checkCancellation()
        let files = SubtitleFileService.shared
        let imported = try await files.download(entry.subtitle, session: session)
        do {
            try Task.checkCancellation()
            let document = try await SubtitleAutoSync.load(imported.url.path)
            let cues = try document.structuralCues()
            try Task.checkCancellation()
            let format = imported.url.pathExtension.lowercased()
            let formatSafe = (format == "srt" && !document.vtt) || (format == "vtt" && document.vtt)
            await files.discard(imported, session: session)
            return SubtitlePivotPreparedCandidate(document: document, cues: cues, formatSafe: formatSafe)
        } catch {
            await files.discard(imported, session: session)
            throw error
        }
    }

    private static func searchAddons(_ request: SubtitleRequest, source: PlaybackSource,
                                     enabled: Bool) async -> [PlaybackSource.Subtitle] {
        guard enabled else { return [] }
        let active = request.addons.filter(\.enabled)
        guard !active.isEmpty else { return [] }
        let scoped = SubtitleRequest(media: request.media, videoID: request.videoID, season: request.season,
                                    episode: request.episode, addons: active, stream: request.stream,
                                    movieHash: request.movieHash)
        do {
            return try await SubtitleAddonService().search(scoped, source: source).subtitles
        } catch {
            return []
        }
    }

    private static func makeEntry(record: SubtitleProviderCandidate, language: String,
                                  ordinal: Int, localConfidence: String = "low") -> SubtitlePivotProviderEntry {
        let source = record.provider.rawValue
        let id = safeID(source: source, ordinal: ordinal)
        let exactRelease = record.matchConfidence == "exact" || localConfidence == "exact"
        let providerScore: Double = {
            guard let score = record.matchScore, score.isFinite else { return 0 }
            return clamp01(score > 1 ? score / 100 : score)
        }()
        let releaseScore = exactRelease ? 1 : max(providerScore, max(confidenceScore(record.matchConfidence), confidenceScore(localConfidence)))
        var editionPenalty: Double = localConfidence == "incompatible" ? 1 : 0
        if record.machineTranslated { editionPenalty += 0.15 }
        if record.episode != nil, !record.episodeConfirmed {
            editionPenalty += 0.15
        }
        let candidate = SubtitlePivotCandidate(id: id, language: language, exactRelease: exactRelease,
            releaseScore: releaseScore, wrongEditionRisk: clamp01(max(1 - releaseScore, editionPenalty)),
            popularity: max(0, record.downloads), source: source)
        return SubtitlePivotProviderEntry(id: id, candidate: candidate, subtitle: record.subtitle, providerRecord: record)
    }

    private static func makeAddonEntry(_ input: PlaybackSource.Subtitle, language: String,
                                       request: SubtitleRequest, owner: String, ordinal: Int,
                                       localConfidence: String = "low") -> SubtitlePivotProviderEntry {
        var subtitle = input
        subtitle.providerDownload = SubtitleProviderDownload(owner: owner, provider: nil, requiresKey: false,
            season: request.season, episode: request.episode, release: nil, filename: request.filename)
        let id = safeID(source: "addon", ordinal: ordinal)
        let exactRelease = localConfidence == "exact"
        let releaseScore = exactRelease ? 1 : confidenceScore(localConfidence)
        let candidate = SubtitlePivotCandidate(id: id, language: language, exactRelease: exactRelease,
            releaseScore: releaseScore, wrongEditionRisk: clamp01(max(1 - releaseScore,
                localConfidence == "incompatible" ? 1 : 0)), popularity: 0, source: "addon")
        return SubtitlePivotProviderEntry(id: id, candidate: candidate, subtitle: subtitle, providerRecord: nil)
    }

    private static func safeID(source: String, ordinal: Int) -> String {
        // Provider IDs and URLs may contain credentials or private query values. Keep them native.
        "\(source):\(String(format: "%04d", ordinal))"
    }

    private static func localConfidences(for entries: [SubtitlePivotProviderEntry], request: SubtitleRequest,
                                         workflow: SubtitlePivotWorkflow?) async -> [String] {
        guard let workflow else { return Array(repeating: "low", count: entries.count) }
        let descriptors = entries.map(subtitleDescriptor)
        let hints = streamHints(request)
        var result: [String] = []
        result.reserveCapacity(entries.count)
        do {
            for start in stride(from: 0, to: descriptors.count, by: confidenceBatchLimit) {
                let end = min(descriptors.count, start + confidenceBatchLimit)
                result += try await workflow.releaseConfidences(hints: hints,
                    subtitleTexts: Array(descriptors[start..<end]))
            }
            guard result.count == entries.count else { throw HarborError(code: "subtitle-pivot-provider-match") }
            return result
        } catch {
            return Array(repeating: "low", count: entries.count)
        }
    }

    private static func streamHints(_ request: SubtitleRequest) -> JSONValue {
        let stream = request.stream
        let filename = request.filename.flatMap(safeDescriptorText).flatMap(SubSourceProvider.releaseValue)
        let title = safeDescriptorText(stream["title"].string ?? stream["name"].string)
        let release = [filename, title].compactMap { $0 }.uniqued().joined(separator: " ")
        let source = safeDescriptorText(stream["source"].string ?? stream["addonName"].string)
        let resolution = safeDescriptorText(stream["resolution"].string ?? stream["quality"].string)
        var values: [String: JSONValue] = [
            "release": release.isEmpty ? .null : .string(String(release.prefix(2_000))),
            "source": source.map(JSONValue.string) ?? .null,
            "resolution": resolution.map(JSONValue.string) ?? .null,
            "season": .null,
            "episode": .null,
        ]
        if let season = request.season { values["season"] = .integer(Int64(season)) }
        if let episode = request.episode { values["episode"] = .integer(Int64(episode)) }
        return .object(values)
    }

    private static func subtitleDescriptor(_ entry: SubtitlePivotProviderEntry) -> String {
        let labels = [entry.providerRecord?.release, entry.providerRecord?.searchTitle,
                      entry.subtitle.title].compactMap(safeDescriptorText).uniqued()
        return String(labels.joined(separator: " ").prefix(2_000))
    }

    private static func safeDescriptorText(_ raw: String?) -> String? {
        guard let value = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty,
              value.rangeOfCharacter(from: .controlCharacters) == nil,
              value.range(of: #"(?i)(?:https?|ftp)://|www\.|(?:^|\s)[a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,}(?:\s|$)|(?:^|\s)(?:[a-z0-9-]+\.)+[a-z]{2,}(?::\d+)?(?:/|\?|#)|(?:api[_-]?key|access[_-]?token|token|authorization|password|secret|auth)\s*[:=]"#, options: .regularExpression) == nil,
              !isStandaloneURI(value) else {
            return nil
        }
        return String(value.prefix(2_000))
    }

    private static func isStandaloneURI(_ value: String) -> Bool {
        guard !value.contains(where: { $0.isWhitespace }),
              let scheme = URLComponents(string: value)?.scheme else { return false }
        return !scheme.isEmpty
    }

    private static func confidenceScore(_ confidence: String?) -> Double {
        switch confidence {
        case "exact": 1
        case "high": 0.92
        case "medium": 0.72
        case "low": 0.42
        case "unknown": 0.25
        default: 0
        }
    }

    private static func candidatePrecedes(_ left: SubtitlePivotProviderEntry,
                                          _ right: SubtitlePivotProviderEntry) -> Bool {
        let a = left.candidate, b = right.candidate
        if a.exactRelease != b.exactRelease { return a.exactRelease }
        if a.releaseScore != b.releaseScore { return a.releaseScore > b.releaseScore }
        if a.wrongEditionRisk != b.wrongEditionRisk { return a.wrongEditionRisk < b.wrongEditionRisk }
        if a.popularity != b.popularity { return a.popularity > b.popularity }
        return a.id < b.id
    }

    private static func hasEpisodeMismatch(_ record: SubtitleProviderCandidate, season: Int?, episode: Int?) -> Bool {
        (record.season != nil && season != nil && record.season != season) ||
            (record.episode != nil && episode != nil && record.episode != episode)
    }

    private static func normalizedLanguage(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let value = SubtitleLanguages.normalize(raw)
        return value.isEmpty || value == "und" || value == "zxx" ? nil : value
    }

    private static func languageFamily(_ raw: String) -> String? {
        guard let normalized = normalizedLanguage(raw) else { return nil }
        return String(normalized.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false).first ?? "")
    }

    private static func clamp01(_ value: Double) -> Double {
        min(1, max(0, value))
    }
}

private extension Array where Element == String {
    func uniqued() -> [String] {
        var seen = Set<String>()
        return filter { seen.insert($0).inserted }
    }
}

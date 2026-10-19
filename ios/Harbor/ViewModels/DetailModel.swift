import Foundation
import Observation

@MainActor @Observable
final class DetailModel {
    var media: Media
    var loadingMetadata = false
    var loadingStreams = false
    var loading: Bool { loadingMetadata || loadingStreams }
    var resolving = false
    var offers: [StreamOffer] = []
    var automaticOffers: [StreamOffer] = []
    var warnings: [String] = []
    var filteredSources = false
    var error: String?
    var playback: PlaybackSession?
    var selectedEpisode: Episode?
    private var lastPlayedSource: StreamSourceIdentity?
    var continuationOffer: StreamOffer? {
        StreamPreferences.shared.preferredContinuation(automaticOffers, previous: lastPlayedSource)
    }
    private let service: HarborService
    private let contextRevision: @MainActor () -> UUID
    private var metadataLoaded: Bool
    var metadataReady: Bool { metadataLoaded && !loadingMetadata }
    private var franchiseLoaded = false
    private var franchiseRequest = UUID()
    private var franchiseSelectionRequest = UUID()
    var franchise: AnimeFranchise?
    private(set) var episodePool: AnimeEpisodePool?
    private var episodePoolRequest = UUID()
    private var loadedEpisodePoolKey: String?
    private(set) var loadingEpisodePool = false
    private(set) var selectedPlaybackMedia: Media?
    var playbackContextMedia: Media { selectedPlaybackMedia ?? sourceMedia(for: selectedEpisode) ?? media }
    var loadingFranchise = false
    var activeFranchiseEntryID: String?
    private(set) var franchiseSelectionRevision = 0
    var soloFranchiseEntry: Bool { franchise?.scopedSplit == true && activeFranchiseEntryID != nil && activeFranchiseEntryID != franchise?.rootID }
    var episodeOrderScope: String { soloFranchiseEntry ? "solo" : "shared" }
    var canLoadFranchise: Bool { metadataReady && (AnimeLibraryDetection.hasDirectEvidence(media) || animeEpisodeVariants?.kitsuID != nil) }
    var franchiseChoices: [AnimeFranchiseEntry] {
        guard let franchise else { return [] }
        if franchise.scopedSplit, activeFranchiseEntryID != franchise.rootID {
            return franchise.entries.filter { $0.id != franchise.rootID && !$0.extra }
        }
        return franchise.entries
    }
    private var animeEpisodesLoaded = false
    private var animeEpisodeVariants: AnimeEpisodeVariants?
    private var tvdbOrder: TVDBEpisodeOrder?
    private var orderRequest = UUID()
    var episodeOrderProjection: EpisodeOrderProjection?
    var episodeOrderOptions: [TVDBEpisodeOrderOption] = []
    var episodeOrderLoading = false
    var canLoadEpisodeOrder: Bool { animeEpisodesLoaded && !loadingMetadata && media.episodic }
    var canLoadEpisodePool: Bool { canLoadEpisodeOrder && !soloFranchiseEntry && franchiseChoices.count > 1
        && franchise?.entries.first(where: { $0.id == activeFranchiseEntryID })?.extra != true }
    var animeEpisodeGrouping = AnimeEpisodeGrouping.saved
    var allowsContinuousAnimeEpisodes: Bool { animeEpisodeVariants?.allowsContinuous == true }
    var episodeMetadataURL: URL? {
        guard let id = tvdbOrder?.seriesID ?? animeEpisodeVariants?.tvdbSeriesID else { return nil }
        return URL(string: "https://thetvdb.com/?tab=series&id=\(id)")
    }
    private var streamRequest = UUID()
    private var resolutionRequest = UUID()
    private var sourceContinuation: SourceContinuation?
    private var streamAddons: [Addon] = []

    func prepareSourceChange(_ session: PlaybackSession, snapshot: ResumeSnapshot?) {
        sourceContinuation = snapshot.map { SourceContinuation(target: session.target, owner: session.owner, snapshot: $0, advanceStartedAtMs: session.advanceStartedAtMs ?? session.startMs) }
        playback = nil
    }
    func clearSourceChange() { sourceContinuation = nil }
    func cancelResolution() { resolutionRequest = UUID(); resolving = false }

    init(_ media: Media, service: HarborService, metadataLoaded: Bool = false, contextRevision: @escaping @MainActor () -> UUID = { AppProfileContext.shared.activationID }) {
        self.media = media; self.service = service; self.metadataLoaded = metadataLoaded; self.contextRevision = contextRevision
    }

    func load(_ addons: [Addon], owner: String, library: LibraryModel, fetch: (@MainActor () async throws -> Media)? = nil) async {
        guard !metadataLoaded else { return }
        loadingMetadata = true
        defer { loadingMetadata = false }
        do {
            let result: Media
            if let fetch { result = try await fetch() }
            else { result = try await service.metadata(media, addons: addons) }
            try Task.checkCancellation()
            guard library.owner == owner else { return }
            media = result
            metadataLoaded = true
        }
        catch is CancellationError { return }
        catch { if library.owner == owner { self.error = safeMessage(error) } }
    }

    func loadRelated(_ addons: [Addon], owner: String, library: LibraryModel) async {
        guard library.owner == owner, media.details?.similar.isEmpty ?? true else { return }
        let selected = media
        do {
            let related = try await service.related(selected, addons: addons)
            try Task.checkCancellation()
            guard library.owner == owner, media.identity == selected.identity, !related.isEmpty, media.details?.similar.isEmpty ?? true else { return }
            var details = media.details ?? MediaDetails()
            details.similar = related
            media.details = details
        } catch { return } // Optional discovery must not prevent opening or playing the title.
    }

    func loadFranchise(owner: String, library: LibraryModel, provider: AnimeFranchiseService = .shared) async {
        guard canLoadFranchise, !franchiseLoaded, owner == library.owner else { return }
        let request = UUID(), selected = media, context = contextRevision()
        franchiseRequest = request; loadingFranchise = true
        defer { if franchiseRequest == request { loadingFranchise = false } }
        do {
            let value = try await provider.franchise(for: selected.id)
            try Task.checkCancellation()
            guard franchiseRequest == request, library.owner == owner, media.identity == selected.identity,
                  contextRevision() == context else { return }
            franchise = value; activeFranchiseEntryID = value?.currentID; franchiseLoaded = value != nil
        } catch { return }
    }

    @discardableResult
    func selectFranchiseEntry(_ id: String, owner: String, library: LibraryModel, fetch: (@MainActor (AnimeFranchiseEntry) async throws -> Media)? = nil) async -> Bool {
        guard owner == library.owner, id != activeFranchiseEntryID, let entry = franchise?.entries.first(where: { $0.id == id }) else { return false }
        let request = UUID(), previous = media.identity, context = contextRevision()
        franchiseSelectionRequest = request; loadingMetadata = true
        defer { if franchiseSelectionRequest == request { loadingMetadata = false } }
        do {
            let selected: Media
            if let fetch { selected = try await fetch(entry) }
            else { selected = try await AnimeService.metadata(id: entry.id, kind: entry.media.type) }
            try Task.checkCancellation()
            guard library.owner == owner, franchiseSelectionRequest == request, media.identity == previous,
                  contextRevision() == context else { return false }
            guard !selected.name.isEmpty, selected.id == entry.id || (entry.id.hasPrefix("anilist:") && selected.id.hasPrefix("mal:") && AnimeService.isAnime(selected.id)) else { throw HarborError(code: "no-metadata") }
            streamRequest = UUID(); resolutionRequest = UUID(); orderRequest = UUID()
            resolving = false; loadingStreams = false; episodeOrderLoading = false
            offers = []; automaticOffers = []; warnings = []; filteredSources = false; error = nil
            playback = nil; selectedEpisode = nil; lastPlayedSource = nil; sourceContinuation = nil; streamAddons = []
            selectedPlaybackMedia = nil; episodePool = nil; loadedEpisodePoolKey = nil; episodePoolRequest = UUID(); loadingEpisodePool = false
            animeEpisodesLoaded = false; animeEpisodeVariants = nil; tvdbOrder = nil
            episodeOrderProjection = nil; episodeOrderOptions = []
            activeFranchiseEntryID = id; media = selected; metadataLoaded = true
            franchiseSelectionRevision &+= 1
            return true
        } catch is CancellationError { return false }
        catch {
            if !Task.isCancelled, franchiseSelectionRequest == request, library.owner == owner, contextRevision() == context { self.error = safeMessage(error) }
            return false
        }
    }

    func loadFranchiseEpisodes(language: String, owner: String, library: LibraryModel, provider: AnimeFranchiseEpisodeService = .shared) async {
        guard canLoadEpisodePool, owner == library.owner, let activeFranchiseEntryID else { return }
        let entries = franchiseChoices.filter { $0.id != activeFranchiseEntryID && !$0.extra && $0.id.hasPrefix("kitsu:") }
        let key = media.identity + "|" + language + "|" + entries.map(\.id).joined(separator: ",")
        guard loadedEpisodePoolKey != key else { return }
        let request = UUID(), selected = media, context = contextRevision()
        episodePoolRequest = request; loadingEpisodePool = true
        defer { if episodePoolRequest == request { loadingEpisodePool = false } }
        let result = await provider.entries(entries, language: language)
        guard !Task.isCancelled, episodePoolRequest == request, contextRevision() == context,
              library.owner == owner, media.identity == selected.identity, canLoadEpisodePool else { return }
        var current = media; current.videos = animeEpisodeVariants?.seasons ?? media.videos
        episodePool = AnimeEpisodePool(current: current, others: result.sources, missingEntryIDs: result.missing)
        if result.missing.isEmpty { loadedEpisodePoolKey = key }
        applyEpisodeOrder()
    }

    func sourceMedia(for episode: Episode?) -> Media? {
        guard let episode else { return media }
        if let source = episode.sourceMetaID {
            if let value = episodePool?.source(for: episode, presentation: episodeOrderProjection) { return value }
            guard source == media.id else { return nil }
        }
        guard media.videos?.contains(where: { $0.id == episode.id && $0.watchedKey == episode.watchedKey }) == true else { return nil }
        return media
    }

    func loadAnimeEpisodes(owner: String, library: LibraryModel,
        fetch: (@Sendable (Media) async -> AnimeEpisodeVariants)? = nil,
        supplement: (@Sendable (AnimeEpisodeVariants, Media) async -> AnimeEpisodeVariants)? = nil) async {
        guard !animeEpisodesLoaded, !loadingMetadata, media.videos?.isEmpty == false, library.owner == owner else { return }
        let selected = media
        let variants: AnimeEpisodeVariants
        if let fetch { variants = await fetch(selected) }
        else { variants = await AnimeEpisodeService.shared.variants(for: selected) }
        guard !Task.isCancelled, library.owner == owner, media.identity == selected.identity else { return }
        animeEpisodeVariants = variants
        media.videos = variants.episodes(animeEpisodeGrouping)
        animeEpisodesLoaded = true
        // Publish the provider list first. Optional stills never delay playback.
        let supplemented: AnimeEpisodeVariants
        if let supplement { supplemented = await supplement(variants, selected) }
        else { supplemented = await TVDBService.shared.supplement(variants, for: selected) }
        guard !Task.isCancelled, library.owner == owner, media.identity == selected.identity else { return }
        animeEpisodeVariants = supplemented
        applyEpisodeOrder()
    }

    func loadEpisodeOrder(setting: String, language: String, owner: String, library: LibraryModel, tvdb: TVDBService = .shared) async {
        guard canLoadEpisodeOrder, library.owner == owner else { return }
        if soloFranchiseEntry {
            orderRequest = UUID(); tvdbOrder = nil; episodeOrderProjection = nil; episodeOrderOptions = []; episodeOrderLoading = false
            applyEpisodeOrder(); return
        }
        let request = UUID(), selected = media
        orderRequest = request; episodeOrderLoading = true
        defer { if orderRequest == request { episodeOrderLoading = false } }
        do {
            var seriesID = animeEpisodeVariants?.tvdbSeriesID
            if seriesID == nil {
                let imdb = selected.imdbID ?? selected.id
                guard imdb.range(of: "^tt[0-9]{7,12}$", options: .regularExpression) != nil else { return }
                let hits = try await tvdb.data(.remote(imdb))
                let ids = Set(hits.array.compactMap { $0["series"]["id"].integer }.filter { $0 > 0 })
                guard ids.count == 1 else { return }
                seriesID = ids.first
            }
            guard let seriesID else { return }
            let options = try await tvdb.orderOptions(series: seriesID)
            let requested = TVDBEpisodeOrderKind(setting: setting) ?? .aired
            guard let effective = options.first(where: { $0.kind == requested })?.kind
                ?? options.first(where: { $0.kind == .aired })?.kind ?? options.first?.kind else { return }
            let order = try await tvdb.episodeOrder(series: seriesID, kind: effective, language: language)
            try Task.checkCancellation()
            guard orderRequest == request, library.owner == owner, media.identity == selected.identity else { return }
            tvdbOrder = order; episodeOrderOptions = options
            applyEpisodeOrder()
        } catch { return } // Keep the available provider list usable during optional metadata failures.
    }

    private func applyEpisodeOrder() {
        guard let variants = animeEpisodeVariants else { return }
        if let pool = episodePool, pool.currentID == media.id {
            var current = media; current.videos = variants.seasons
            episodePool = AnimeEpisodePool(current: current, others: pool.sources.values.filter { $0.id != current.id }.sorted { $0.id < $1.id }, missingEntryIDs: pool.missingEntryIDs)
        }
        let source = episodePool?.episodes ?? variants.seasons
        episodeOrderProjection = tvdbOrder.flatMap { EpisodeOrderProjection.build($0, source: source, animeIdentity: AnimeService.isAnime(media.id)) }
        if let pool = episodePool, let projection = episodeOrderProjection,
           let current = pool.episodes.first(where: { $0.sourceMetaID == media.id }), let source = pool.source(for: current, presentation: projection) {
            media.videos = source.videos
        } else { media.videos = episodeOrderProjection?.videos ?? variants.episodes(animeEpisodeGrouping) }
    }

    func setAnimeEpisodeGrouping(_ grouping: AnimeEpisodeGrouping) {
        guard let variants = animeEpisodeVariants, variants.allowsContinuous else { return }
        animeEpisodeGrouping = grouping
        media.videos = variants.episodes(grouping)
        UserDefaults.standard.set(grouping.rawValue, forKey: AnimeEpisodeGrouping.preferenceKey)
    }

    func findStreams(_ addons: [Addon], episode: Episode? = nil) async {
        let request = UUID(), context = contextRevision()
        streamRequest = request
        loadingStreams = true
        error = nil
        offers = []
        automaticOffers = []
        streamAddons = addons
        warnings = []
        filteredSources = false
        playback = nil
        selectedEpisode = episode
        let selected = sourceMedia(for: episode)
        selectedPlaybackMedia = selected
        defer { if streamRequest == request { loadingStreams = false } }
        do {
            guard let selected else { throw HarborError(code: "no-metadata") }
            let videoID = episode?.id ?? selected.behaviorHints?.defaultVideoId ?? selected.id
            let result = try await service.streams(selected, videoID: videoID, addons: addons, season: episode?.season, episode: episode?.episode, unfiltered: true)
            let automatic = try await service.automaticStreams(result.0, media: selected, season: episode?.season, episode: episode?.episode)
            try Task.checkCancellation()
            guard streamRequest == request, contextRevision() == context else { return }
            offers = result.0
            automaticOffers = StreamPreferences.shared.filter(automatic)
            warnings = result.1
            Diagnostics.shared.record(.streamsLoaded, count: offers.count)
            if offers.isEmpty {
                if !result.0.isEmpty { filteredSources = true; self.error = DesktopInterfaceText.value("Strict filters dropped everything") }
                else { throw HarborError(code: warnings.first ?? "no-streams") }
            }
        } catch is CancellationError { return }
        catch { if streamRequest == request, contextRevision() == context { self.error = safeMessage(error) } }
    }

    func play(_ offer: StreamOffer, resume: ResumeStore, library: LibraryModel) async {
        guard !resolving else { return }
        resolving = true
        let resolution = UUID()
        resolutionRequest = resolution
        let owner = library.owner, context = contextRevision()
        let request = streamRequest
        let episode = selectedEpisode
        let selected = playbackContextMedia
        let continuation = sourceContinuation
        defer { if resolutionRequest == resolution { resolving = false } }
        do {
            let source = try await service.resolve(offer)
            try Task.checkCancellation()
            guard owner == library.owner, contextRevision() == context, request == streamRequest, resolution == resolutionRequest else { return }
            let target = ResumeTarget(id: selected.id, season: episode?.season, episode: episode?.episode, videoId: episode?.id)
            var start = ResumeStart(ms: 0, prompt: false)
            var warning: String?
            let preservedPosition = continuation?.position(for: target, owner: owner)
            let progressEnabled = ["movie", "series", "anime"].contains(selected.type) && !selected.id.hasPrefix("iptv:")
            if let preservedPosition { start = ResumeStart(ms: preservedPosition, prompt: false) }
            else if progressEnabled {
                do {
                    let cloud = await library.resume(for: target)
                    guard owner == library.owner, contextRevision() == context, request == streamRequest, resolution == resolutionRequest else { return }
                    let duration = (episode?.runtime ?? 0) > 0 ? (episode?.runtime ?? 0) * 60_000 : cloud?.durationMs ?? 0
                    start = try await resume.position(target, durationMs: duration, playback: UserDefaults.standard.object(forKey: "resumePlayback") as? Bool ?? true, prompt: UserDefaults.standard.object(forKey: "resumePrompt") as? Bool ?? false, cloud: cloud?.entry)
                } catch {
                    warning = safeMessage(error)
                    Diagnostics.shared.recordFailure(error)
                }
            }
            try Task.checkCancellation()
            guard owner == library.owner, contextRevision() == context, request == streamRequest, resolution == resolutionRequest else { return }
            lastPlayedSource = StreamSourceIdentity(offer)
            sourceContinuation = nil
            playback = PlaybackSession(source: source, target: target, startMs: start.ms, storageWarning: warning, progressEnabled: progressEnabled, owner: owner, resumeStore: resume, preservePosition: preservedPosition != nil, advanceStartedAtMs: preservedPosition == nil ? nil : continuation?.advanceStartedAtMs, promptForResume: start.prompt)
            playback?.media = selected
            playback?.subtitleRequest = SubtitleRequest(media: selected, videoID: episode?.id ?? selected.behaviorHints?.defaultVideoId ?? selected.id, season: episode?.season, episode: episode?.episode, addons: streamAddons, stream: offer.raw)
        }
        catch is CancellationError { return }
        catch { if request == streamRequest, resolution == resolutionRequest, contextRevision() == context { self.error = safeMessage(error) } }
    }

}

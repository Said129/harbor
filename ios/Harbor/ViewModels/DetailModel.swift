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
    /// The whole ranked list. "Prefer these sources" narrows what the picker shows and
    /// automatic selection uses, and can change without asking the addons again.
    private var rankedOffers: [StreamOffer] = []
    private var rankedAutomatic: [StreamOffer] = []
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
    private let pluginStreams: HarborPluginStreamProvider?
    private let debrid: @MainActor () -> DebridClient?
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
    private var extraSources: [String: Media] = [:]
    private var extraRequests: [String: UUID] = [:]
    private(set) var loadingExtraEntries = Set<String>()
    var playbackContextMedia: Media { selectedPlaybackMedia ?? sourceMedia(for: selectedEpisode) ?? media }
    var loadingFranchise = false
    var activeFranchiseEntryID: String?
    private(set) var franchiseSelectionRevision = 0
    var soloFranchiseEntry: Bool { franchise?.scopedSplit == true && activeFranchiseEntryID != nil && activeFranchiseEntryID != franchise?.rootID }
    var episodeOrderScope: String { soloFranchiseEntry ? "solo" : "shared" }
    var canLoadFranchise: Bool { metadataReady && (AnimeLibraryDetection.hasDirectEvidence(media) || animeEpisodeVariants?.kitsuID != nil) }
    var isAnimeOneOff: Bool {
        let count = franchise?.entries.first(where: { $0.id == activeFranchiseEntryID })?.episodeCount
        return metadataReady && AnimeOneOffPresentation.isOneOff(media, knownAnime: animeEpisodeVariants?.kitsuID != nil, declaredEpisodes: count)
    }
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
    var canLoadEpisodeOrder: Bool { animeEpisodesLoaded && !loadingMetadata && media.type != "movie" && media.episodic && !isAnimeOneOff }
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
    private var seasonMetadataRequest = UUID()
    private var loadedSeasonMetadataKey: String?

    func loadSeasonArtworkMetadata(configuration: MetadataConfiguration, owner: String, library: LibraryModel,
        fetch: (@Sendable (Media, MetadataConfiguration) async throws -> Media)? = nil) async {
        let request = UUID(); seasonMetadataRequest = request
        guard metadataReady, owner == library.owner, franchiseChoices.count > 1,
              !configuration.tmdbKey.isEmpty else { return }
        let selected = media, context = contextRevision()
        let imdb = selected.imdbID ?? selected.videos?.compactMap(\.imdbID).first ?? selected.id
        guard imdb.range(of: "^tt[0-9]{7,12}$", options: .regularExpression) != nil else { return }
        let key = selected.identity + "|" + imdb + "|" + configuration.language + "|" + EBookShelf.hash(configuration.tmdbKey)
        guard key != loadedSeasonMetadataKey else { return }
        var lookup = selected; lookup.id = imdb
        do {
            let enriched: Media
            if let fetch { enriched = try await fetch(lookup, configuration) }
            else { enriched = try await TMDBService().detail(lookup, configuration: configuration) }
            try Task.checkCancellation()
            guard seasonMetadataRequest == request, owner == library.owner, contextRevision() == context,
                  media.identity == selected.identity, enriched.id == imdb, let supplied = enriched.details,
                  supplied.overviewLanguage == configuration.language else { return }
            var details = media.details ?? MediaDetails()
            details.overviewLanguage = supplied.overviewLanguage; details.localizedOverview = supplied.localizedOverview
            details.seasonOverviews = supplied.seasonOverviews
            media.details = details; loadedSeasonMetadataKey = key
        } catch { return } // Optional artwork metadata must not delay or prevent playback.
    }

    func prepareSourceChange(_ session: PlaybackSession, snapshot: ResumeSnapshot?) {
        sourceContinuation = snapshot.map { SourceContinuation(target: session.target, owner: session.owner, snapshot: $0, advanceStartedAtMs: session.advanceStartedAtMs ?? session.startMs) }
        playback = nil
    }
    func clearSourceChange() { sourceContinuation = nil }
    func cancelResolution() { resolutionRequest = UUID(); resolving = false }

    init(_ media: Media, service: HarborService, metadataLoaded: Bool = false, contextRevision: @escaping @MainActor () -> UUID = { AppProfileContext.shared.activationID },
        pluginStreams: HarborPluginStreamProvider? = nil, debrid: @escaping @MainActor () -> DebridClient? = { nil }) {
        self.media = media; self.service = service; self.metadataLoaded = metadataLoaded; self.contextRevision = contextRevision
        self.pluginStreams = pluginStreams; self.debrid = debrid
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
            applyEpisodeOrder()
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
            offers = []; automaticOffers = []; rankedOffers = []; rankedAutomatic = []; warnings = []; filteredSources = false; error = nil
            playback = nil; selectedEpisode = nil; lastPlayedSource = nil; sourceContinuation = nil; streamAddons = []
            selectedPlaybackMedia = nil; episodePool = nil; loadedEpisodePoolKey = nil; episodePoolRequest = UUID(); loadingEpisodePool = false
            extraSources = [:]; extraRequests = [:]; loadingExtraEntries = []
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
            if let extra = extraSources[source], extra.videos?.contains(where: { $0.id == episode.id && $0.watchedKey == episode.watchedKey }) == true { return extra }
            if let value = episodePool?.source(for: episode, presentation: episodeOrderProjection) { return value }
            guard source == media.id else { return nil }
        }
        guard media.videos?.contains(where: { $0.id == episode.id && $0.watchedKey == episode.watchedKey }) == true else { return nil }
        return media
    }

    func resolveFranchiseExtra(_ extra: AnimeFranchiseExtra, language: String, owner: String, library: LibraryModel, provider: AnimeFranchiseEpisodeService = .shared) async -> MediaPlaybackSelection? {
        guard owner == library.owner, let entry = franchise?.entries.first(where: { $0.id == extra.entry.id && $0.extra }),
              !loadingExtraEntries.contains(entry.id) else { return nil }
        let request = UUID(), anchor = media.identity, context = contextRevision()
        extraRequests[entry.id] = request; loadingExtraEntries.insert(entry.id)
        defer { if extraRequests[entry.id] == request { extraRequests[entry.id] = nil; loadingExtraEntries.remove(entry.id) } }
        do {
            var source = try await provider.metadata(for: entry, language: language)
            try Task.checkCancellation()
            guard owner == library.owner, contextRevision() == context, media.identity == anchor, extraRequests[entry.id] == request else { return nil }
            let sourceID = source.id
            source.videos = source.videos?.map { episode in var value = episode; value.sourceMetaID = sourceID; return value }
            let episode: Episode?
            if AnimeOneOffPresentation.isOneOff(source, knownAnime: true, declaredEpisodes: entry.episodeCount) {
                if var selected = AnimeOneOffPresentation.playbackEpisode(source) {
                    selected.displaySeason = extra.slot.season; selected.displayEpisode = extra.slot.number
                    source.videos = source.videos?.map { $0.id == selected.id ? selected : $0 }
                    episode = selected
                } else { episode = nil }
            }
            else {
                episode = EpisodeSequence.startingEpisode(source.videos ?? [], record: library.items.first { $0.id == source.id }, watched: library.watchedEpisodes(source))
            }
            extraSources[source.id] = source
            return MediaPlaybackSelection(media: source, episode: episode)
        } catch is CancellationError { return nil }
        catch {
            if !Task.isCancelled, owner == library.owner, contextRevision() == context, media.identity == anchor { self.error = safeMessage(error) }
            return nil
        }
    }

    func loadAnimeEpisodes(owner: String, library: LibraryModel,
        fetch: (@Sendable (Media) async -> AnimeEpisodeVariants)? = nil,
        supplement: (@Sendable (AnimeEpisodeVariants, Media) async -> AnimeEpisodeVariants)? = nil) async {
        guard !animeEpisodesLoaded, !loadingMetadata, media.videos?.isEmpty == false, library.owner == owner else { return }
        if media.type == "movie" {
            let videos = media.videos ?? []
            animeEpisodeVariants = AnimeEpisodeVariants(seasons: videos, continuous: videos)
            animeEpisodesLoaded = true; return
        }
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
        episodeOrderProjection = tvdbOrder.flatMap { EpisodeOrderProjection.build($0, source: source, animeIdentity: AnimeService.isAnime(media.id), currentSourceID: episodePool == nil ? nil : media.id, franchise: franchise?.entries ?? []) }
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

    /// Applies "Prefer these sources" to the listed and the automatic offers. Desktop lets the
    /// picker switch it live; when the favoured kind has nothing, everything stays visible.
    func applyStreamMode() {
        let mode = StreamPreferences.shared.sourceMode
        offers = StreamSourcePolicy.filter(rankedOffers, mode: mode)
        automaticOffers = StreamPreferences.shared.filter(StreamSourcePolicy.filter(rankedAutomatic, mode: mode))
    }

    /// Automatic play for one stream request. `wanted` is asked right before starting, so a
    /// selection that changed meanwhile never plays; `start` resolves and opens the source.
    struct StreamAutoplay {
        let continuation: Bool
        let wanted: @MainActor () -> Bool
        let start: @MainActor (StreamOffer) async -> Void
    }

    /// Requests answered so far for the picker's "addons loading" pill.
    private(set) var answeredRequests = 0
    private(set) var totalRequests = 0
    /// What Desktop's empty and low-count states explain: the streams the addons returned,
    /// the safety filter's rejection reasons and how many debrid services are configured.
    private(set) var receivedStreams = 0
    private(set) var rejectedReasons: [String] = []
    private(set) var debridProviders = 0
    private(set) var pickerFilter = StreamSafetyOverride()
    private var pickerFilterKey: String?
    var pickerStrict: Bool { pickerFilter.level(StreamPreferences.shared.filterLevel) == "strict" }
    /// Desktop's "Search wider": Strict becomes Balanced for this title, then everything is shown.
    func searchWider() { pickerFilter.widen(StreamPreferences.shared.filterLevel) }
    /// Desktop's "Show everything anyway" for this title.
    func showAllSources() { pickerFilter.showAll = true }
    private var autoplay: StreamAutoplay?
    private var autoSettle = StreamAutoSettle(started: .now)
    private var autoTask: Task<Void, Never>?
    /// Offers keep their identity while partial lists replace each other, so a selection
    /// in the picker stays on the same source as more addons answer.
    private var offerIDs: [String: Int] = [:]
    private var nextOfferID = 0

    private static func identity(_ raw: JSONValue) -> String {
        let source: String
        if let hash = raw["infoHash"].string, !hash.isEmpty { source = "hash:" + hash.lowercased() + ":" + (raw["fileIdx"].textValue ?? "") }
        else if let url = raw["url"].string, !url.isEmpty { source = "url:" + url }
        else { source = "name:" + (raw["name"].string ?? "") + ":" + (raw["title"].string ?? "") + ":" + (raw["externalUrl"].string ?? raw["ytId"].string ?? "") }
        return (raw["addonId"].string ?? "") + "|" + source
    }
    private func stable(_ list: [StreamOffer]) -> [StreamOffer] {
        var used = Set<Int>()
        return list.map { offer in
            let key = Self.identity(offer.raw)
            var id: Int
            if let known = offerIDs[key] { id = known } else { id = nextOfferID; nextOfferID += 1; offerIDs[key] = id }
            if !used.insert(id).inserted { id = nextOfferID; nextOfferID += 1; used.insert(id) }
            return StreamOffer(id: id, raw: offer.raw)
        }
    }

    /// Desktop's `use-auto-fire.ts`: starts the automatic source once the list has settled,
    /// or at once when every addon has answered. Never while a source is already starting.
    private func considerAutoplay(done: Bool) {
        guard let autoplay, autoTask == nil, !resolving, playback == nil else { return }
        guard autoplay.wanted() else { self.autoplay = nil; return }
        let preferences = StreamPreferences.shared
        let remembered = autoplay.continuation && preferences.keepSourceNextEpisode ? lastPlayedSource : nil
        let protecting = remembered.map { identity in !automaticOffers.contains { identity.matches($0) } } ?? false
        let candidate = autoplay.continuation ? continuationOffer : preferences.preferred(automaticOffers)
        guard autoSettle.shouldStart(now: .now, top: candidate, candidates: automaticOffers, hasResults: !rankedOffers.isEmpty,
                                     answered: answeredRequests, total: totalRequests, done: done, protecting: protecting),
              let top = candidate else { return }
        self.autoplay = nil
        let start = autoplay.start, wanted = autoplay.wanted
        autoTask = Task { [weak self] in
            var tried: Set<Int> = [top.id]
            await start(top)
            // Desktop's attempt chain (`use-auto-fire.ts`): a source that could not be opened is set aside and the
            // next candidate tried, so one dead link does not leave the person in the picker.
            while let self, !Task.isCancelled, self.playback == nil, self.error != nil, tried.count < Self.autoAttemptLimit, wanted() {
                guard let next = StreamPreferences.shared.preferred(self.automaticOffers.filter { !tried.contains($0.id) }) else { break }
                tried.insert(next.id)
                self.error = nil
                await start(next)
            }
        }
    }
    /// How many sources an automatic start tries before it leaves the choice to the picker.
    static let autoAttemptLimit = 8

    private func tickAutoplay(_ request: UUID) async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled, streamRequest == request, loadingStreams, autoplay != nil else { return }
            considerAutoplay(done: false)
        }
    }

    func findStreams(_ addons: [Addon], episode: Episode? = nil, selection: MediaPlaybackSelection? = nil, autoplay: StreamAutoplay? = nil) async {
        let request = UUID(), context = contextRevision()
        streamRequest = request
        loadingStreams = true
        error = nil
        offers = []
        automaticOffers = []
        rankedOffers = []
        rankedAutomatic = []
        offerIDs = [:]; nextOfferID = 0
        answeredRequests = 0; totalRequests = 0; receivedStreams = 0; rejectedReasons = []
        self.autoplay = autoplay; autoTask = nil
        streamAddons = addons
        warnings = []
        filteredSources = false
        playback = nil
        let episode = selection == nil ? episode : selection?.episode
        selectedEpisode = episode
        // Desktop resets Search wider and Show all for another title, episode or safety level.
        let filterKey = [selection?.key ?? episode?.routingKey ?? media.identity, StreamPreferences.shared.filterLevel].joined(separator: "|")
        if filterKey != pickerFilterKey { pickerFilter = StreamSafetyOverride(); pickerFilterKey = filterKey }
        let selected: Media?
        if let selection {
            let validSource = extraSources[selection.media.id] == selection.media
            let validEpisode = selection.episode.map { selected in selection.media.videos?.contains(where: { $0.id == selected.id && $0.watchedKey == selected.watchedKey }) == true } ?? true
            selected = validSource && validEpisode ? selection.media : nil
        } else { selected = sourceMedia(for: episode) }
        selectedPlaybackMedia = selected
        autoSettle = StreamAutoSettle(started: .now, season: episode?.season, episode: episode?.episode, strongAddon: StreamAutoSettle.strong(addons))
        defer { if streamRequest == request { loadingStreams = false } }
        do {
            guard let selected else { throw HarborError(code: "no-metadata") }
            // Desktop re-evaluates its settle timers; a child tick does the same between
            // answers and is cancelled with this request.
            async let ticking: Void = tickAutoplay(request)
            let videoID = episode?.id ?? selected.behaviorHints?.defaultVideoId ?? selected.id
            let provider = pluginStreams, startingPriority = StreamAddonPriority.pluginStart(addons: addons, settings: StreamPreferences.shared.sourceSettings)
            let plugins: (@Sendable () async throws -> HarborPluginStreamBatch)?
            if let provider { plugins = { try await provider(selected, videoID, episode, startingPriority) } }
            else { plugins = nil }
            let debridClient = debrid(), service = service
            debridProviders = debridClient?.providers.count ?? 0
            // Desktop's picker shows what the safety filter keeps, and automatic play picks from
            // that same list; Search wider and Show all relax it for this title only.
            let level = pickerFilter.level(StreamPreferences.shared.filterLevel)
            // Desktop's trust expects the IMDb-aligned episode when the anime numbering agrees
            // with it (`effSeason`/`effEpisode` in episode-pipeline-input.ts).
            let anime = AnimeService.isAnime(selected.id) || videoID.hasPrefix("kitsu:") || videoID.hasPrefix("mal:")
            let aligned = !anime || episode?.imdbEpisode == nil || episode?.episode == episode?.imdbEpisode
            let expected = (season: aligned ? (episode?.imdbSeason ?? episode?.season) : episode?.season,
                            episode: aligned ? (episode?.imdbEpisode ?? episode?.episode) : episode?.episode)
            // Desktop's automatic start does not check episode numbers for anime ids.
            if selected.id.range(of: "^(kitsu|mal|anilist|anidb):", options: .regularExpression) != nil {
                autoSettle.season = nil; autoSettle.episode = nil
            }
            // Each partial list replaces the previous one, as Desktop's picker does while addons answer.
            let progress: @MainActor @Sendable (HarborService.StreamBatch) async -> Void = { [weak self] batch in
                guard let self, self.streamRequest == request, self.contextRevision() == context, self.loadingStreams else { return }
                self.rankedOffers = self.stable(batch.offers)
                self.rankedAutomatic = self.rankedOffers
                self.answeredRequests = batch.answered; self.totalRequests = batch.total
                self.applyStreamMode()
                self.considerAutoplay(done: false)
            }
            let result = try await service.streamResults(selected, videoID: videoID, addons: addons, season: episode?.season, episode: episode?.episode,
                filterLevel: level, trustEpisode: episode == nil ? nil : expected, pluginSource: plugins, debrid: debridClient, progress: progress)
            try Task.checkCancellation()
            guard streamRequest == request, contextRevision() == context else { return }
            rankedOffers = stable(result.offers)
            rankedAutomatic = rankedOffers
            totalRequests = result.requests; answeredRequests = result.requests
            receivedStreams = result.received
            rejectedReasons = result.rejected
            applyStreamMode()
            warnings = result.errors
            Diagnostics.shared.record(.streamsLoaded, count: offers.count)
            loadingStreams = false
            if offers.isEmpty {
                if result.received > 0 { filteredSources = true; self.error = DesktopInterfaceText.value("Strict filters dropped everything") }
                else { throw HarborError(code: warnings.first ?? "no-streams") }
            }
            considerAutoplay(done: true)
            _ = await ticking
        } catch is CancellationError { autoTask?.cancel(); return }
        catch { if streamRequest == request, contextRevision() == context { self.error = safeMessage(error) } }
        // A source started early keeps this request alive until it has opened or failed.
        if let running = autoTask {
            await withTaskCancellationHandler { await running.value } onCancel: { running.cancel() }
        }
    }

    func play(_ offer: StreamOffer, resume: ResumeStore, library: LibraryModel) async {
        guard !resolving else { return }
        resolving = true
        let resolution = UUID()
        resolutionRequest = resolution
        let owner = library.owner, personalOwner = library.personalOwner, progressStores = library.playbackProgressStores, context = contextRevision()
        let request = streamRequest
        let episode = selectedEpisode
        let selected = playbackContextMedia
        let continuation = sourceContinuation
        defer { if resolutionRequest == resolution { resolving = false } }
        do {
            let source = try await service.resolve(offer, debrid: debrid(), season: episode?.season, episode: episode?.episode)
            try Task.checkCancellation()
            guard owner == library.owner, personalOwner == library.personalOwner, contextRevision() == context, request == streamRequest, resolution == resolutionRequest else { return }
            let target = ResumeTarget(id: selected.id, season: episode?.season, episode: episode?.episode, videoId: episode?.id)
            var start = ResumeStart(ms: 0, prompt: false)
            var warning: String?
            let preservedPosition = continuation?.position(for: target, owner: owner)
            let progressEnabled = ["movie", "series", "anime"].contains(selected.type) && !selected.id.hasPrefix("iptv:")
            if let preservedPosition { start = ResumeStart(ms: preservedPosition, prompt: false) }
            else if progressEnabled {
                do {
                    let cloud = await library.resume(for: target)
                    guard owner == library.owner, personalOwner == library.personalOwner, contextRevision() == context, request == streamRequest, resolution == resolutionRequest else { return }
                    let movieMinutes = selected.runtime.flatMap { value -> Double? in
                        guard let range = value.range(of: "[0-9]+(?:\\.[0-9]+)?", options: .regularExpression) else { return nil }
                        return Double(value[range])
                    } ?? 0
                    let minutes = (episode?.runtime ?? 0) > 0 ? (episode?.runtime ?? 0) : cloud?.entry.pct != nil && selected.type == "movie" ? movieMinutes : 0
                    let duration = minutes > 0 ? minutes * 60_000 : cloud?.durationMs ?? 0
                    start = try await resume.position(target, durationMs: duration, playback: UserDefaults.standard.object(forKey: "resumePlayback") as? Bool ?? true, prompt: UserDefaults.standard.object(forKey: "resumePrompt") as? Bool ?? false, cloud: cloud?.entry, media: selected)
                } catch {
                    warning = safeMessage(error)
                    Diagnostics.shared.recordFailure(error)
                }
            }
            try Task.checkCancellation()
            guard owner == library.owner, personalOwner == library.personalOwner, contextRevision() == context, request == streamRequest, resolution == resolutionRequest else { return }
            lastPlayedSource = StreamSourceIdentity(offer)
            sourceContinuation = nil
            playback = PlaybackSession(source: source, target: target, startMs: start.ms, storageWarning: warning, progressEnabled: progressEnabled, owner: owner, resumeStore: resume, preservePosition: preservedPosition != nil, advanceStartedAtMs: preservedPosition == nil ? nil : continuation?.advanceStartedAtMs, promptForResume: start.prompt)
            playback?.media = selected
            playback?.personalOwner = personalOwner
            playback?.progressStores = progressStores
            playback?.subtitleRequest = SubtitleRequest(media: selected, videoID: episode?.id ?? selected.behaviorHints?.defaultVideoId ?? selected.id, season: episode?.season, episode: episode?.episode, addons: streamAddons, stream: offer.raw)
        }
        catch is CancellationError { return }
        catch { if request == streamRequest, resolution == resolutionRequest, contextRevision() == context { self.error = safeMessage(error) } }
    }

}

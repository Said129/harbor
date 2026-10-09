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
    var warnings: [String] = []
    var filteredSources = false
    var error: String?
    var playback: PlaybackSession?
    var selectedEpisode: Episode?
    private var lastPlayedSource: StreamSourceIdentity?
    var continuationOffer: StreamOffer? {
        StreamPreferences.shared.preferredContinuation(offers, previous: lastPlayedSource)
    }
    private let service: HarborService
    private var streamRequest = UUID()
    private var resolutionRequest = UUID()
    private var sourceContinuation: SourceContinuation?

    func prepareSourceChange(_ session: PlaybackSession, snapshot: ResumeSnapshot?) {
        sourceContinuation = snapshot.map { SourceContinuation(target: session.target, owner: session.owner, snapshot: $0, advanceStartedAtMs: session.advanceStartedAtMs ?? session.startMs) }
        playback = nil
    }
    func clearSourceChange() { sourceContinuation = nil }
    func cancelResolution() { resolutionRequest = UUID(); resolving = false }

    init(_ media: Media, service: HarborService) { self.media = media; self.service = service }

    func load(_ addons: [Addon], owner: String, library: LibraryModel) async {
        loadingMetadata = true
        defer { loadingMetadata = false }
        do {
            let result = try await service.metadata(media, addons: addons)
            try Task.checkCancellation()
            guard library.owner == owner else { return }
            media = result
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

    func findStreams(_ addons: [Addon], episode: Episode? = nil) async {
        let request = UUID()
        streamRequest = request
        loadingStreams = true
        error = nil
        offers = []
        warnings = []
        filteredSources = false
        playback = nil
        selectedEpisode = episode
        defer { if streamRequest == request { loadingStreams = false } }
        do {
            let videoID = episode?.id ?? media.behaviorHints?.defaultVideoId ?? media.id
            let result = try await service.streams(media, videoID: videoID, addons: addons, season: episode?.season, episode: episode?.episode)
            try Task.checkCancellation()
            guard streamRequest == request else { return }
            offers = StreamPreferences.shared.filter(result.0)
            warnings = result.1
            Diagnostics.shared.record(.streamsLoaded, count: offers.count)
            if offers.isEmpty {
                if !result.0.isEmpty { filteredSources = true; self.error = DesktopInterfaceText.value("Strict filters dropped everything") }
                else { throw HarborError(code: warnings.first ?? "no-streams") }
            }
        } catch is CancellationError { return }
        catch { if streamRequest == request { self.error = safeMessage(error) } }
    }

    func play(_ offer: StreamOffer, resume: ResumeStore, library: LibraryModel) async {
        guard !resolving else { return }
        resolving = true
        let resolution = UUID()
        resolutionRequest = resolution
        let owner = library.owner
        let request = streamRequest
        let episode = selectedEpisode
        let continuation = sourceContinuation
        defer { if resolutionRequest == resolution { resolving = false } }
        do {
            let source = try await service.resolve(offer)
            try Task.checkCancellation()
            guard owner == library.owner, request == streamRequest, resolution == resolutionRequest else { return }
            let target = ResumeTarget(id: media.id, season: episode?.season, episode: episode?.episode, videoId: episode?.id)
            var start = ResumeStart(ms: 0, prompt: false)
            var warning: String?
            let preservedPosition = continuation?.position(for: target, owner: owner)
            let progressEnabled = ["movie", "series", "anime"].contains(media.type) && !media.id.hasPrefix("iptv:")
            if let preservedPosition { start = ResumeStart(ms: preservedPosition, prompt: false) }
            else if progressEnabled {
                do {
                    let cloud = await library.resume(for: target)
                    guard owner == library.owner, request == streamRequest, resolution == resolutionRequest else { return }
                    let duration = (episode?.runtime ?? 0) > 0 ? (episode?.runtime ?? 0) * 60_000 : cloud?.durationMs ?? 0
                    start = try await resume.position(target, durationMs: duration, playback: UserDefaults.standard.object(forKey: "resumePlayback") as? Bool ?? true, prompt: UserDefaults.standard.object(forKey: "resumePrompt") as? Bool ?? false, cloud: cloud?.entry)
                } catch {
                    warning = safeMessage(error)
                    Diagnostics.shared.recordFailure(error)
                }
            }
            try Task.checkCancellation()
            guard owner == library.owner, request == streamRequest, resolution == resolutionRequest else { return }
            lastPlayedSource = StreamSourceIdentity(offer)
            sourceContinuation = nil
            playback = PlaybackSession(source: source, target: target, startMs: start.ms, storageWarning: warning, progressEnabled: progressEnabled, owner: owner, resumeStore: resume, preservePosition: preservedPosition != nil, advanceStartedAtMs: preservedPosition == nil ? nil : continuation?.advanceStartedAtMs, promptForResume: start.prompt)
        }
        catch is CancellationError { return }
        catch { if request == streamRequest, resolution == resolutionRequest { self.error = safeMessage(error) } }
    }

}

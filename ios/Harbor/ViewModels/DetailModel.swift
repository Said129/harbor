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
    var error: String?
    var playback: PlaybackSession?
    var pendingPlayback: PlaybackSession?
    var showResumePrompt = false
    var selectedEpisode: Episode?
    var lastPlayedAddonID: String?
    var lastPlayedBingeGroup: String?
    var continuationOffer: StreamOffer? {
        StreamPreferences.shared.preferred(offers.filter { $0.addonID == lastPlayedAddonID && lastPlayedBingeGroup != nil && $0.bingeGroup == lastPlayedBingeGroup }) ??
            StreamPreferences.shared.preferred(offers.filter { $0.addonID != nil && $0.addonID == lastPlayedAddonID }) ?? StreamPreferences.shared.preferred(offers)
    }
    private let service: HarborService
    private var streamRequest = UUID()
    private var sourceContinuation: SourceContinuation?

    func prepareSourceChange(_ session: PlaybackSession, snapshot: ResumeSnapshot?) {
        sourceContinuation = snapshot.map { SourceContinuation(target: session.target, owner: session.owner, snapshot: $0, advanceStartedAtMs: session.advanceStartedAtMs ?? session.startMs) }
        playback = nil
    }
    func clearSourceChange() { sourceContinuation = nil }

    init(_ media: Media, service: HarborService) { self.media = media; self.service = service }

    func load(_ addons: [Addon]) async {
        loadingMetadata = true
        defer { loadingMetadata = false }
        do { media = try await service.metadata(media, addons: addons) }
        catch is CancellationError { return }
        catch { self.error = safeMessage(error) }
    }

    func findStreams(_ addons: [Addon], episode: Episode? = nil) async {
        let request = UUID()
        streamRequest = request
        loadingStreams = true
        error = nil
        offers = []
        warnings = []
        playback = nil
        pendingPlayback = nil
        showResumePrompt = false
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
                if !result.0.isEmpty { self.error = "Ninguna fuente cumple tus filtros de calidad. Puedes cambiarlos en Ajustes → Reproducción." }
                else { throw HarborError(code: warnings.first ?? "no-streams") }
            }
        } catch is CancellationError { return }
        catch { if streamRequest == request { self.error = safeMessage(error) } }
    }

    func play(_ offer: StreamOffer, resume: ResumeStore, library: LibraryModel) async {
        guard !resolving else { return }
        resolving = true
        let owner = library.owner
        let request = streamRequest
        let episode = selectedEpisode
        let continuation = sourceContinuation
        defer { resolving = false }
        do {
            let source = try await service.resolve(offer)
            try Task.checkCancellation()
            guard owner == library.owner, request == streamRequest else { return }
            let target = ResumeTarget(id: media.id, season: episode?.season, episode: episode?.episode, videoId: episode?.id)
            var start = ResumeStart(ms: 0, prompt: false)
            var warning: String?
            let preservedPosition = continuation?.position(for: target, owner: owner)
            let progressEnabled = ["movie", "series", "anime"].contains(media.type) && !media.id.hasPrefix("iptv:")
            if let preservedPosition { start = ResumeStart(ms: preservedPosition, prompt: false) }
            else if progressEnabled {
                do {
                    let cloud = await library.resume(for: target)
                    guard owner == library.owner, request == streamRequest else { return }
                    let duration = (episode?.runtime ?? 0) > 0 ? (episode?.runtime ?? 0) * 60_000 : cloud?.durationMs ?? 0
                    start = try await resume.position(target, durationMs: duration, playback: UserDefaults.standard.object(forKey: "resumePlayback") as? Bool ?? true, prompt: UserDefaults.standard.object(forKey: "resumePrompt") as? Bool ?? false, cloud: cloud?.entry)
                } catch {
                    warning = safeMessage(error)
                    Diagnostics.shared.recordFailure(error)
                }
            }
            try Task.checkCancellation()
            guard owner == library.owner, request == streamRequest else { return }
            lastPlayedAddonID = offer.addonID
            lastPlayedBingeGroup = offer.bingeGroup
            sourceContinuation = nil
            let session = PlaybackSession(source: source, target: target, startMs: start.ms, storageWarning: warning, progressEnabled: progressEnabled, owner: owner, resumeStore: resume, preservePosition: preservedPosition != nil, advanceStartedAtMs: preservedPosition == nil ? nil : continuation?.advanceStartedAtMs)
            if start.prompt { pendingPlayback = session; showResumePrompt = true }
            else { playback = session }
        }
        catch is CancellationError { return }
        catch { if request == streamRequest { self.error = safeMessage(error) } }
    }

    func chooseResume(_ resume: Bool, owner: String) {
        guard let pending = pendingPlayback else { return }
        guard pending.owner == owner else { pendingPlayback = nil; showResumePrompt = false; return }
        playback = PlaybackSession(source: pending.source, target: pending.target, startMs: resume ? pending.startMs : 0, storageWarning: pending.storageWarning, progressEnabled: pending.progressEnabled, owner: pending.owner, resumeStore: pending.resumeStore, preservePosition: pending.preservePosition, advanceStartedAtMs: pending.advanceStartedAtMs)
        pendingPlayback = nil
        showResumePrompt = false
    }
}

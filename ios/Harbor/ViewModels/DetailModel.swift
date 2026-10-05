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
    private let service: HarborService
    private var streamRequest = UUID()

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
            (offers, warnings) = result
            Diagnostics.shared.record(.streamsLoaded, count: offers.count)
            if offers.isEmpty { throw HarborError(code: warnings.first ?? "no-streams") }
        } catch is CancellationError { return }
        catch { if streamRequest == request { self.error = safeMessage(error) } }
    }

    func play(_ offer: StreamOffer, resume: ResumeStore, library: LibraryModel) async {
        guard !resolving else { return }
        resolving = true
        let owner = library.owner
        defer { resolving = false }
        do {
            let source = try await service.resolve(offer)
            let target = ResumeTarget(id: media.id, season: selectedEpisode?.season, episode: selectedEpisode?.episode, videoId: selectedEpisode?.id)
            var start = ResumeStart(ms: 0, prompt: false)
            var warning: String?
            let progressEnabled = ["movie", "series", "anime"].contains(media.type) && !media.id.hasPrefix("iptv:")
            if progressEnabled {
                do {
                    let cloud = await library.resume(for: target)
                    guard owner == library.owner else { return }
                    let duration = (selectedEpisode?.runtime ?? 0) > 0 ? (selectedEpisode?.runtime ?? 0) * 60_000 : cloud?.durationMs ?? 0
                    start = try await resume.position(target, durationMs: duration, playback: UserDefaults.standard.object(forKey: "resumePlayback") as? Bool ?? true, prompt: UserDefaults.standard.object(forKey: "resumePrompt") as? Bool ?? false, cloud: cloud?.entry)
                } catch {
                    warning = safeMessage(error)
                    Diagnostics.shared.recordFailure(error)
                }
            }
            try Task.checkCancellation()
            guard owner == library.owner else { return }
            let session = PlaybackSession(source: source, target: target, startMs: start.ms, storageWarning: warning, progressEnabled: progressEnabled, owner: owner, resumeStore: resume)
            if start.prompt { pendingPlayback = session; showResumePrompt = true }
            else { playback = session }
        }
        catch is CancellationError { return }
        catch { self.error = safeMessage(error) }
    }

    func chooseResume(_ resume: Bool) {
        guard let pending = pendingPlayback else { return }
        playback = PlaybackSession(source: pending.source, target: pending.target, startMs: resume ? pending.startMs : 0, storageWarning: pending.storageWarning, progressEnabled: pending.progressEnabled, owner: pending.owner, resumeStore: pending.resumeStore)
        pendingPlayback = nil
        showResumePrompt = false
    }
}

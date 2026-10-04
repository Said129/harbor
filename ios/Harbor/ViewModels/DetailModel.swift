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
    var playback: PlaybackSource?
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

    func play(_ offer: StreamOffer) async {
        guard !resolving else { return }
        resolving = true
        defer { resolving = false }
        do {
            let source = try await service.resolve(offer)
            try Task.checkCancellation()
            playback = source
        }
        catch is CancellationError { return }
        catch { self.error = safeMessage(error) }
    }
}

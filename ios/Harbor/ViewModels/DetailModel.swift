import Foundation
import Observation

@MainActor @Observable
final class DetailModel {
    var media: Media
    var loading = false
    var resolving = false
    var offers: [StreamOffer] = []
    var warnings: [String] = []
    var error: String?
    var playback: PlaybackSource?
    var selectedEpisode: Episode?
    private let service: HarborService

    init(_ media: Media, service: HarborService) { self.media = media; self.service = service }

    func load(_ addons: [Addon]) async {
        loading = true
        defer { loading = false }
        do { media = try await service.metadata(media, addons: addons) }
        catch is CancellationError { return }
        catch { self.error = safeMessage(error) }
    }

    func findStreams(_ addons: [Addon], episode: Episode? = nil) async {
        loading = true
        error = nil
        offers = []
        playback = nil
        selectedEpisode = episode
        defer { loading = false }
        do {
            let videoID = episode?.id ?? media.behaviorHints?.defaultVideoId ?? media.id
            (offers, warnings) = try await service.streams(media, videoID: videoID, addons: addons, season: episode?.season, episode: episode?.episode)
            Diagnostics.shared.record(.streamsLoaded, count: offers.count)
            if offers.isEmpty { throw HarborError(code: warnings.first ?? "no-streams") }
        } catch is CancellationError { return }
        catch { self.error = safeMessage(error) }
    }

    func play(_ offer: StreamOffer) async {
        guard !resolving else { return }
        resolving = true
        defer { resolving = false }
        do { playback = try await service.resolve(offer) }
        catch is CancellationError { return }
        catch { self.error = safeMessage(error) }
    }
}

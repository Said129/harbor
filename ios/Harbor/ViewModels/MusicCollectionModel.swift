import Foundation
import Observation

@MainActor @Observable final class MusicCollectionModel {
    private(set) var tracks: [MusicTrack] = []
    private(set) var sources: [String] = []
    private(set) var sourceLabels: [String: String] = [:]
    private(set) var loading = false
    private(set) var failed = false
    @ObservationIgnored private let tools = MusicCollectionTools()
    @ObservationIgnored private var revision = UUID()
    @ObservationIgnored private var sourcesFor: [MusicTrack]?
    func load(_ input: MusicCollectionInput) async {
        let request = UUID(); revision = request; loading = true; failed = false
        defer { if revision == request { loading = false } }
        do {
            let selected = try await tools.filter(input)
            let sourceIDs: [String]; var labels = sourceLabels
            if sourcesFor == input.tracks { sourceIDs = sources }
            else {
                sourceIDs = try await tools.sources(input.tracks); labels = [:]
                for source in sourceIDs { labels[source] = try await tools.label(source) }
            }
            try Task.checkCancellation(); guard revision == request else { return }
            tracks = selected; sources = sourceIDs; sourceLabels = labels; sourcesFor = input.tracks
        } catch is CancellationError { }
        catch { if revision == request { failed = true } }
    }
    func addable(_ candidates: [MusicTrack], to held: [MusicTrack]) async throws -> [MusicTrack] { try await tools.addable(candidates, to: held) }
}

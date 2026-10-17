import Foundation
import Observation

@MainActor @Observable
final class AnimeLibraryDetection {
    private(set) var identifiers = Set<String>()
    @ObservationIgnored private var checked: [String: Date] = [:]
    @ObservationIgnored private var pending: [String: Task<Bool, Never>] = [:]

    static func hasDirectEvidence(_ media: Media) -> Bool {
        if AnimeService.isAnime(media.id) || media.type == "anime" { return true }
        let genres = Set((media.genres ?? []).map { $0.lowercased() })
        if genres.contains("anime") { return true }
        guard genres.contains("animation") else { return false }
        let country = media.country?.split(separator: ",").first?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        let language = media.details?.language?.lowercased() ?? ""
        return ["japan", "jp", "jpn", "日本"].contains(country) || ["ja", "jpn", "japanese"].contains(language)
    }

    func observe(_ media: Media) {
        if Self.hasDirectEvidence(media) { identifiers.insert(media.id) }
    }

    func detect(_ media: Media, mapping: @escaping @Sendable (Media) async -> Bool = { await AnimeEpisodeService.shared.hasAnimeIdentity(for: $0) }) async {
        observe(media)
        guard !identifiers.contains(media.id), media.id.range(of: "^tt[0-9]{7,}$", options: .regularExpression) != nil else { return }
        let animated = media.genres?.contains { ["anime", "animation"].contains($0.lowercased()) } == true
        guard animated || (media.country ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let matched: Bool
        if let task = pending[media.id] { matched = await task.value }
        else {
            guard checked[media.id].map({ $0 > Date() }) != true else { return }
            let task = Task { await mapping(media) }
            pending[media.id] = task
            matched = await task.value
            pending[media.id] = nil
            if checked.count >= 1500, let oldest = checked.min(by: { $0.value < $1.value })?.key { checked[oldest] = nil }
            checked[media.id] = Date().addingTimeInterval(300)
        }
        if matched { identifiers.insert(media.id) }
    }
}

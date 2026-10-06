import CryptoKit
import Foundation

enum LibraryFilter: String, Codable, CaseIterable, Identifiable, Sendable {
    case all, saved, watchlist, watched, favorites, continuing = "continue"
    var id: String { rawValue }
    var title: String { switch self { case .all: "Biblioteca"; case .saved: "Guardados"; case .watchlist: "Mi lista"; case .watched: "Historial"; case .favorites: "Favoritos"; case .continuing: "Continuar" } }
}
enum LibraryKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case all, movie, series
    var id: String { rawValue }
    var title: String { switch self { case .all: "Todo"; case .movie: "Películas"; case .series: "Series" } }
}
enum LibrarySort: String, Codable, CaseIterable, Identifiable, Sendable {
    case recent, title, year
    var id: String { rawValue }
    var title: String { switch self { case .recent: "Recientes"; case .title: "A–Z"; case .year: "Año" } }
}
struct LibraryDisplay: Codable, Sendable {
    var filter = LibraryFilter.all
    var kind = LibraryKind.all
    var sort = LibrarySort.recent
    var grouped = true
    private enum CodingKeys: String, CodingKey { case filter, kind, sort, grouped }
    init() { }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        filter = try values.decodeIfPresent(LibraryFilter.self, forKey: .filter) ?? .all
        kind = try values.decodeIfPresent(LibraryKind.self, forKey: .kind) ?? .all
        sort = try values.decodeIfPresent(LibrarySort.self, forKey: .sort) ?? .recent
        grouped = try values.decodeIfPresent(Bool.self, forKey: .grouped) ?? true
    }
}
struct ContinueDismissal: Codable, Sendable {
    let timestampMs: Double
    let videoID: String?
    let season: Int?
    let episode: Int?
    let progress: Double

    init(_ record: LibraryRecord, now: Date = Date()) {
        timestampMs = max(now.timeIntervalSince1970 * 1_000, record.activityTimestamp)
        videoID = record.raw["state"]["video_id"].string
        season = record.playbackCoordinates.season; episode = record.playbackCoordinates.episode
        progress = record.progress
    }
    func hides(_ record: LibraryRecord) -> Bool {
        guard record.activityTimestamp <= timestampMs else { return false }
        let coordinates = record.playbackCoordinates
        let currentVideo = record.raw["state"]["video_id"].string
        let sameVideo = videoID != nil && videoID == currentVideo
        let sameCoordinates = coordinates.season == season && coordinates.episode == episode
        if (sameVideo || (videoID == nil && sameCoordinates)), record.progress > progress + 0.01 { return false }
        if let videoID, let currentVideo, !videoID.isEmpty, !currentVideo.isEmpty, videoID != currentVideo {
            if let season, let episode, let nextSeason = coordinates.season, let nextEpisode = coordinates.episode {
                return nextSeason < season || (nextSeason == season && nextEpisode <= episode)
            }
            return false
        }
        if !sameCoordinates {
            guard let season, let episode, let nextSeason = coordinates.season, let nextEpisode = coordinates.episode else { return false }
            return nextSeason < season || (nextSeason == season && nextEpisode <= episode)
        }
        return true
    }
    func hasNewPlayback(_ snapshot: ResumeSnapshot) -> Bool {
        snapshot.positionMs.isFinite && snapshot.positionMs >= 0 && Double(snapshot.timestampMs) > timestampMs
    }
    var valid: Bool {
        timestampMs.isFinite && timestampMs >= 0 && progress.isFinite && (0...1).contains(progress)
            && (videoID?.utf8.count ?? 0) <= 4_096 && (season ?? 0) >= 0 && (episode ?? 0) >= 0
    }
}
struct LibraryPresentation: Codable, Sendable {
    var version = 1
    var display = LibraryDisplay()
    var dismissed: [String: ContinueDismissal] = [:]
    var valid: Bool { version == 1 && dismissed.count <= 2_000 && dismissed.allSatisfy { !$0.key.isEmpty && $0.key.utf8.count <= 4_096 && $0.value.valid } }
    static func key(owner: String) -> String {
        "library-presentation-" + SHA256.hash(data: Data(owner.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
enum LibraryListing {
    static func select(_ records: [LibraryRecord], display: LibraryDisplay, query: String) -> [LibraryRecord] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        let candidates = records.compactMap { record -> (record: LibraryRecord, name: String, year: Int, date: Double)? in
            guard let media = record.media, display.kind == .all || media.type == display.kind.rawValue else { return nil }
            let name = media.name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            guard query.isEmpty || name.contains(query) else { return nil }
            var date = 0.0
            if display.sort == .recent {
                switch display.filter {
                case .all, .saved, .watchlist, .favorites: date = LibraryRecord.timestamp(record.raw["_ctime"].string) ?? LibraryRecord.timestamp(record.modified) ?? 0
                case .watched, .continuing: date = record.activityTimestamp
                }
            }
            return (record, name, Int((media.releaseInfo ?? "").prefix(4)) ?? 0, date)
        }
        return candidates.sorted { first, second in
            switch display.sort {
            case .recent: if first.date != second.date { return first.date > second.date }
            case .year: if first.year != second.year { return first.year > second.year }
            case .title: break
            }
            let order = first.name.localizedStandardCompare(second.name)
            return order == .orderedSame ? first.record.id < second.record.id : order == .orderedAscending
        }.map(\.record)
    }
}

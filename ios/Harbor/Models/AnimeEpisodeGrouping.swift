import Foundation

enum AnimeEpisodeGrouping: String, CaseIterable, Sendable {
    case seasons = "aired", continuous = "absolute"
    static let preferenceKey = "tvdbSeasonType"
    static var saved: Self { Self(rawValue: UserDefaults.standard.string(forKey: preferenceKey) ?? "") ?? .seasons }
}

struct AnimeEpisodeVariants: Sendable {
    let seasons: [Episode]
    let continuous: [Episode]
    let tvdbSeriesID: Int?
    let kitsuID: Int?
    let allowsContinuous: Bool
    init(seasons: [Episode], continuous: [Episode], tvdbSeriesID: Int? = nil, kitsuID: Int? = nil) {
        self.seasons = seasons; self.continuous = continuous
        self.tvdbSeriesID = tvdbSeriesID
        self.kitsuID = kitsuID
        allowsContinuous = Self.supportsContinuous(seasons: seasons, continuous: continuous)
    }
    private static func supportsContinuous(seasons: [Episode], continuous: [Episode]) -> Bool {
        let seasonal = seasons.filter { ($0.season ?? 1) > 0 }
        let joined = continuous.filter { ($0.season ?? 1) > 0 }
        guard !seasonal.isEmpty, seasons.map(\.id) == continuous.map(\.id),
              seasons.map(\.watchedKey) == continuous.map(\.watchedKey),
              seasonal.count == joined.count,
              joined.allSatisfy({ $0.displaySeason == 1 && ($0.displayEpisode ?? 0) > 0 }),
              Set(joined.compactMap(\.displayEpisode)) == Set(1...joined.count) else { return false }
        return zip(seasonal, joined).contains { source, projected in
            source.listedSeason != projected.listedSeason || source.listedEpisode != projected.listedEpisode
        }
    }
    func episodes(_ grouping: AnimeEpisodeGrouping) -> [Episode] {
        grouping == .continuous && allowsContinuous ? continuous : seasons
    }
}

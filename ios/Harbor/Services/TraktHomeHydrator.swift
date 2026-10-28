import Foundation

struct TraktHomeHydrator: Sendable {
    typealias TMDB = @Sendable (Media, MetadataConfiguration) async throws -> JSONValue
    typealias Cinemeta = @Sendable (String, String) async throws -> Media?
    private let tmdb: TMDB
    private let cinemeta: Cinemeta
    init(tmdb: @escaping TMDB = { try await TMDBService().traktMetadata($0, configuration: $1) },
         cinemeta: @escaping Cinemeta = { id, kind in
             let value = try await HTTPClient().json("https://v3-cinemeta.strem.io/meta/\(kind)/\(id).json")
             return Media.parse(value["meta"], kind: kind)
         }) { self.tmdb = tmdb; self.cinemeta = cinemeta }

    func hydrate(_ items: [TraktLibraryItem], configuration: MetadataConfiguration) async throws -> [Media] {
        try Task.checkCancellation()
        // Bound metadata fan-out on mobile while retaining the source order.
        return try await withThrowingTaskGroup(of: (Int, Media?).self) { group in
            var next = 0, result = [Int: Media]()
            func enqueue() {
                guard next < items.count else { return }
                let index = next, item = items[index]; next += 1
                group.addTask { (index, try await one(item, configuration: configuration)) }
            }
            for _ in 0..<min(4, items.count) { enqueue() }
            for try await (index, media) in group {
                if let media { result[index] = media }
                try Task.checkCancellation(); enqueue()
            }
            return items.indices.compactMap { result[$0] }
        }
    }
    private func one(_ item: TraktLibraryItem, configuration: MetadataConfiguration) async throws -> Media? {
        guard let skeleton = item.media else { return nil }
        if !configuration.tmdbKey.isEmpty, item.ids.json["tmdb"].integer != nil {
            do {
                let media = Self.enrich(skeleton, raw: try await tmdb(skeleton, configuration))
                try Task.checkCancellation()
                if let poster = media.poster, !poster.isEmpty { return media }
            } catch is CancellationError { throw CancellationError() }
            catch { }
        }
        try Task.checkCancellation()
        if let imdb = item.ids.json["imdb"].string {
            do {
                let media = try await cinemeta(imdb, skeleton.type)
                try Task.checkCancellation()
                if let media, let poster = media.poster, !poster.isEmpty { return media }
            } catch is CancellationError { throw CancellationError() }
            catch { }
        }
        // Desktop excludes unillustrated skeletons from these four rows.
        return nil
    }
    static func enrich(_ skeleton: Media, raw: JSONValue) -> Media {
        var media = skeleton
        func image(_ field: String, size: String) -> String? {
            guard let path = raw[field].string, !path.isEmpty else { return nil }
            return "https://image.tmdb.org/t/p/\(size)\(path)"
        }
        media.poster = image("poster_path", size: "w500"); media.background = image("backdrop_path", size: "w780")
        media.description = raw["overview"].string
        let date = raw[media.type == "movie" ? "release_date" : "first_air_date"].string ?? ""
        media.releaseInfo = date.isEmpty ? nil : String(date.prefix(4))
        media.imdbRating = raw["vote_average"].numericValue.flatMap { $0 > 0 ? String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), $0) : nil }
        media.ratingSource = media.imdbRating == nil ? nil : "TMDB"
        return media
    }
}

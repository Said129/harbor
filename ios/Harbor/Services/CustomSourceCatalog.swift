import Foundation

struct CustomSourceCatalog: Sendable {
    private let http = HTTPClient()
    func page(_ destination: DesktopSourceFolder.Destination, page: Int, configuration: MetadataConfiguration, service: HarborService) async throws -> [Media] {
        guard (1...1_000).contains(page) else { return [] }
        switch destination {
        case .discover(let title, let kind, let parameters):
            guard ["movie", "tv"].contains(kind) else { throw HarborError(code: "custom-source-import") }
            return try await TMDBService().page(.init(id: "custom-source", title: title, kind: kind == "tv" ? "series" : "movie",
                path: "discover/" + kind, parameters: parameters), page: page, configuration: configuration)
        case .collection(_, let id):
            guard page == 1 else { return [] }
            guard let id = Int(id), id > 0 else { throw HarborError(code: "custom-source-import") }
            return try await TMDBService().collection(id, configuration: configuration).parts
        case .traktList(_, let id):
            let response = try await http.traktList(id: id, page: page)
            guard case .array(let rows) = response, rows.count <= 20 else { throw HarborError(code: "custom-source-list") }
            let skeletons = rows.compactMap { row -> (Media, String?)? in
                Self.traktMedia(row).map { ($0, row[row["type"].string ?? ""]["ids"]["imdb"].string) }
            }
            // Match Desktop's TMDB -> Cinemeta fallback, preserving list order.
            return await withTaskGroup(of: (Int, Media?).self, returning: [Media].self) { group in
                for (index, entry) in skeletons.enumerated() {
                    group.addTask {
                        let (original, imdb) = entry
                        var media = original
                        if let enriched = try? await TMDBService().sourceMetadata(media, configuration: configuration), enriched.poster != nil { media = enriched }
                        else if let imdb, imdb.range(of: #"^tt[0-9]+$"#, options: .regularExpression) != nil,
                                let full = try? await service.metadata(Media(id: imdb, type: original.type, name: original.name), addons: []), full.poster != nil { media = full }
                        return (index, Task.isCancelled || media.poster == nil ? nil : media)
                    }
                }
                var results: [(Int, Media)] = []
                for await (index, media) in group { if let media { results.append((index, media)) } }
                return results.sorted { $0.0 < $1.0 }.map(\.1)
            }
        case .catalog: throw HarborError(code: "custom-source-addon")
        }
    }
    static func traktMedia(_ row: JSONValue) -> Media? {
        guard let type = row["type"].string, ["movie", "show"].contains(type) else { return nil }
        let raw = row[type], kind = type == "show" ? "series" : "movie"
        guard let title = raw["title"].string else { return nil }
        let id: String
        if let tmdb = raw["ids"]["tmdb"].integer, tmdb > 0 { id = "tmdb:\(type == "show" ? "tv" : "movie"):\(tmdb)" }
        else if let imdb = raw["ids"]["imdb"].string, imdb.range(of: #"^tt[0-9]+$"#, options: .regularExpression) != nil { id = imdb }
        else { return nil }
        var media = Media(id: id, type: kind, name: title)
        media.releaseInfo = raw["year"].integer.map(String.init)
        return media
    }
}

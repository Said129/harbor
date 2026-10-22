import Foundation

extension HarborReadingPluginManager {
    func resolveMangaAdaptation(_ item: JSONValue, book: EBook, client: EBookAdaptationClient, server: SuwayomiClient?, includeAdult: Bool) async throws -> [MangaBook] {
        let queries = try await client.query("manga-queries", arguments: ["item": item, "book": EBookMetadataMapping.raw(book)]).array.compactMap(\.string)
        let plugins = installed(.manga, includeAdult: includeAdult)
        let sources: [MangaSource]
        if let server {
            do { sources = try await server.sources().filter { includeAdult || !$0.adult } }
            catch is CancellationError { throw CancellationError() }
            catch { sources = [] }
        } else { sources = [] }
        struct Request: Sendable { let query: String; let plugin: HarborInstalledReadingPlugin?; let source: String? }
        let requests = queries.flatMap { query in
            plugins.map { Request(query: query, plugin: $0, source: nil) } + sources.map { Request(query: query, plugin: nil, source: $0.id) }
        }
        var batches: [Int: [MangaBook]] = [:]
        try await withThrowingTaskGroup(of: (Int, [MangaBook]).self) { group in
            var cursor = 0
            func enqueue(_ index: Int) {
                let request = requests[index]
                group.addTask {
                    do {
                        if let plugin = request.plugin { return (index, try await self.mangaBrowse(plugin, query: request.query, offset: 0)) }
                        if let source = request.source, let server { return (index, try await server.browse(source: source, latest: false, query: request.query, page: 1).0) }
                        return (index, [])
                    } catch is CancellationError { throw CancellationError() }
                    catch { return (index, []) }
                }
            }
            while cursor < min(4, requests.count) { enqueue(cursor); cursor += 1 }
            for try await (index, rows) in group {
                try Task.checkCancellation(); batches[index] = rows
                if cursor < requests.count { enqueue(cursor); cursor += 1 }
            }
        }
        let rows = requests.indices.map { batches[$0] ?? [] }
        var known: [String: MangaBook] = [:]
        let raw = rows.map { rows in rows.map { row -> JSONValue in
            known[row.id] = row
            var value: [String: JSONValue] = ["id": .string(row.id), "title": .string(row.title)]
            if let alternate = row.metadata?["altTitle"].string { value["altTitle"] = .string(alternate) }
            return .object(value)
        } }
        let choices = try await client.query("manga-choices", arguments: ["queries": .array(queries.map(JSONValue.string)), "results": .array(raw.map(JSONValue.array))])
        try Task.checkCancellation()
        return choices.array.compactMap { $0["id"].string.flatMap { known[$0] } }
    }
}

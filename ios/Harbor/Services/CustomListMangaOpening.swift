import Foundation

enum CustomListMangaTitle {
    private static let colors: Set<String> = ["color", "colour", "colored", "coloured", "colorized", "colorised"]
    private static let editions: Set<String> = ["official", "full", "complete", "digital", "webtoon", "version", "ver", "volume", "vol", "edition"]
    static func key(_ title: String) -> String {
        let expression = try! NSRegularExpression(pattern: #"[\(\[\{｛【（]\s*([^\)\]\}｝】）]*?)\s*[\)\]\}｝】）]"#)
        let original = title as NSString, stripped = NSMutableString(string: title)
        for match in expression.matches(in: title, range: NSRange(location: 0, length: original.length)).reversed() {
            let words = original.substring(with: match.range(at: 1)).lowercased().components(separatedBy: CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789").inverted).filter { !$0.isEmpty }
            if words.contains(where: colors.contains), words.allSatisfy({ colors.contains($0) || editions.contains($0) || $0.allSatisfy(\.isNumber) }) {
                stripped.replaceCharacters(in: match.range, with: "")
            }
        }
        // Desktop keeps a title made entirely of a color marker instead of
        // allowing an empty key to match an unrelated work.
        let cleaned = (stripped as String).replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+([,;:.!?])", with: "$1", options: .regularExpression)
            .replacingOccurrences(of: "[\\s\\-–—]+$", with: "", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
        let value = cleaned.isEmpty ? title : cleaned
        return value.lowercased().replacingOccurrences(of: "[^\\p{L}\\p{N}]+", with: "", options: .regularExpression)
    }
    static func matches(_ query: String, title: String, alternate: String? = nil) -> Bool {
        let expected = key(query)
        return !expected.isEmpty && ([title] + [alternate].compactMap { $0 }).contains { key($0) == expected }
    }
}

@MainActor enum CustomListMangaOpening {
    static func resolve(_ item: CustomListItem, local: [MangaBook], server: SuwayomiClient?, reading: HarborReadingPluginManager?, includeAdult: Bool) async throws -> MangaBook? {
        let queries = [item.name, item.raw["altTitle"].string].compactMap { $0 }.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !queries.isEmpty else { return nil }
        func matches(_ book: MangaBook) -> Bool {
            queries.contains { CustomListMangaTitle.matches($0, title: book.title, alternate: book.metadata?["altTitle"].string) }
        }
        let plugins = reading?.installed(.manga, includeAdult: includeAdult) ?? []
        var saved = local.first { $0.id == item.id }
        if saved == nil, let plugin = plugins.first(where: { item.id.hasPrefix($0.entry.id + "::") }) {
            let remote = String(item.id.dropFirst(plugin.entry.id.count + 2))
            if !remote.isEmpty { saved = .init(id: item.id, title: item.name, remoteID: remote, sourceID: plugin.entry.id, pluginID: plugin.id) }
        }
        if saved == nil, let server {
            let prefix = server.server.id + ":"
            let remote = item.id.hasPrefix(prefix) ? String(item.id.dropFirst(prefix.count)) : item.id
            if !remote.isEmpty, remote.allSatisfy(\.isNumber) { saved = .init(id: item.id, title: item.name, server: server.server.id, remoteID: remote) }
        }
        if let saved {
            if saved.pluginID != nil, let reading, let detail = try? await reading.mangaDetail(saved), matches(detail) { try Task.checkCancellation(); return detail }
            else if saved.server != nil, let server, saved.server == server.server.id,
                    let detail = try? await server.detail(saved), matches(detail) { try Task.checkCancellation(); return detail }
            else if saved.pluginID == nil, saved.server == nil, matches(saved) { try Task.checkCancellation(); return saved }
        }
        try Task.checkCancellation()
        if let server, let library = try? await server.library() {
            try Task.checkCancellation()
            for query in queries { if let hit = library.first(where: { CustomListMangaTitle.matches(query, title: $0.title, alternate: $0.metadata?["altTitle"].string) }) { return hit } }
        }
        // Query every configured source, then choose an exact title match in
        // source order. A reused numeric ID or a first search hit is not proof.
        let sources: [MangaSource]
        if let server { sources = (try? await server.sources())?.filter { includeAdult || !$0.adult } ?? [] } else { sources = [] }
        try Task.checkCancellation()
        for query in queries {
            struct Request: Sendable { let plugin: HarborInstalledReadingPlugin?; let source: String? }
            let requests = plugins.map { Request(plugin: $0, source: nil) } + sources.map { Request(plugin: nil, source: $0.id) }
            var batches: [Int: [MangaBook]] = [:]
            try await withThrowingTaskGroup(of: (Int, [MangaBook]).self) { group in
                var cursor = 0
                func enqueue(_ index: Int) {
                    let request = requests[index]
                    group.addTask {
                        do {
                            if let plugin = request.plugin, let reading { return (index, try await reading.mangaBrowse(plugin, query: query, offset: 0)) }
                            if let source = request.source, let server { return (index, try await server.browse(source: source, latest: false, query: query, page: 1).0) }
                            return (index, [])
                        } catch is CancellationError { throw CancellationError() }
                        catch { return (index, []) }
                    }
                }
                while cursor < min(4, requests.count) { enqueue(cursor); cursor += 1 }
                for try await (index, books) in group {
                    try Task.checkCancellation(); batches[index] = books
                    if cursor < requests.count { enqueue(cursor); cursor += 1 }
                }
            }
            for index in requests.indices {
                if let hit = batches[index]?.first(where: { CustomListMangaTitle.matches(query, title: $0.title, alternate: $0.metadata?["altTitle"].string) }) { return hit }
            }
        }
        return nil
    }
}

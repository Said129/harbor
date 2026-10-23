import Foundation

extension HarborReadingPluginManager {
    /// Keep readable routes available while independent providers resolve the original Desktop aliases.
    func resolveEBook(_ book: EBook, candidates: [EBook], catalog: @escaping @Sendable (String) async throws -> [EBook] = { title in
        try await EBookService.shared.catalog(query: title, language: "", page: 1).0
    }, onPartial: @escaping @MainActor ([EBook]) async -> Void) async throws -> [EBook] {
        let client = try ebookMetadata()
        let raw = EBookMetadataMapping.raw(book)
        let titles = try await client.query("source-queries", arguments: ["book": raw]).array.compactMap(\.string)
        var known = (book.alternativeSources ?? [book]).filter(\.readable) + candidates.flatMap { $0.alternativeSources ?? [$0] }.filter(\.readable)
        func unique(_ books: [EBook]) -> [EBook] { var seen = Set<String>(); return books.filter { seen.insert($0.id).inserted } }
        known = unique(known)
        func refresh(_ rows: [EBook]) {
            var positions = Dictionary(uniqueKeysWithValues: known.enumerated().map { ($0.element.id, $0.offset) })
            for row in rows {
                guard let index = positions[row.id] else { positions[row.id] = known.count; known.append(row); continue }
                let previous = known[index]
                var fields = EBookMetadataMapping.raw(row).objectValue
                let oldIdentity = previous.metadata?["sourceIdentity"].objectValue ?? [:]
                if !oldIdentity.isEmpty {
                    fields["sourceIdentity"] = .object(oldIdentity.merging(fields["sourceIdentity"]?.objectValue ?? [:], uniquingKeysWith: { _, fresh in fresh }))
                }
                let merged = EBookMetadataMapping.detail(.object(fields), preserving: previous)
                // Keep fresh native routes while retaining rich fields absent from a search row.
                var value = row
                value.title = merged.title; value.authors = merged.authors; value.description = merged.description; value.cover = merged.cover; value.metadata = merged.metadata
                known[index] = value
            }
        }
        func matches() async throws -> [EBook] {
            try Task.checkCancellation()
            return try await client.books("source-matches", arguments: ["book": raw, "candidates": .array(known.map(EBookMetadataMapping.raw))], preserving: known)
        }
        await onPartial(try await matches())
        let providers = installed(.ebook)
        let requests = titles.flatMap { title in providers.map { (title: title, plugin: $0) } }
        try await withThrowingTaskGroup(of: [EBook].self) { group in
            var cursor = 0
            func enqueue(_ index: Int) {
                let request = requests[index]
                group.addTask {
                    do { return try await self.ebookBrowse(request.plugin, query: request.title, offset: 0) }
                    catch is CancellationError { throw CancellationError() }
                    catch { return [] }
                }
            }
            // Gutenberg already hydrates its catalog with bounded concurrency. Query aliases serially.
            group.addTask {
                var found: [EBook] = []
                for title in titles {
                    try Task.checkCancellation()
                    do { found += try await catalog(title) }
                    catch is CancellationError { throw CancellationError() }
                    catch { continue }
                }
                return found
            }
            while cursor < min(3, requests.count) { enqueue(cursor); cursor += 1 }
            for try await rows in group {
                refresh(rows)
                await onPartial(try await matches())
                if cursor < requests.count { enqueue(cursor); cursor += 1 }
            }
        }
        let existing = (book.alternativeSources ?? [book]).filter(\.readable)
        let promising = try await client.books("source-promising", arguments: ["book": raw, "candidates": .array(known.map(EBookMetadataMapping.raw)), "existing": .array(existing.map(EBookMetadataMapping.raw))], preserving: known)
        try await withThrowingTaskGroup(of: EBook.self) { group in
            let hydratable = promising.filter { $0.pluginID != nil }
            var cursor = 0
            func enqueue(_ index: Int) {
                let source = hydratable[index]
                group.addTask {
                    do { return try await self.ebookDetail(source) }
                    catch is CancellationError { throw CancellationError() }
                    catch { return source }
                }
            }
            while cursor < min(4, hydratable.count) { enqueue(cursor); cursor += 1 }
            for try await detail in group {
                known.removeAll { $0.id == detail.id }; known.append(detail)
                if cursor < hydratable.count { enqueue(cursor); cursor += 1 }
            }
        }
        let result = try await matches(); await onPartial(result); return result
    }
}

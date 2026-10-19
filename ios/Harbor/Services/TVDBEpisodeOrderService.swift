import Foundation

extension TVDBService {
    func orderOptions(series: Int) async throws -> [TVDBEpisodeOrderOption] {
        let metadata = try await data(.series(series))
        var advertised = TVDBEpisodeOrderOption.advertised(in: metadata)
        if !advertised.contains(where: { $0.kind == .aired }) { advertised.insert(.init(kind: .aired, label: TVDBEpisodeOrderKind.aired.label), at: 0) }
        let available = await withTaskGroup(of: TVDBEpisodeOrderKind?.self) { group in
            for option in advertised {
                group.addTask {
                    do {
                        let page = try await self.data(.episodes(series: series, order: option.kind.slug, language: nil, page: 0))
                        return page["episodes"].array.isEmpty ? nil : option.kind
                    } catch { return nil }
                }
            }
            var found = Set<TVDBEpisodeOrderKind>()
            for await kind in group { if let kind { found.insert(kind) } }
            return found
        }
        try Task.checkCancellation()
        return advertised.filter { available.contains($0.kind) }
    }

    func episodeOrder(series: Int, kind: TVDBEpisodeOrderKind, language: String?) async throws -> TVDBEpisodeOrder? {
        async let base = orderRows(series: series, slug: "default")
        async let metadata = data(.series(series))
        let canonical = try await base
        let alternative = kind.slug == "default" ? canonical : try await orderRows(series: series, slug: kind.slug)
        guard !alternative.isEmpty else { return nil }
        let lang = TVDBEpisodeOrder.language(language)
        async let english = optionalOrderTranslation(series: series, slug: kind.slug, language: "eng")
        async let translated = optionalOrderTranslation(series: series, slug: kind.slug, language: lang == "eng" ? nil : lang)
        let (seriesData, en, localized) = try await (metadata, english, translated)
        try Task.checkCancellation()
        return TVDBEpisodeOrder.build(seriesID: series, kind: kind, canonical: canonical, alternative: alternative,
                                      series: seriesData, translated: localized, english: en)
    }

    func orderRows(series: Int, slug: String, language: String? = nil) async throws -> [TVDBOrderEpisode] {
        var result: [TVDBOrderEpisode] = [], seen = Set<Int>()
        for page in 0..<20 {
            try Task.checkCancellation()
            let value = try await data(.episodes(series: series, order: slug, language: language, page: page))
            let raw = value["episodes"].array
            let rows = raw.compactMap(TVDBOrderEpisode.init)
            result.append(contentsOf: rows)
            if raw.count < 500 { return result }
            let count = seen.count
            for row in rows { seen.insert(row.id) }
            guard seen.count > count else { throw HarborError(code: "tvdb-response") }
        }
        throw HarborError(code: "tvdb-response")
    }

    private func optionalOrderTranslation(series: Int, slug: String, language: String?) async -> [TVDBOrderEpisode] {
        guard let language else { return [] }
        return (try? await orderRows(series: series, slug: slug, language: language)) ?? []
    }
}

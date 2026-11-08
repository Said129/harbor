import Foundation

/// The public related list of one title by IMDb id (Desktop's `traktRelated` in `src/lib/providers/trakt-related.ts`,
/// `/movies/{id}/related` or `/shows/{id}/related`, 20 rows, unauthenticated).
struct TraktRelatedTarget: Equatable, Sendable {
    let imdbId: String
    let show: Bool

    var valid: Bool { imdbId.range(of: "^tt[0-9]{7,}$", options: .regularExpression) != nil }
    var path: String { "/\(show ? "shows" : "movies")/\(imdbId)/related?extended=full&limit=20" }
}

/// Desktop's Trakt related fallback and its merge in `views/detail.tsx`: the Trakt titles fill in when the primary
/// related source has none. Pure apart from `fetch`, which returns nothing on any error.
enum TraktRelatedTitles {
    /// Desktop's `traktRelated` rows: titles with an IMDb id, the title itself and duplicates left out.
    static func metas(_ value: JSONValue, show: Bool, excluding seedID: String) -> [Media] {
        var seen: Set<String> = [seedID]
        var metas: [Media] = []
        for row in value.array {
            guard let imdb = row["ids"]["imdb"].string, imdb.hasPrefix("tt"),
                  let title = row["title"].string?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty,
                  seen.insert(imdb).inserted else { continue }
            var media = Media(id: imdb, type: show ? "series" : "movie", name: title)
            media.description = row["overview"].string
            media.releaseInfo = row["year"].integer.map { String($0) }
            if let rating = row["rating"].numericValue, rating > 0 { media.imdbRating = String(format: "%.1f", rating) }
            media.genres = row["genres"].array.compactMap(\.string)
            media.poster = firstImage(row["images"]["poster"].array.first?.string)
            media.background = firstImage(row["images"]["fanart"].array.first?.string)
            metas.append(media)
        }
        return metas
    }

    /// Desktop's `merge`: the primary list when it has titles, else the fallback without the titles already taken.
    static func merge(primary: [Media], fallback: [Media], taken: Set<String>) -> [Media] {
        guard primary.isEmpty else { return primary }
        return fallback.filter { !taken.contains($0.id) }
    }

    /// The Trakt titles of one target. Empty for an invalid id, a failed request, or an unreadable answer.
    static func fetch(_ target: TraktRelatedTarget) async -> [Media] {
        guard target.valid, let reply = try? await TraktClient.shared.reply(.related(target)),
              let value = try? reply.value() else { return [] }
        return metas(value, show: target.show, excluding: target.imdbId)
    }

    /// Desktop's `firstImage`: the first artwork URL, with `https://` added to a bare host.
    private static func firstImage(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty else { return nil }
        return raw.hasPrefix("http") ? raw : "https://" + raw
    }
}

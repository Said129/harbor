import Foundation

/// The ratings row of a detail page (Desktop's `views/detail/hero-ratings.tsx`) for the providers that need a key:
/// Rotten Tomatoes and Metacritic from OMDb, and Letterboxd, Trakt, SIMKL, the audience score and MDBList's own score.
enum DetailRatings {
    struct Source: Identifiable, Equatable, Sendable {
        let id: String
        let name: String
    }
    /// The providers in Desktop's ratings matrix, in its order (the MAL source is anime-only and not offered).
    static let sources: [Source] = [
        .init(id: "imdb", name: "IMDb"), .init(id: "tmdb", name: "TMDB"), .init(id: "rt", name: "Rotten Tomatoes"), .init(id: "audience", name: "Audience"),
        .init(id: "metacritic", name: "Metacritic"), .init(id: "letterboxd", name: "Letterboxd"), .init(id: "mdblist", name: "MDBList"),
        .init(id: "trakt", name: "Trakt"), .init(id: "simkl", name: "SIMKL")]

    struct Item: Identifiable, Equatable, Sendable {
        let id: String
        /// Desktop's label, a translation key.
        let label: String
        let value: String
        let link: URL?
    }

    static func rounded(_ value: Double) -> Int { Int((value + 0.5).rounded(.down)) }

    /// Items for the scores at hand, skipping any the person turned off in the ratings matrix.
    /// `simkl` is SIMKL's own community score; it needs no key and is preferred over the copy MDBList carries.
    static func items(omdb: OmdbScores?, mdblist: MdblistScores?, simkl: Double? = nil, imdbID: String?, isShow: Bool, hidden: Set<String>) -> [Item] {
        var items: [Item] = []
        if !hidden.contains("rt"), let critics = omdb?.rtCritics {
            items.append(Item(id: "rt", label: "Rotten Tomatoes Critics", value: "\(critics)%", link: nil))
        }
        if !hidden.contains("audience"), let audience = mdblist?.rtAudience {
            items.append(Item(id: "audience", label: "Rotten Tomatoes Audience", value: "\(rounded(audience))%", link: nil))
        }
        if !hidden.contains("letterboxd"), let average = mdblist?.letterboxd {
            items.append(Item(id: "letterboxd", label: "Letterboxd", value: String(format: "%.1f", average), link: imdbID.flatMap { URL(string: "https://letterboxd.com/imdb/\($0)/") }))
        }
        if !hidden.contains("metacritic"), let metascore = mdblist?.metacritic.map(rounded) ?? omdb?.metascore {
            items.append(Item(id: "metacritic", label: "Metacritic", value: String(metascore), link: nil))
        }
        if !hidden.contains("trakt"), let trakt = mdblist?.trakt {
            items.append(Item(id: "trakt", label: "Trakt", value: "\(rounded(trakt))%", link: imdbID.flatMap { URL(string: "https://trakt.tv/search/imdb/\($0)") }))
        }
        if !hidden.contains("simkl"), let simkl = simkl ?? mdblist?.simkl {
            items.append(Item(id: "simkl", label: "SIMKL", value: String(format: "%.1f", simkl), link: imdbID.flatMap { URL(string: "https://api.simkl.com/redirect?to=simkl&imdb=\($0)") }))
        }
        if !hidden.contains("mdblist"), let score = mdblist?.score {
            items.append(Item(id: "mdblist", label: "MDBList", value: String(rounded(score)), link: imdbID.flatMap { URL(string: "https://mdblist.com/\(isShow ? "show" : "movie")/\($0)") }))
        }
        return items
    }

    /// The short name printed on a chip, where Desktop prints the provider's logo.
    static func shortName(_ id: String) -> String {
        switch id {
        case "rt": "RT"
        case "audience": "RT Aud."
        case "letterboxd": "Letterboxd"
        case "metacritic": "Metacritic"
        case "trakt": "Trakt"
        case "simkl": "SIMKL"
        case "mdblist": "MDBList"
        case "mal": "MAL"
        default: id
        }
    }

    /// Desktop's `metacriticBand` colour thresholds: 61 and up green, 40 and up amber, otherwise red.
    static func metacriticBand(_ score: Int) -> String { score >= 61 ? "green" : score >= 40 ? "amber" : "red" }
}

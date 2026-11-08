import Foundation

/// One other film that shares crew with the title: Desktop's `SharedCrewFilm` (`src/lib/providers/wikidata-graph.ts`).
struct SharedCrewFilm: Equatable, Sendable {
    let metaId: String
    let name: String
    let shared: Int
    let who: [String]
}

/// Desktop's shared-crew rules: the three-member minimum, the crew line (`views/detail/shared-crew-line.tsx`), the
/// reason label and rank (`views/detail/use-graph-reasons.ts`). Pure. The Wikidata crew query that produces the films
/// is not ported yet, so nothing calls these rules.
enum SharedCrewRules {
    /// Desktop's `SHARED_MIN`: a film needs this many shared crew members.
    static let minimumShared = 3

    static func films(_ films: [SharedCrewFilm]) -> [SharedCrewFilm] {
        films.filter { $0.shared >= minimumShared }
    }

    /// Desktop's crew line text, or nil when no film shares crew. `text` translates a template with `{n}` placeholders.
    static func line(count: Int, text: (String, [String: String]) -> String) -> String? {
        guard count > 0 else { return nil }
        return count == 1 ? text("Shares crew with 1 other film", [:]) : text("Shares crew with {n} other films", ["n": "\(count)"])
    }

    /// Desktop's reason label for a film in the related rails: "Shares {n} crew".
    static func reasonLabel(shared: Int, text: (String, [String: String]) -> String) -> String {
        text("Shares {n} crew", ["n": "\(shared)"])
    }

    /// Desktop's reason rank: crew films rank above every other reason, by how many they share.
    static func rank(shared: Int) -> Int { 100 + shared }

    /// Desktop's `orderByReason`: items sorted by rank, highest first, keeping the original order for equal ranks.
    /// The list stays as it is with fewer than two items or when no item has a rank.
    static func ordered<T>(_ items: [T], id: (T) -> String, ranks: [String: Int]) -> [T] {
        guard items.count > 1, items.contains(where: { ranks[id($0)] != nil }) else { return items }
        return items.enumerated().sorted { a, b in
            let rankA = ranks[id(a.element)] ?? 0, rankB = ranks[id(b.element)] ?? 0
            return rankA != rankB ? rankA > rankB : a.offset < b.offset
        }.map(\.element)
    }
}

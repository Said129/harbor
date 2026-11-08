import Foundation

/// The counts OMDb writes in its `Awards` sentence (Desktop's `OmdbAwards` in `lib/providers/omdb.ts`).
struct OmdbAwards: Codable, Equatable, Sendable {
    var oscarsWon = 0
    var oscarsNominated = 0
    var emmysWon = 0
    var emmysNominated = 0
    var baftasWon = 0
    var baftasNominated = 0
    var globesWon = 0
    var globesNominated = 0
    var totalWins = 0
    var totalNominations = 0
}

enum OmdbAwardsParser {
    /// Desktop's `parseAwards`: reads the lower-cased sentence with one pattern per count. Nil for a missing
    /// sentence, the literal "N/A", or a sentence that names no count at all.
    static func parse(_ text: String?) -> OmdbAwards? {
        guard let text, !text.isEmpty, text != "N/A" else { return nil }
        let lower = text.lowercased()
        func grab(_ pattern: String) -> Int {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: lower, range: NSRange(lower.startIndex..., in: lower)),
                  let range = Range(match.range(at: 1), in: lower) else { return 0 }
            return Int(lower[range]) ?? 0
        }
        var awards = OmdbAwards()
        awards.oscarsWon = grab(#"won\s+([0-9]+)\s+oscar"#)
        awards.oscarsNominated = grab(#"nominated for\s+([0-9]+)\s+oscar"#)
        awards.emmysWon = grab(#"won\s+([0-9]+)\s+(?:primetime\s+)?emmy"#)
        awards.emmysNominated = grab(#"nominated for\s+([0-9]+)\s+(?:primetime\s+)?emmy"#)
        awards.baftasWon = grab(#"won\s+([0-9]+)\s+bafta"#)
        awards.baftasNominated = grab(#"nominated for\s+([0-9]+)\s+bafta"#)
        awards.globesWon = grab(#"won\s+([0-9]+)\s+golden globe"#)
        awards.globesNominated = grab(#"nominated for\s+([0-9]+)\s+golden globe"#)
        awards.totalWins = grab(#"([0-9]+)\s+wins?(?:\s+&|\.|\s|$)"#)
        awards.totalNominations = grab(#"([0-9]+)\s+nominations?"#)
        let counts = [awards.oscarsWon, awards.oscarsNominated, awards.emmysWon, awards.emmysNominated, awards.baftasWon,
                      awards.baftasNominated, awards.globesWon, awards.globesNominated, awards.totalWins, awards.totalNominations]
        return counts.contains { $0 != 0 } ? awards : nil
    }
}

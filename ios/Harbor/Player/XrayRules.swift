import Foundation

/// A person on the X-Ray rail or grid: a cast entry with its character and photo URL (`MediaDetails.Credit.photo`).
struct XrayPerson: Identifiable, Hashable, Sendable {
    let id: Int
    let name: String
    let character: String
    let photo: String?
}

/// What the rail shows. iOS has no face model, so the rail is always the cast list (Desktop's `castFallback`) or a status line.
enum XrayRailState: Equatable, Sendable {
    case cast
    case needsTMDBKey
    case empty
}

/// Pure rules of Desktop's X-Ray overlay (`components/player/xray/*`) without the live face scan.
enum XrayRules {
    /// The stored setting, named as Desktop's `xrayEnabled` (default off).
    static let enabledKey = "xrayEnabled"
    /// The most people the rail and the grid show. The title's cast is loaded at 60 credits, so the list never grows past that.
    static let castLimit = 60

    static func enabled(_ defaults: UserDefaults) -> Bool {
        defaults.object(forKey: enabledKey) as? Bool ?? false
    }

    /// The cast list is shown whenever there is one. Without a cast the status says whether a TMDB key would fill it.
    static func railState(people: [XrayPerson], hasTMDBKey: Bool) -> XrayRailState {
        if !people.isEmpty { return .cast }
        return hasTMDBKey ? .empty : .needsTMDBKey
    }

    /// Keeps the first entry for each person id and drops entries without a name, in the order TMDB gave them.
    static func people(from credits: [MediaDetails.Credit], limit: Int = castLimit) -> [XrayPerson] {
        var seen = Set<Int>()
        var result: [XrayPerson] = []
        for credit in credits {
            guard result.count < limit else { break }
            let name = credit.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, seen.insert(credit.id).inserted else { continue }
            result.append(XrayPerson(id: credit.id, name: name, character: credit.role.trimmingCharacters(in: .whitespacesAndNewlines), photo: credit.photo))
        }
        return result
    }

    /// Desktop's `initials`: the first letter of the first and the last word, or "?" when there is no name.
    static func initials(_ name: String) -> String {
        let words = name.split(whereSeparator: { $0.isWhitespace })
        guard let first = words.first?.first else { return "?" }
        var letters = String(first)
        if words.count > 1, let last = words[words.count - 1].first { letters.append(last) }
        return letters.uppercased()
    }
}

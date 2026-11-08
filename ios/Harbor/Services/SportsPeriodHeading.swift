import Foundation

/// The heading Desktop's score breakdown gives a period (`heading` in `src/views/sports/score-breakdown.tsx`).
enum SportsPeriodHeading: Equatable, Sendable {
    /// A Desktop template whose `{n}` is the period number, such as "Set {n}".
    case template(String, Int)
    /// A Desktop word followed by a number, such as "Overtime" and 1, shown as "Overtime 1".
    case word(String, Int)

    /// `leagueID` is the Harbor league id, which is Desktop's `game.league` for the NCAA basketball league.
    static func heading(group: String, leagueID: String, period n: Int) -> SportsPeriodHeading {
        if ["tennis", "volleyball"].contains(group) { return .template("Set {n}", n) }
        if group == "basketball", ["NCAA", "NCAAB"].contains(leagueID) { return .template("Period {n}", n) }
        if ["basketball", "football"].contains(group) { return n <= 4 ? .template("Quarter {n}", n) : .word("Overtime", n - 4) }
        if group == "hockey", n > 3 { return .word("Overtime", n - 3) }
        if ["baseball", "softball", "cricket"].contains(group) { return .word("Innings", n) }
        return .template("Period {n}", n)
    }

    /// The heading in the person's language, through the Desktop string table.
    var text: String {
        switch self {
        case .template(let key, let n): return DesktopInterfaceText.value(key, variables: ["n": "\(n)"])
        case .word(let key, let n): return DesktopInterfaceText.value(key) + " \(n)"
        }
    }

    static func label(group: String, leagueID: String, period n: Int) -> String {
        heading(group: group, leagueID: leagueID, period: n).text
    }
}

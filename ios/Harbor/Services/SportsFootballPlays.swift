import Foundation

/// Desktop's parseFootballEvents (src/lib/sports/football-situation.ts): the drive plays of an American football game,
/// in game order, shown as the event timeline. Desktop keeps the last 80 plays and uses the scoring plays only when
/// no drive play is published.
enum SportsFootballPlays {
    static func timeline(_ data: JSONValue) -> [SportsTimelineEntry] {
        var plays: [JSONValue] = []
        for drive in data["drives"]["previous"].array {
            plays += drive["plays"].array
        }
        plays += data["drives"]["current"]["plays"].array
        let drivePlays = ordered(plays)
        let source = drivePlays.isEmpty ? ordered(data["scoringPlays"].array) : drivePlays
        return source.suffix(80).map { entry($0) }
    }

    /// Desktop's orderedPlays: plays without text are dropped, a repeated play keeps its newest copy at the first
    /// position, and the rest follow the sequence number, then the period, then the clock (the higher clock first).
    static func ordered(_ input: [JSONValue]) -> [(String, JSONValue)] {
        var order: [String] = []
        var unique: [String: JSONValue] = [:]
        for play in input {
            guard text(play["text"]) != nil || text(play["shortText"]) != nil else { continue }
            let key = identifier(play) ?? fallbackKey(play)
            if unique[key] == nil { order.append(key) }
            unique[key] = play
        }
        let items: [(String, JSONValue)] = order.compactMap { key in
            guard let play = unique[key] else { return nil }
            return (key, play)
        }
        return items.sorted { precedes($0.1, $1.1) }
    }

    /// Desktop's comparator: a sequence number decides when both plays have one, else the period, else the clock.
    static func precedes(_ left: JSONValue, _ right: JSONValue) -> Bool {
        if let leftSequence = sequence(left), let rightSequence = sequence(right) {
            return leftSequence < rightSequence
        }
        let leftPeriod = periodNumber(left) ?? 0
        let rightPeriod = periodNumber(right) ?? 0
        if leftPeriod != rightPeriod { return leftPeriod < rightPeriod }
        if let leftSeconds = clockSeconds(left), let rightSeconds = clockSeconds(right) {
            return leftSeconds > rightSeconds
        }
        return false
    }

    private static func entry(_ item: (String, JSONValue)) -> SportsTimelineEntry {
        let play = item.1
        var periodText = ""
        if let period = periodNumber(play) {
            periodText = period <= 4 ? "Q\(period)" : "OT\(period - 4)"
        }
        let clockText = text(play["clock"]["displayValue"]) ?? ""
        let parts = [periodText, clockText].filter { !$0.isEmpty }
        let body = text(play["text"]) ?? text(play["shortText"]) ?? ""
        var participant: String?
        if let first = play["participants"].array.first {
            participant = text(first["athlete"]["displayName"])
        }
        return SportsTimelineEntry(id: item.0, clock: parts.joined(separator: " \u{00B7} "), kind: .other, text: body, participant: participant)
    }

    private static func text(_ value: JSONValue) -> String? {
        guard let raw = value.string, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return raw
    }

    private static func identifier(_ play: JSONValue) -> String? {
        if let raw = play["id"].string, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return raw }
        return play["id"].integer.map { String($0) }
    }

    private static func fallbackKey(_ play: JSONValue) -> String {
        let period = play["period"]["number"].textValue ?? ""
        let clock = play["clock"]["displayValue"].textValue ?? ""
        let body = play["text"].textValue ?? play["shortText"].textValue ?? ""
        return period + "|" + clock + "|" + body
    }

    private static func periodNumber(_ play: JSONValue) -> Int? {
        guard let period = play["period"]["number"].integer, period >= 1, period <= 20 else { return nil }
        return period
    }

    private static func sequence(_ play: JSONValue) -> Double? {
        guard let raw = play["sequenceNumber"].textValue, let value = Double(raw), value.isFinite else { return nil }
        return value
    }

    /// Desktop's `^(\d+):(\d{2})$` clock, as seconds.
    private static func clockSeconds(_ play: JSONValue) -> Int? {
        guard let clock = play["clock"]["displayValue"].string else { return nil }
        let parts = clock.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2, parts[1].count == 2, parts[0].allSatisfy({ $0.isNumber }), parts[1].allSatisfy({ $0.isNumber }) else { return nil }
        guard let minutes = Int(parts[0]), let seconds = Int(parts[1]) else { return nil }
        return minutes * 60 + seconds
    }
}

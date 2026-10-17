import Foundation

enum MusicSort: String, CaseIterable, Identifiable {
    case original = "default", added, title, artist, album, duration
    var id: String { rawValue }
    var title: String {
        switch self {
        case .original: "Orden de la lista"
        case .added: "Fecha de incorporación"
        case .title: "Título"
        case .artist: "Artista"
        case .album: "Álbum"
        case .duration: "Duración"
        }
    }
}
enum MusicContentFilter: String, CaseIterable, Identifiable {
    case all, clean, explicit
    var id: String { rawValue }
    var title: String {
        switch self { case .all: "Todo"; case .clean: "Sin contenido explícito"; case .explicit: "Contenido explícito" }
    }
}

struct MusicFilters {
    var query = ""
    var source = "all"
    var content = MusicContentFilter.all
    var sort = MusicSort.original
    var descending = false
    var active: Bool { !query.isEmpty || source != "all" || content != .all }
    var canReorder: Bool { !active && sort == .original }
    mutating func reset() { query = ""; source = "all"; content = .all }
    static func source(_ record: MusicRecord) -> String {
        let source = (record.local.track.connectorId ?? String(record.id.split(separator: ":").first ?? "")).lowercased()
        if ["youtube", "youtubemusic", "youtube-music", "youtube_music"].contains(source) { return "youtube" }
        return source == "direct" ? "local" : source
    }
    // Native equivalent of playlist-filters.ts. Sorting affects the listening
    // view only; membership and stored drag order remain unchanged.
    func apply(_ records: [MusicRecord], addedAt: [String: String]? = nil) -> [MusicRecord] {
        let terms = Self.searchKey(String(query.prefix(200))).split(whereSeparator: \.isWhitespace).map(String.init)
        let selected = records.filter { record in
            let track = record.local.track
            if source != "all", Self.source(record) != source { return false }
            if content != .all, track.explicit != (content == .explicit) { return false }
            if terms.isEmpty { return true }
            let text = Self.searchKey(track.title + " " + track.artist + " " + (track.album ?? ""))
            return terms.allSatisfy { text.contains($0) }
        }
        guard sort != .original else { return selected }
        let dates = Dictionary(uniqueKeysWithValues: selected.map { record in
            (record.id, addedAt.map { Self.timestamp($0[record.id]) } ?? record.importedAt.timeIntervalSince1970 * 1000)
        })
        return selected.enumerated().sorted { left, right in
            let a = left.element, b = right.element
            let result: ComparisonResult
            if sort == .added { result = numeric(dates[a.id] ?? 0, dates[b.id] ?? 0, newestFirst: true) }
            else if sort == .duration { result = numeric(Double(a.local.track.durationSeconds), Double(b.local.track.durationSeconds)) }
            else {
                let text: (MusicRecord) -> String = { record in
                    switch sort { case .artist: record.local.track.artist; case .album: record.local.track.album ?? ""; default: record.local.track.title }
                }
                result = textual(text(a), text(b))
            }
            return result == .orderedSame ? left.offset < right.offset : result == .orderedAscending
        }.map(\.element)
    }
    private func numeric(_ a: Double, _ b: Double, newestFirst: Bool = false) -> ComparisonResult {
        // Unknown durations/dates stay at the end in either direction, as Desktop.
        if a <= 0 || b <= 0 { return a <= 0 && b <= 0 ? .orderedSame : a <= 0 ? .orderedDescending : .orderedAscending }
        if a == b { return .orderedSame }
        let ascending = newestFirst ? a > b : a < b
        return ascending != descending ? .orderedAscending : .orderedDescending
    }
    private func textual(_ a: String, _ b: String) -> ComparisonResult {
        if a.isEmpty || b.isEmpty { return a.isEmpty && b.isEmpty ? .orderedSame : a.isEmpty ? .orderedDescending : .orderedAscending }
        let order = a.compare(b, options: [.caseInsensitive, .diacriticInsensitive, .numeric], locale: .current)
        if !descending || order == .orderedSame { return order }
        return order == .orderedAscending ? .orderedDescending : .orderedAscending
    }
    private static func searchKey(_ value: String) -> String {
        String(String.UnicodeScalarView(value.decomposedStringWithCompatibilityMapping.unicodeScalars.filter { !CharacterSet.nonBaseCharacters.contains($0) })).lowercased(with: .current)
    }
    private static func timestamp(_ value: String?) -> Double {
        guard let value else { return 0 }
        if let number = Double(value), number.isFinite { return max(0, number) }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
        return date.map { max(0, $0.timeIntervalSince1970 * 1000) } ?? 0
    }
}

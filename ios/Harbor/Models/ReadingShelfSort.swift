import Foundation

enum ReadingShelfSort: String, CaseIterable, Identifiable {
    case title, recent, author
    var id: String { rawValue }
    var label: String { switch self { case .title: "Título · A–Z"; case .recent: "Leídos recientemente"; case .author: "Autor" } }
    static func matches(_ query: String, title: String, author: String) -> Bool {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return term.isEmpty || (title + " " + author).range(of: term, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }
    func before(title a: String, author aa: String, updated ad: Date, id ai: String, title b: String, author ba: String, updated bd: Date, id bi: String) -> Bool {
        if self == .recent && ad != bd { return ad > bd }
        if self == .author {
            let order = aa.localizedStandardCompare(ba)
            if order != .orderedSame { return order == .orderedAscending }
        }
        let order = a.localizedStandardCompare(b)
        return order == .orderedSame ? ai < bi : order == .orderedAscending
    }
}

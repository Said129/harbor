import Foundation

/// Original language aliases, including distinct Latin American Spanish and
/// Brazilian Portuguese, with the native locale used only for display names.
enum SubtitleLanguages {
    private struct Policy: Decodable, Sendable {
        let iso3: [String: String]
        let names: [String: String]
        let order: [String]
        let latamAliases: [String]
        let latamRegions: [String]
        let brazilAliases: [String]
    }
    private static let policy: Policy? = {
        guard let url = Bundle.main.url(forResource: "SubtitleLanguages", withExtension: "json"),
              let data = try? Data(contentsOf: url), data.count <= 128 * 1024 else { return nil }
        return try? JSONDecoder().decode(Policy.self, from: data)
    }()
    private static let namesToCode: [String: String] = {
        var values = Dictionary(uniqueKeysWithValues: (policy?.names ?? [:]).map { ($0.value.lowercased(), $0.key) })
        values.merge(["jp": "ja", "mandarin": "zh", "cantonese": "zh", "العربية": "ar", "عربي": "ar"]) { _, new in new }
        return values
    }()

    static func normalize(_ input: String) -> String {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !value.isEmpty else { return "" }
        if value == "in" { return "id" }
        if policy?.latamAliases.contains(value) == true { return "es-419" }
        if policy?.brazilAliases.contains(value) == true { return "pt-br" }
        if value.count == 2 { return value }
        if value.count == 3, let code = policy?.iso3[value] { return code }
        if let code = namesToCode[value] { return code }
        let parts = value.split(whereSeparator: { $0 == "-" || $0 == "_" }).map(String.init)
        if parts.count >= 2 {
            let head = parts[0].count == 2 ? parts[0] : policy?.iso3[parts[0]] ?? namesToCode[parts[0]]
            if head == "es", policy?.latamRegions.contains(parts[1]) == true { return "es-419" }
            if head == "pt", parts[1] == "br" { return "pt-br" }
            if let head { return head }
        }
        return value
    }
    static func name(_ input: String) -> String {
        let code = normalize(input)
        guard policy?.names[code] != nil else { return input.uppercased() }
        return Locale.current.localizedString(forLanguageCode: code) ?? policy?.names[code] ?? input.uppercased()
    }
    static var allCodes: [String] { policy?.order ?? [] }
    static func preferenceName(_ input: String) -> String {
        policy?.names[normalize(input)] ?? input
    }
    static func preferredCodes(_ input: String) -> [String] {
        var seen = Set<String>()
        return input.split(separator: ",").map { normalize(String($0)) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }
    static func preferredSecondary(in tracks: [PlayerState.Track], excluding primaryID: Int, languages: String) -> PlayerState.Track? {
        let eligible = tracks.filter { $0.type == "sub" && $0.id != primaryID && !$0.isImageSubtitle }
        for preference in preferredCodes(languages) {
            if let exact = eligible.first(where: { normalize($0.language) == preference }) { return exact }
            let family = preference.split(separator: "-").first
            if let fallback = eligible.first(where: { normalize($0.language).split(separator: "-").first == family }) { return fallback }
        }
        return nil
    }
    static func key(_ track: PlayerState.Track) -> String {
        let language = track.language.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if ["", "und", "unknown", "undetermined"].contains(language) { return track.external ? "__external_unknown__" : "__embedded_unknown__" }
        return normalize(language)
    }
    static func label(_ track: PlayerState.Track) -> String {
        switch key(track) {
        case "__external_unknown__": "Idioma desconocido"
        case "__embedded_unknown__": "Integrados sin idioma"
        default: name(track.language)
        }
    }
}

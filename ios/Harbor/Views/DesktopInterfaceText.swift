import Foundation

enum DesktopInterfaceText {
    private static let spanish: [String: String] = {
        guard let url = Bundle.main.url(forResource: "DesktopInterfaceSpanish", withExtension: "json"), let data = try? Data(contentsOf: url) else { return [:] }
        return (try? JSONDecoder().decode([String: String].self, from: data)) ?? [:]
    }()
    private static let sourceBySpanish = Dictionary(spanish.map { ($0.value, $0.key) }, uniquingKeysWith: { first, _ in first })
    private static let aliases: [String: String] = {
        guard let file = Bundle.main.url(forResource: "NativeInterfaceAliases", withExtension: "json"), let data = try? Data(contentsOf: file) else { return [:] }
        return (try? JSONDecoder().decode([String: String].self, from: data)) ?? [:]
    }()
    private static let bundles: [String: Bundle] = Dictionary(uniqueKeysWithValues: InterfaceLanguage.all.compactMap { language in
        Bundle.main.path(forResource: language.code, ofType: "lproj").flatMap(Bundle.init(path:)).map { (language.code, $0) }
    })
    static func value(_ original: String, site: String? = nil, variables: [String: String] = [:], language: String? = nil) -> String {
        let selected = language.map { Locale(identifier: $0).language.languageCode?.identifier ?? $0 }
        let code = InterfaceLanguage.resolve(selected ?? UserDefaults.standard.string(forKey: "uiLanguage") ?? "es")
        let key = aliases[original] ?? sourceBySpanish[original] ?? original
        let fallback = code == "es" ? spanish[key] ?? original : key
        let text = bundles[code]?.localizedString(forKey: key, value: fallback, table: nil) ?? fallback
        var replacements = variables
        if let site { replacements["site"] = site }
        return interpolate(text, variables: replacements)
    }

    private static let placeholders = try! NSRegularExpression(pattern: #"\{([A-Za-z][A-Za-z0-9_]*)\}"#)
    static func interpolate(_ text: String, variables: [String: String]) -> String {
        guard !variables.isEmpty else { return text }
        let source = text as NSString, result = NSMutableString(string: text)
        // Work on the original ranges once: a value containing braces is text,
        // not another template, including when it contains non-ASCII characters.
        for match in placeholders.matches(in: text, range: NSRange(location: 0, length: source.length)).reversed() {
            if let value = variables[source.substring(with: match.range(at: 1))] { result.replaceCharacters(in: match.range, with: value) }
        }
        return result as String
    }
}

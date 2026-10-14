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
    static func value(_ original: String, site: String? = nil) -> String {
        let code = InterfaceLanguage.resolve(UserDefaults.standard.string(forKey: "uiLanguage") ?? "es")
        let key = aliases[original] ?? sourceBySpanish[original] ?? original
        let fallback = code == "es" ? spanish[key] ?? original : key
        let text = bundles[code]?.localizedString(forKey: key, value: fallback, table: nil) ?? fallback
        return site.map { text.replacingOccurrences(of: "{site}", with: $0) } ?? text
    }
}

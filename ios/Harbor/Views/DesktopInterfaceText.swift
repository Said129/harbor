import Foundation

enum DesktopInterfaceText {
    private static let spanish: [String: String] = {
        guard let url = Bundle.main.url(forResource: "DesktopInterfaceSpanish", withExtension: "json"), let data = try? Data(contentsOf: url) else { return [:] }
        return (try? JSONDecoder().decode([String: String].self, from: data)) ?? [:]
    }()
    static func value(_ original: String, site: String? = nil) -> String {
        let text = spanish[original] ?? original
        return site.map { text.replacingOccurrences(of: "{site}", with: $0) } ?? text
    }
}

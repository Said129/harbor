import Foundation

struct InterfaceLanguage: Decodable, Identifiable, Sendable {
    let code: String
    let nativeLabel: String
    var id: String { code }
    static let all: [InterfaceLanguage] = {
        guard let file = Bundle.main.url(forResource: "DesktopLanguages", withExtension: "json"), let data = try? Data(contentsOf: file),
              let languages = try? JSONDecoder().decode([InterfaceLanguage].self, from: data) else {
            return [InterfaceLanguage(code: "es", nativeLabel: "Español"), InterfaceLanguage(code: "en", nativeLabel: "English")]
        }
        return languages
    }()
    static func resolve(_ raw: String) -> String { all.contains { $0.code == raw } ? raw : "es" }
}

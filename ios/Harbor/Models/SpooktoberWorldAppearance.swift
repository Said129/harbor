import Foundation
import SwiftUI
import UIKit

struct SpooktoberWorldAppearance: Codable, Equatable, Sendable {
    let language: String
    let direction: String
    let css: [String: String]
    let showIMDb: Bool
    let labels: [String: String]
    private static let musicLabels: [String: [String: String]] = {
        guard let file = Bundle.main.url(forResource: "SpooktoberWorldAssets", withExtension: "json"),
              let data = try? Data(contentsOf: file), let asset = try? JSONDecoder().decode(JSONValue.self, from: data) else { return [:] }
        return asset["music_status_labels"].objectValue.mapValues { $0.objectValue.compactMapValues(\.string) }
    }()
    init(palette: [String: [Double]], font: String, language: String, showIMDb: Bool) {
        let code = InterfaceLanguage.resolve(language); self.language = code
        direction = InterfaceLanguage.all.first(where: { $0.code == code })?.rtl == true ? "rtl" : "ltr"
        self.showIMDb = showIMDb
        labels = Self.musicLabels[code] ?? Self.musicLabels["en"] ?? [:]
        var css = [String: String]()
        for (token, channels) in palette {
            guard token.range(of: #"^[a-z][a-z0-9-]{0,63}$"#, options: .regularExpression) != nil,
                  channels.count == 4, channels.allSatisfy({ $0.isFinite && (0...1).contains($0) }) else { continue }
            let values = channels.enumerated().map { index, channel in
                String(format: "%.6f", locale: Locale(identifier: "en_US_POSIX"), index == 3 ? channel : channel * 255)
            }
            css["--color-" + token] = "rgba(" + values.joined(separator: ",") + ")"
        }
        css["--font-sans"] = font == "system" ? "-apple-system,BlinkMacSystemFont,sans-serif" : "'SpookJakarta',sans-serif"
        self.css = css
    }
    @MainActor static func current() -> Self {
        let theme = ThemePreferences.shared
        let keys = Set(theme.palettes.flatMap { $0.tokens.keys }).union(theme.customColors.keys)
        var palette = [String: [Double]]()
        for key in keys {
            var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
            if UIColor(theme.color(key)).getRed(&red, green: &green, blue: &blue, alpha: &alpha) {
                palette[key] = [Double(red), Double(green), Double(blue), Double(alpha)]
            }
        }
        return .init(palette: palette, font: theme.font, language: UserDefaults.standard.string(forKey: "uiLanguage") ?? "es", showIMDb: InterfacePreferences.shared.showImdbBadge)
    }
    var signature: String {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return EBookShelf.hash(String(decoding: (try? encoder.encode(self)) ?? Data(), as: UTF8.self))
    }
}

import SwiftUI
import Observation

struct NativePalette: Decodable, Identifiable {
    let id: String
    let name: String
    let tokens: [String: [Double]]
}

@MainActor @Observable
final class ThemePreferences {
    static let shared = ThemePreferences()
    private let storage = UserDefaults.standard
    let palettes: [NativePalette]
    var preset = UserDefaults.standard.string(forKey: "iphone.theme.preset") ?? "cool-grey" { didSet { storage.set(preset, forKey: "iphone.theme.preset") } }
    var custom = UserDefaults.standard.bool(forKey: "iphone.theme.custom") { didSet { storage.set(custom, forKey: "iphone.theme.custom") } }
    var font = UserDefaults.standard.string(forKey: "iphone.theme.font") ?? "switzer" { didSet { storage.set(font, forKey: "iphone.theme.font") } }
    var seekBarColor = UserDefaults.standard.string(forKey: "seekBarColor") ?? "" { didSet { storage.set(seekBarColor, forKey: "seekBarColor") } }
    var seekColor: Color {
        guard seekBarColor.range(of: "^#[0-9a-fA-F]{6}$", options: .regularExpression) != nil else { return color("accent") }
        return ProfilePreferences.color(String(seekBarColor.dropFirst()))
    }
    func setSeekColor(_ color: Color) {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        guard UIColor(color).getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return }
        seekBarColor = String(format: "#%02x%02x%02x", Int((red * 255).rounded()), Int((green * 255).rounded()), Int((blue * 255).rounded()))
    }
    var customColors: [String: [Double]] = [:] { didSet { if let data = try? JSONEncoder().encode(customColors) { storage.set(data, forKey: "iphone.theme.colors") } } }
    init() {
        struct Document: Decodable { let palettes: [NativePalette] }
        palettes = Bundle.main.url(forResource: "DesktopThemes", withExtension: "json").flatMap { try? Data(contentsOf: $0) }.flatMap { try? JSONDecoder().decode(Document.self, from: $0).palettes } ?? []
        if let data = storage.data(forKey: "iphone.theme.colors"), let colors = try? JSONDecoder().decode([String: [Double]].self, from: data) { customColors = colors }
    }
    func color(_ token: String) -> Color {
        let selected = palettes.first { $0.id == preset } ?? palettes.first
        let values = (custom ? customColors[token] : nil) ?? selected?.tokens[token] ?? [0.1, 0.1, 0.1, 1]
        guard values.count == 4, values.allSatisfy({ $0.isFinite && (0...1).contains($0) }) else { return .gray }
        return Color(.sRGB, red: values[0], green: values[1], blue: values[2], opacity: values[3])
    }
    func set(_ color: Color, token: String) {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        guard UIColor(color).getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return }
        customColors[token] = [Double(red), Double(green), Double(blue), Double(alpha)]
    }
    func reset() { preset = "cool-grey"; custom = false; customColors = [:]; font = "switzer"; seekBarColor = "" }
}

import SwiftUI
import Observation

struct NativePalette: Decodable, Identifiable {
    let id: String
    let name: String
    let tokens: [String: [Double]]
    let swatch: [String]?
}

@MainActor @Observable
final class ThemePreferences {
    static let shared = ThemePreferences()
    private let storage = UserDefaults.standard
    let palettes: [NativePalette]
    var preset = UserDefaults.standard.string(forKey: "iphone.theme.preset") ?? "cool-grey" { didSet { persist(preset, forKey: "iphone.theme.preset") } }
    var custom = UserDefaults.standard.bool(forKey: "iphone.theme.custom") { didSet { persist(custom, forKey: "iphone.theme.custom") } }
    var font = UserDefaults.standard.string(forKey: "iphone.theme.font") ?? "switzer" { didSet { persist(font, forKey: "iphone.theme.font") } }
    var seekBarColor = UserDefaults.standard.string(forKey: "seekBarColor") ?? "" { didSet { persist(seekBarColor, forKey: "seekBarColor") } }
    var seekColor: Color {
        guard seekBarColor.range(of: "^#[0-9a-fA-F]{6}$", options: .regularExpression) != nil else { return color("accent") }
        return ProfilePreferences.color(String(seekBarColor.dropFirst()))
    }
    func setSeekColor(_ color: Color) {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        guard UIColor(color).getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return }
        seekBarColor = String(format: "#%02x%02x%02x", Int((red * 255).rounded()), Int((green * 255).rounded()), Int((blue * 255).rounded()))
    }
    var customColors: [String: [Double]] = [:] { didSet { if let data = try? JSONEncoder().encode(customColors) { persist(data, forKey: "iphone.theme.colors") } } }
    var library = ThemeLibrary.restored(from: UserDefaults.standard.data(forKey: "iphone.theme.library")) { didSet { if let data = try? JSONEncoder().encode(library) { persist(data, forKey: "iphone.theme.library") } } }
    /// File name of the active background inside ThemeBackgroundStore; empty when there is none. Per profile.
    var backgroundFile = UserDefaults.standard.string(forKey: "iphone.theme.backgroundFile") ?? "" { didSet { persist(backgroundFile, forKey: "iphone.theme.backgroundFile") } }
    var hasBackgroundImage: Bool { !backgroundFile.isEmpty }
    var backgroundDim = UserDefaults.standard.object(forKey: "iphone.theme.backgroundDim") as? Double ?? ThemeBackgroundDefaults.dim { didSet { persist(backgroundDim, forKey: "iphone.theme.backgroundDim") } }
    private(set) var backgroundRevision = 0
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
    func customPaletteSeed() -> [String: [Double]] {
        let selected = palettes.first { $0.id == preset } ?? palettes.first
        return (selected?.tokens ?? [:]).merging(customColors) { _, saved in saved }
    }
    /// Applies a saved theme: its colors become the custom palette, and its background (if any) becomes the active one.
    func applyLibraryTheme(_ entry: ThemeLibraryEntry) {
        customColors = entry.tokens
        custom = true
        guard entry.hasBackground, let data = ThemeBackgroundStore.shared.read(ThemeBackgroundStore.name(for: entry.id)) else { return }
        do {
            try activateBackground(data)
            backgroundDim = entry.backgroundDim
        } catch {
            return
        }
    }
    /// Stores JPEG bytes under a new file name, makes them the active background and removes the previous file.
    private func activateBackground(_ jpeg: Data) throws {
        let name = ThemeBackgroundStore.newActiveName()
        try ThemeBackgroundStore.shared.write(jpeg, name: name)
        let previous = backgroundFile
        backgroundFile = name
        if !previous.isEmpty { ThemeBackgroundStore.shared.remove(previous) }
        backgroundRevision += 1
    }
    /// The palette Desktop would save: the custom palette when custom is on, otherwise the selected preset's tokens.
    private func presetTokens() -> [String: [Double]] {
        let selected = palettes.first { $0.id == preset } ?? palettes.first
        return selected?.tokens ?? [:]
    }
    /// Saves the palette currently on screen (preset or custom) with the active background.
    func saveCurrentTheme(named name: String) throws {
        let id = UUID().uuidString
        let background = hasBackgroundImage ? ThemeBackgroundStore.shared.read(backgroundFile) : nil
        let tokens = custom ? customPaletteSeed() : presetTokens()
        let entry = try ThemeLibrary.makeEntry(name: name, tokens: tokens, hasBackground: background != nil, backgroundDim: backgroundDim, id: id)
        if let background { try ThemeBackgroundStore.shared.write(background, name: ThemeBackgroundStore.name(for: id)) }
        library.save(entry)
    }
    /// Stores an imported theme in the library and applies it, as Desktop's import does.
    func importTheme(_ imported: ThemeImport) throws {
        let id = UUID().uuidString
        let stored = imported.background.flatMap { ThemeBackgroundStore.normalizedJPEG($0.imageData) }
        let entry = try ThemeLibrary.makeEntry(name: imported.name, blurb: imported.blurb, tokens: imported.tokens, hasBackground: stored != nil, backgroundDim: imported.background?.dim ?? ThemeBackgroundDefaults.dim, id: id)
        if let stored { try ThemeBackgroundStore.shared.write(stored, name: ThemeBackgroundStore.name(for: id)) }
        library.save(entry)
        applyLibraryTheme(entry)
    }
    func removeLibraryTheme(id: String) {
        ThemeBackgroundStore.shared.remove(ThemeBackgroundStore.name(for: id))
        library.remove(id: id)
    }
    func renameLibraryTheme(id: String, to name: String) throws {
        try library.rename(id: id, to: name)
    }
    /// Normalizes a picked photo and makes it the active background. Returns false when it cannot be stored.
    func setBackgroundImage(from raw: Data) -> Bool {
        guard let jpeg = ThemeBackgroundStore.normalizedJPEG(raw) else { return false }
        do { try activateBackground(jpeg) } catch { return false }
        return true
    }
    func clearBackgroundImage() {
        let previous = backgroundFile
        backgroundFile = ""
        if !previous.isEmpty { ThemeBackgroundStore.shared.remove(previous) }
        backgroundRevision += 1
    }
    func reset() {
        preset = "cool-grey"; custom = false; customColors = [:]; font = "switzer"; seekBarColor = ""
        for key in ["rowCardStyle", "tvCardLogoPos", "posterScale", "posterRadius", "posterEffect", "posterQuality", "posterFocusedCard", "posterBackdropExpansion", "posterDockMagnification", "posterDockTransitionMs", "hidePosterTitles"] { storage.removeObject(forKey: key) }
    }

    private var reloading = false
    private func persist(_ value: Any?, forKey key: String) {
        if !reloading { UserDefaults.standard.set(value, forKey: key) }
    }
    func reloadPreferences() {
        reloading = true; defer { reloading = false }
        preset = UserDefaults.standard.string(forKey: "iphone.theme.preset") ?? "cool-grey"
        custom = UserDefaults.standard.bool(forKey: "iphone.theme.custom")
        font = UserDefaults.standard.string(forKey: "iphone.theme.font") ?? "switzer"
        seekBarColor = UserDefaults.standard.string(forKey: "seekBarColor") ?? ""
        customColors = storage.data(forKey: "iphone.theme.colors").flatMap { try? JSONDecoder().decode([String: [Double]].self, from: $0) } ?? [:]
        library = ThemeLibrary.restored(from: storage.data(forKey: "iphone.theme.library"))
        backgroundFile = UserDefaults.standard.string(forKey: "iphone.theme.backgroundFile") ?? ""
        backgroundDim = UserDefaults.standard.object(forKey: "iphone.theme.backgroundDim") as? Double ?? ThemeBackgroundDefaults.dim
        backgroundRevision += 1
    }
}

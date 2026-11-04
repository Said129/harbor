import SwiftUI
import UIKit

private struct MusicArtworkPaletteKey: EnvironmentKey { static let defaultValue: MusicArtworkPalette? = nil }
extension EnvironmentValues {
    var musicArtworkPalette: MusicArtworkPalette? {
        get { self[MusicArtworkPaletteKey.self] }
        set { self[MusicArtworkPaletteKey.self] = newValue }
    }
}

/// The same relative Oklch lightness/chroma and sRGB mixes as the original CSS.
enum MusicArtworkColourMath {
    static func tone(_ rgb: [Double], light: Bool, text: Bool = false) -> [Double] {
        guard MusicArtworkColour.valid(rgb) else { return [] }
        let linear = rgb.map { value in let n = value / 255; return n <= 0.04045 ? n / 12.92 : pow((n + 0.055) / 1.055, 2.4) }
        let l = cbrt(0.4122214708 * linear[0] + 0.5363325363 * linear[1] + 0.0514459929 * linear[2])
        let m = cbrt(0.2119034982 * linear[0] + 0.6806995451 * linear[1] + 0.1073969566 * linear[2])
        let s = cbrt(0.0883024619 * linear[0] + 0.2817188376 * linear[1] + 0.6299787005 * linear[2])
        let a = 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s
        let b = 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s
        let chroma = hypot(a, b)
        let hue = chroma <= 0.000004 ? 0 : atan2(b, a)
        let limit = text ? (light ? 0.16 : 0.14) : (light ? 0.17 : 0.15)
        let c = text ? min(chroma, limit) : min(limit, max(0.05, chroma))
        let target = text ? (light ? 0.42 : 0.84) : (light ? 0.46 : 0.78)
        let x = c * cos(hue), y = c * sin(hue)
        let lc = pow(target + 0.3963377774 * x + 0.2158037573 * y, 3)
        let mc = pow(target - 0.1055613458 * x - 0.0638541728 * y, 3)
        let sc = pow(target - 0.0894841775 * x - 1.2914855480 * y, 3)
        return [
            4.0767416621 * lc - 3.3077115913 * mc + 0.2309699292 * sc,
            -1.2684380046 * lc + 2.6097574011 * mc - 0.3413193965 * sc,
            -0.0041960863 * lc - 0.7034186147 * mc + 1.7076147010 * sc
        ].map { value in
            let magnitude = abs(value)
            return magnitude <= 0.0031308 ? 12.92 * value : copysign(1.055 * pow(magnitude, 1 / 2.4) - 0.055, value)
        }
    }
    static func mix(_ first: [Double], _ second: [Double], amount: Double) -> [Double] {
        guard first.count == 3, second.count == 3, amount.isFinite else { return [] }
        let weight = min(1, max(0, amount))
        return (0..<3).map { first[$0] * weight + second[$0] * (1 - weight) }
    }
}

@MainActor enum MusicArtworkStyle {
    static func color(_ channels: [Double]) -> Color {
        guard channels.count == 3, channels.allSatisfy(\.isFinite) else { return HarborTheme.accent }
        return Color(.sRGB, red: min(1, max(0, channels[0])), green: min(1, max(0, channels[1])), blue: min(1, max(0, channels[2])))
    }
    static func channels(_ color: Color) -> [Double] {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a) else { return [0, 0, 0] }
        return [Double(r), Double(g), Double(b)]
    }
    static var light: Bool {
        let canvas = channels(HarborTheme.background)
        return canvas[0] * 0.2126 + canvas[1] * 0.7152 + canvas[2] * 0.0722 > 0.5
    }
    static func accent(_ palette: MusicArtworkPalette?) -> Color {
        palette?.dominant.map { color($0.rgb.map { $0 / 255 }) } ?? HarborTheme.ink
    }
    static func spectrum(_ palette: MusicArtworkPalette?) -> Color {
        palette?.dominant.map { color($0.rgb.map { $0 / 255 }) } ?? HarborTheme.accent
    }
    static func ink(_ palette: MusicArtworkPalette?) -> Color {
        palette?.dominant.map { $0.darkInk ? Color(red: 17.0 / 255, green: 17.0 / 255, blue: 17.0 / 255) : .white } ?? HarborTheme.background
    }
    static func tone(_ palette: MusicArtworkPalette?, text: Bool = false) -> Color {
        palette?.dominant.map { color(MusicArtworkColourMath.tone($0.rgb, light: light, text: text)) } ?? HarborTheme.accent
    }
    static func surface(_ palette: MusicArtworkPalette?, expanded: Bool) -> Color {
        guard let rgb = palette?.dominant?.rgb else { return expanded ? HarborTheme.background : HarborTheme.surface }
        let foreground = expanded ? rgb.map { $0 / 255 } : MusicArtworkColourMath.tone(rgb, light: light)
        return color(MusicArtworkColourMath.mix(foreground, channels(HarborTheme.background), amount: expanded ? 0.16 : 0.12))
    }
    static func seek(_ palette: MusicArtworkPalette?) -> Color {
        guard let rgb = palette?.dominant?.rgb else { return HarborTheme.accent }
        return color(MusicArtworkColourMath.mix(MusicArtworkColourMath.tone(rgb, light: light), channels(HarborTheme.ink), amount: 0.55))
    }
}

@MainActor struct MusicPlayButton: View {
    @Bindable var player: MusicPlayback
    let diameter: CGFloat
    @Environment(\.musicArtworkPalette) private var palette
    var body: some View {
        Button { player.togglePause() } label: {
            Group {
                if player.phase == .resolving { ProgressView().tint(MusicArtworkStyle.ink(palette)) }
                else { MusicGlyph(player.paused ? "play" : "pause", size: diameter > 44 ? 28 : 20) }
            }.foregroundStyle(MusicArtworkStyle.ink(palette)).frame(width: diameter, height: diameter)
                .background(MusicArtworkStyle.accent(palette), in: .circle)
        }.buttonStyle(.plain).accessibilityLabel(DesktopInterfaceText.value(player.paused ? "music.play" : "music.pause"))
            .accessibilityIdentifier("music-transport-play")
    }
}

@MainActor struct MusicAppearanceControls: View {
    let preferences: MusicAudioPreferences
    @Environment(\.musicArtworkPalette) private var palette
    var body: some View {
        LazyVGrid(columns: [.init(.adaptive(minimum: 128, maximum: 220))], alignment: .leading, spacing: 8) {
            choice("music.now.colors", icon: "paintpalette", selected: preferences.artworkColors) { preferences.artworkColors.toggle() }
            if MusicAudioMeter.supported {
                choice("music.quality.levels", icon: "waveform", selected: preferences.showLevels) { preferences.showLevels.toggle() }
                choice("music.now.visualizer", icon: "chart.bar", selected: preferences.dockVisualizer) { preferences.dockVisualizer.toggle() }
            }
        }
    }
    private func choice(_ key: String, icon: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(DesktopInterfaceText.value(key), systemImage: icon).font(.caption.weight(selected ? .semibold : .regular))
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(.rect)
        }.buttonStyle(.plain).foregroundStyle(selected ? MusicArtworkStyle.tone(palette, text: true) : .secondary)
            .accessibilityAddTraits(selected ? .isSelected : []).accessibilityIdentifier(key)
    }
}

@MainActor struct MusicArtworkBackground: View {
    var expanded = false
    @Environment(\.musicArtworkPalette) private var palette
    var body: some View {
        if expanded {
            LinearGradient(stops: [.init(color: MusicArtworkStyle.surface(palette, expanded: true), location: 0),
                                   .init(color: HarborTheme.background, location: 0.68)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        } else { MusicArtworkStyle.surface(palette, expanded: false) }
    }
}

@MainActor struct MusicArtworkTheme: ViewModifier {
    let player: MusicPlayback
    @State private var palette: MusicArtworkPalette?
    @State private var loadedKey: String?
    private var enabled: Bool {
        guard let session = player.playbackSession else { return true }
        return session.audio?.artworkColors != false && (try? session.validate()) != nil
    }
    private var key: String {
        let item = player.currentItem
        return EBookShelf.hash([player.owner, String(enabled), item?.id ?? "", item?.track.artwork ?? "",
                               item?.localRecord?.cover ?? "", player.playbackSession?.scope.activation.uuidString ?? "",
                               player.playbackSession?.plex?.credentialVersion.uuidString ?? "",
                               String(ArtworkRefresh.shared.revision)].joined(separator: "|"))
    }
    func body(content: Content) -> some View {
        content.environment(\.musicArtworkPalette, enabled && loadedKey == key ? palette : nil)
            .foregroundStyle(HarborTheme.ink)
            .environment(\.colorScheme, MusicArtworkStyle.light ? .light : .dark)
            .task(id: key) {
                let identity = key, session = player.playbackSession, owner = player.owner
                let scope = session?.scope, version = session?.plex?.credentialVersion
                palette = nil; loadedKey = nil
                guard enabled, let item = player.currentItem else { return }
                do {
                    try session?.validate()
                    let data: Data?
                    if let record = item.localRecord { data = try await MusicFileService.shared.artwork(record, owner: owner) }
                    else if item.track.artwork.hasPrefix("harbor-music-art://"), let plex = session?.plex {
                        data = try await plex.artwork(item.track.artwork)
                    } else if !item.track.artwork.isEmpty { data = try await ArtworkStore.shared.data(item.track.artwork) }
                    else { data = nil }
                    guard let data else { return }
                    let result = try await MusicArtworkColours.shared.palette(data)
                    try Task.checkCancellation(); try session?.validate()
                    guard key == identity, owner == player.owner, scope == player.playbackSession?.scope,
                          version == player.playbackSession?.plex?.credentialVersion else { throw CancellationError() }
                    palette = result; loadedKey = identity
                } catch { }
            }
    }
}

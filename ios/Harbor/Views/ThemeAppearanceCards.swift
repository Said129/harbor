import SwiftUI

struct ThemePaletteCard: View {
    let palette: NativePalette
    let selected: Bool
    let select: () -> Void
    private func swatch(_ index: Int, token: String) -> Color {
        if let colors = palette.swatch, colors.indices.contains(index) { return ProfilePreferences.color(String(colors[index].dropFirst())) }
        let values = palette.tokens[token] ?? [0, 0, 0, 1]
        return Color(.sRGB, red: values[0], green: values[1], blue: values[2], opacity: values[3])
    }
    var body: some View {
        Button(action: select) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Spacer()
                    Circle().fill(swatch(2, token: "ink"))
                        .overlay { if selected { Image("theme-selected").resizable().scaledToFit().frame(width: 14, height: 14).foregroundStyle(swatch(0, token: "canvas")) } }
                        .frame(width: 28, height: 28)
                }
                Spacer(minLength: 16)
                Text(palette.name).font(HarborTheme.font(16.5, weight: .semibold)).foregroundStyle(swatch(2, token: "ink"))
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
            }.padding(16).frame(maxWidth: .infinity, minHeight: 168, alignment: .leading)
                .background { ZStack(alignment: .top) { swatch(0, token: "canvas"); LinearGradient(colors: [swatch(1, token: "raised"), swatch(0, token: "canvas")], startPoint: .top, endPoint: .bottom).frame(height: 68) } }
                .clipShape(.rect(cornerRadius: 10))
                .overlay { RoundedRectangle(cornerRadius: 10).stroke(selected ? HarborTheme.ink : ThemePreferences.shared.color("edge-soft"), lineWidth: 1) }
                .contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel(palette.name).accessibilityAddTraits(selected ? [.isSelected] : [])
            .accessibilityIdentifier("theme-palette-\(palette.id)")
    }
}

struct ThemeFontCard: View {
    let value: String
    let name: String
    let selected: Bool
    let select: () -> Void
    private func specimen(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        switch value {
        case "inter": .custom("Inter-Regular", size: size).weight(weight)
        case "system": .system(size: size, weight: weight)
        default: .custom("SwitzerVariable-Regular", size: size).weight(weight)
        }
    }
    var body: some View {
        Button(action: select) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(name).font(HarborTheme.font(16.5, weight: .semibold))
                    Spacer()
                    if selected { Image("theme-font-selected").resizable().scaledToFit().frame(width: 18, height: 18).foregroundStyle(HarborTheme.accent) }
                }
                Text("Harbor").font(specimen(28, weight: .medium))
                Text(DesktopInterfaceText.value("The quick brown fox jumps over the lazy dog"))
                    .font(specimen(15.5)).foregroundStyle(ThemePreferences.shared.color("ink-muted"))
            }.frame(maxWidth: .infinity, alignment: .leading).padding(20)
                .background(ThemePreferences.shared.color("elevated"), in: .rect(cornerRadius: 10))
                .overlay { RoundedRectangle(cornerRadius: 10).stroke(selected ? HarborTheme.ink : ThemePreferences.shared.color("edge-soft"), lineWidth: 1) }
                .contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityAddTraits(selected ? [.isSelected] : []).accessibilityIdentifier("theme-font-\(value)")
    }
}

import SwiftUI

struct PlayerSeekBarSettings: View {
    @Bindable private var preferences = ThemePreferences.shared
    private let presets = ["", "#ff3b30", "#ff9500", "#ffcc00", "#34c759", "#5ac8fa", "#007aff", "#af52de", "#ff2d92", "#ffffff"]
    var body: some View {
        HarborSettingsSection("Barra de progreso") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Color de la barra").font(HarborTheme.font(14, weight: .medium))
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 44), spacing: 8)], spacing: 8) {
                    ForEach(presets, id: \.self) { hex in
                        Button { withAnimation(.easeInOut(duration: 0.18)) { preferences.seekBarColor = hex } } label: {
                            Circle().fill(hex.isEmpty ? HarborTheme.accent : ProfilePreferences.color(String(hex.dropFirst())))
                                .frame(width: 30, height: 30)
                                .overlay { if preferences.seekBarColor.caseInsensitiveCompare(hex) == .orderedSame { Image("music-check").resizable().scaledToFit().frame(width: 13, height: 13).foregroundStyle(hex == "#ffffff" || hex == "#ffcc00" ? .black : .white) } }
                                .overlay { Circle().stroke(HarborTheme.ink.opacity(preferences.seekBarColor.caseInsensitiveCompare(hex) == .orderedSame ? 0.9 : 0.12), lineWidth: 2) }
                                .frame(width: 44, height: 44).contentShape(Rectangle())
                        }.buttonStyle(.plain).accessibilityLabel(hex.isEmpty ? "Predeterminado" : hex).accessibilityAddTraits(preferences.seekBarColor.caseInsensitiveCompare(hex) == .orderedSame ? [.isSelected] : [])
                    }
                }
                ColorPicker("Personalizado", selection: Binding(get: { preferences.seekColor }, set: { preferences.setSeekColor($0) }), supportsOpacity: false)
                    .font(HarborTheme.font(14)).accessibilityIdentifier("settings-seek-color")
                HarborSeekBar(position: 40, duration: 100, previewOnly: true).accessibilityHidden(true)
                if !preferences.seekBarColor.isEmpty { Button("Restablecer") { preferences.seekBarColor = "" }.font(HarborTheme.font(13)) }
            }
        }
    }
}

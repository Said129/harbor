import SwiftUI

struct ThemeSettingsView: View {
    @Bindable var preferences = ThemePreferences.shared
    @State private var editingColors = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                HarborSettingsSection(DesktopInterfaceText.value("Colors")) {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        ForEach(preferences.palettes) { palette in
                            ThemePaletteCard(palette: palette, selected: preferences.preset == palette.id && !preferences.custom) {
                                preferences.preset = palette.id; preferences.custom = false
                            }
                        }
                        ThemeCustomCard(preferences: preferences) { editingColors = true }
                    }.animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: preferences.preset)
                }
                HarborSettingsSection(DesktopInterfaceText.value("Typography")) {
                    ForEach([("switzer", "Switzer"), ("inter", "Inter"), ("system", "System UI")], id: \.0) { value, name in
                        ThemeFontCard(value: value, name: DesktopInterfaceText.value(name), selected: preferences.font == value) { preferences.font = value }
                    }
                }
                PlayerSeekBarSettings()
                Button { preferences.reset() } label: {
                    Label(DesktopInterfaceText.value("Reset"), image: "audio-reset-sync").font(HarborTheme.font(14, weight: .medium)).frame(minHeight: 44)
                }.buttonStyle(.plain).accessibilityIdentifier("theme-reset")
            }.padding(20)
        }.background(HarborTheme.background).foregroundStyle(HarborTheme.ink)
            .navigationTitle(DesktopInterfaceText.value("Appearance")).navigationBarTitleDisplayMode(.inline).tint(HarborTheme.accent)
            .accessibilityIdentifier("theme-settings-scroll")
            .accessibilityElement(children: .contain).accessibilityValue(preferences.custom ? "custom" : preferences.preset)
            .sheet(isPresented: $editingColors) { CustomPaletteEditor(preferences: preferences) }
    }
}

import SwiftUI

struct ThemeSettingsView: View {
    @Bindable var preferences = ThemePreferences.shared
    var body: some View {
        Form {
            Section("Tipografía") {
                Picker("Fuente de la interfaz", selection: $preferences.font) { Text("Switzer").tag("switzer"); Text("Inter").tag("inter"); Text("Sistema").tag("system") }
                Text("Harbor").font(HarborTheme.font(24, weight: .semibold))
            }
            Section("Paleta de Harbor") {
                ForEach(preferences.palettes) { palette in
                    Button {
                        preferences.preset = palette.id; preferences.custom = false
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 10) {
                                Text(palette.name).foregroundStyle(.primary)
                                HStack(spacing: 5) {
                                    ForEach(["canvas", "surface", "elevated", "accent"], id: \.self) { token in
                                        let rgba = palette.tokens[token] ?? [0, 0, 0, 1]
                                        RoundedRectangle(cornerRadius: 4).fill(Color(.sRGB, red: rgba[0], green: rgba[1], blue: rgba[2])).frame(width: 35, height: 18)
                                    }
                                }
                            }
                            Spacer()
                            if preferences.preset == palette.id && !preferences.custom { Image(systemName: "checkmark").foregroundStyle(HarborTheme.accent) }
                        }.padding(.vertical, 5)
                    }
                }
            }
            Section("Colores personalizados") {
                Toggle("Personalizar colores", isOn: $preferences.custom)
                if preferences.custom {
                    ForEach([("canvas", "Fondo"), ("surface", "Superficies"), ("ink", "Texto"), ("accent", "Acento")], id: \.0) { token, name in
                        ColorPicker(name, selection: Binding(get: { preferences.color(token) }, set: { preferences.set($0, token: token) }), supportsOpacity: false)
                    }
                }
            }
            Section { Button("Restablecer apariencia") { preferences.reset() } }
            Section { PlayerSeekBarSettings() }
        }.navigationTitle("Apariencia").navigationBarTitleDisplayMode(.inline)
            .scrollContentBackground(.hidden).background(HarborTheme.background)
    }
}

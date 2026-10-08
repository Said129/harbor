import SwiftUI

struct CustomPaletteEditor: View {
    let preferences: ThemePreferences
    @Environment(\.dismiss) private var dismiss
    @State private var draft: [String: [Double]]
    @State private var seed: [String: [Double]]
    @State private var original: [String: [Double]]
    @State private var originallyCustom: Bool
    @State private var saved = false
    @State private var started = false
    private let groups: [(String, [(String, String, String)])] = [
        ("Surfaces", [("canvas", "Background", "Page base."), ("surface", "Surface", "Slightly lighter than background."), ("elevated", "Elevated", "Cards, panels."), ("raised", "Raised", "Highlighted blocks.")]),
        ("Text", [("ink", "Text", "Primary copy."), ("ink-muted", "Muted text", "Secondary copy."), ("ink-subtle", "Subtle text", "Captions, eyebrows.")]),
        ("Lines", [("edge", "Border", "Used at 55% / 25% alpha.")]),
        ("Accents", [("accent", "Accent", "Highlight, progress."), ("danger", "Danger", "Errors, destructive.")])
    ]
    init(preferences: ThemePreferences) {
        self.preferences = preferences
        let values = preferences.customPaletteSeed()
        _draft = State(initialValue: values); _seed = State(initialValue: values)
        _original = State(initialValue: preferences.customColors); _originallyCustom = State(initialValue: preferences.custom)
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    ForEach(groups, id: \.0) { group, fields in
                        HarborSettingsSection(DesktopInterfaceText.value(group)) {
                            ForEach(fields, id: \.0) { token, name, hint in
                                HStack(spacing: 16) {
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(DesktopInterfaceText.value(name)).font(HarborTheme.font(14, weight: .semibold))
                                        Text(DesktopInterfaceText.value(hint)).font(HarborTheme.font(13)).foregroundStyle(.secondary)
                                    }.frame(maxWidth: .infinity, alignment: .leading)
                                    ColorPicker(DesktopInterfaceText.value(name), selection: binding(token), supportsOpacity: false).labelsHidden()
                                        .frame(minWidth: 44, minHeight: 44).accessibilityIdentifier("theme-color-\(token)")
                                }.frame(minHeight: 44)
                            }
                        }
                    }
                    Text(DesktopInterfaceText.value("Live preview is on. Save keeps what you've picked as your Custom theme. Reset reverts the editor to the saved palette."))
                        .font(HarborTheme.font(13)).foregroundStyle(.secondary)
                }.padding(20)
            }.background(HarborTheme.background).foregroundStyle(HarborTheme.ink).accessibilityIdentifier("theme-custom-scroll")
                .navigationTitle(DesktopInterfaceText.value("Custom")).navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button(DesktopInterfaceText.value("Cancel")) { dismiss() }.accessibilityIdentifier("theme-custom-cancel") }
                    ToolbarItemGroup(placement: .confirmationAction) {
                        Button { draft = seed } label: { Image("audio-reset-sync").resizable().scaledToFit().frame(width: 18, height: 18).frame(minWidth: 44, minHeight: 44) }
                            .accessibilityLabel(DesktopInterfaceText.value("Reset")).accessibilityIdentifier("theme-custom-reset")
                        Button(DesktopInterfaceText.value("Save")) { saved = true; dismiss() }.accessibilityIdentifier("theme-custom-save")
                    }
                }
        }.tint(HarborTheme.accent)
            .onAppear { if !started { started = true; preview() } }
            .onChange(of: draft) { _, _ in preview() }
            .onDisappear { if !saved { preferences.customColors = original; preferences.custom = originallyCustom } }
    }
    private func preview() { preferences.customColors = draft; preferences.custom = true }
    private func binding(_ token: String) -> Binding<Color> {
        Binding(get: {
            let values = draft[token] ?? [0, 0, 0, 1]
            return Color(.sRGB, red: values[0], green: values[1], blue: values[2], opacity: values[3])
        }, set: { color in
            var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
            guard UIColor(color).getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return }
            let rgb = [Double(red), Double(green), Double(blue)]
            draft[token] = rgb + [1]
            if token == "edge" { draft["edge"] = rgb + [0.55]; draft["edge-soft"] = rgb + [0.25] }
            if token == "accent" { draft["accent-soft"] = rgb + [0.18] }
        })
    }
}

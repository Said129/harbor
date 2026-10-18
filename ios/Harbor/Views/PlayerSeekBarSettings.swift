import SwiftUI

struct PlayerSeekBarSettings: View {
    @Bindable private var preferences = ThemePreferences.shared
    @State private var previewPosition = 55.0
    private let presets = ["", "#ff3b30", "#ff9500", "#ffcc00", "#34c759", "#5ac8fa", "#007aff", "#af52de", "#ff2d92", "#ffffff"]
    var body: some View {
        HarborSettingsSection(DesktopInterfaceText.value("Seek bar")) {
            VStack(alignment: .leading, spacing: 12) {
                Image("seek-preview").resizable().aspectRatio(1599.0 / 254, contentMode: .fit)
                    .overlay(alignment: .bottom) {
                        LinearGradient(colors: [.clear, HarborTheme.background.opacity(0.4), HarborTheme.background], startPoint: .top, endPoint: .bottom)
                            .overlay(alignment: .bottom) {
                                HarborSeekBar(position: previewPosition, duration: 100, seek: { previewPosition = $0 })
                                    .padding(.horizontal, 28).padding(.bottom, 12)
                                    .accessibilityIdentifier("settings-seek-preview")
                            }
                    }.clipShape(.rect(cornerRadius: 10))
                Text(DesktopInterfaceText.value("Bar color")).font(HarborTheme.font(14, weight: .medium))
                Text(DesktopInterfaceText.value("The filled part of the timeline. Default follows your Harbor accent."))
                    .font(HarborTheme.font(13)).foregroundStyle(.secondary)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 44, maximum: 44), spacing: 10)], alignment: .leading, spacing: 10) {
                    ForEach(presets, id: \.self) { hex in
                        Button { withAnimation(.easeInOut(duration: 0.18)) { preferences.seekBarColor = hex } } label: {
                            RoundedRectangle(cornerRadius: 10).fill(hex.isEmpty ? .clear : ProfilePreferences.color(String(hex.dropFirst())))
                                .overlay {
                                    if hex.isEmpty {
                                        Canvas { context, size in
                                            var line = Path(); line.move(to: CGPoint(x: 0, y: size.height)); line.addLine(to: CGPoint(x: size.width, y: 0))
                                            context.stroke(line, with: .color(HarborTheme.ink.opacity(0.25)), lineWidth: 5)
                                        }.clipShape(.rect(cornerRadius: 10))
                                    }
                                }
                                .overlay { RoundedRectangle(cornerRadius: 10).stroke(HarborTheme.ink.opacity(preferences.seekBarColor.caseInsensitiveCompare(hex) == .orderedSame ? 1 : 0.12), lineWidth: 2) }
                                .frame(width: 44, height: 44).contentShape(Rectangle())
                        }.buttonStyle(.plain).accessibilityLabel(hex.isEmpty ? DesktopInterfaceText.value("Default (gold accent)") : hex).accessibilityAddTraits(preferences.seekBarColor.caseInsensitiveCompare(hex) == .orderedSame ? [.isSelected] : [])
                    }
                }
                HStack {
                    ColorPicker(preferences.seekBarColor.isEmpty ? DesktopInterfaceText.value("Custom") : preferences.seekBarColor.uppercased(), selection: Binding(get: { preferences.seekColor }, set: { preferences.setSeekColor($0) }), supportsOpacity: false)
                        .font(HarborTheme.font(14)).frame(minHeight: 44).accessibilityIdentifier("settings-seek-color")
                    Button { preferences.seekBarColor = "" } label: {
                        Label { Text(DesktopInterfaceText.value("Default")) } icon: { Image("seek-color-reset").resizable().scaledToFit().frame(width: 16, height: 16) }
                    }.disabled(preferences.seekBarColor.isEmpty).font(HarborTheme.font(13)).frame(minHeight: 44)
                }
            }
        }
    }
}

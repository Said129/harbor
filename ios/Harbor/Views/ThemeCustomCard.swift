import SwiftUI

struct ThemeCustomCard: View {
    @Bindable var preferences: ThemePreferences
    let edit: () -> Void
    private func color(_ token: String) -> Color {
        let values = preferences.customPaletteSeed()[token] ?? [0, 0, 0, 1]
        return Color(.sRGB, red: values[0], green: values[1], blue: values[2], opacity: values[3])
    }
    var body: some View {
        if preferences.customColors.isEmpty {
            Button(action: edit) {
                VStack(spacing: 8) {
                    Image("desktop-plus").resizable().scaledToFit().frame(width: 20, height: 20)
                        .frame(width: 44, height: 44).background(ThemePreferences.shared.color("raised"), in: .circle)
                    Text(DesktopInterfaceText.value("Custom")).font(HarborTheme.font(16.5, weight: .semibold))
                    Text(DesktopInterfaceText.value("Build your own palette")).font(HarborTheme.font(15.5)).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, minHeight: 168).padding(.horizontal, 12)
                    .background(ThemePreferences.shared.color("elevated"), in: .rect(cornerRadius: 10))
                    .overlay { RoundedRectangle(cornerRadius: 10).stroke(ThemePreferences.shared.color("edge"), style: StrokeStyle(lineWidth: 1, dash: [4])) }
                    .contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityIdentifier("theme-custom")
        } else {
            Button { preferences.custom = true } label: {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Spacer()
                        Circle().fill(color("ink")).overlay {
                            if preferences.custom { Image("theme-selected").resizable().scaledToFit().frame(width: 14, height: 14).foregroundStyle(color("canvas")) }
                        }.frame(width: 28, height: 28)
                    }
                    Spacer(minLength: 16)
                    Text(DesktopInterfaceText.value("Custom")).font(HarborTheme.font(16.5, weight: .semibold)).foregroundStyle(color("ink"))
                }.padding(16).frame(maxWidth: .infinity, minHeight: 168, alignment: .leading)
                    .background { ZStack(alignment: .top) { color("canvas"); LinearGradient(colors: [color("raised"), color("canvas")], startPoint: .top, endPoint: .bottom).frame(height: 68) } }
                    .clipShape(.rect(cornerRadius: 10))
                    .overlay { RoundedRectangle(cornerRadius: 10).stroke(preferences.custom ? HarborTheme.ink : ThemePreferences.shared.color("edge-soft"), lineWidth: 1) }
            }.buttonStyle(.plain).accessibilityLabel(DesktopInterfaceText.value("Apply custom theme"))
                .accessibilityAddTraits(preferences.custom ? [.isSelected] : []).accessibilityIdentifier("theme-custom")
                .overlay(alignment: .bottomTrailing) {
                    Button(action: edit) {
                        Image("theme-edit").resizable().scaledToFit().frame(width: 16, height: 16).frame(width: 44, height: 44)
                            .background(color("elevated"), in: .circle).foregroundStyle(color("ink"))
                            .overlay { Circle().stroke(color("edge"), lineWidth: 1) }
                    }.buttonStyle(.plain).padding(8).accessibilityLabel(DesktopInterfaceText.value("Edit custom theme")).accessibilityIdentifier("theme-custom-edit")
                }
        }
    }
}

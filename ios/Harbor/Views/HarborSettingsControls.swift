import SwiftUI

/// Desktop settings use section headings and open rows, with controls below
/// their labels at narrow widths. Keep that layout instead of iOS Form cells.
struct HarborSettingsSection<Content: View>: View {
    let title: String
    var note: String? = nil
    let content: Content

    init(_ title: String, note: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.note = note
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(DesktopInterfaceText.value(title)).font(HarborTheme.font(20, weight: .semibold))
                .accessibilityAddTraits(.isHeader)
            VStack(alignment: .leading, spacing: 18) { content }
                .frame(maxWidth: .infinity, alignment: .leading)
            if let note {
                Text(DesktopInterfaceText.value(note)).font(HarborTheme.font(13)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct HarborSettingsChoice<Value: Hashable>: View {
    let title: String
    @Binding var selection: Value
    let choices: [(String, Value)]
    var localizeChoices = true
    let identifier: String?
    private var selectedTitle: String {
        choices.first { $0.1 == selection }?.0 ?? String(describing: selection)
    }

    init(_ title: String, selection: Binding<Value>, choices: [(String, Value)], localizeChoices: Bool = true, identifier: String? = nil) {
        self.title = title
        self._selection = selection
        self.choices = choices
        self.localizeChoices = localizeChoices
        self.identifier = identifier
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(DesktopInterfaceText.value(title)).font(HarborTheme.font(14, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
            Menu {
                ForEach(choices.indices, id: \.self) { index in
                    Button { selection = choices[index].1 } label: {
                        if selection == choices[index].1 {
                            Label(choiceTitle(choices[index].0), image: "music-check")
                        } else {
                            Text(choiceTitle(choices[index].0))
                        }
                    }
                }
            } label: {
                HStack(spacing: 12) {
                    Text(choiceTitle(selectedTitle)).font(HarborTheme.font(15, weight: .semibold))
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Image("desktop-chevron-right").resizable().scaledToFit()
                        .frame(width: 16, height: 16).rotationEffect(.degrees(90))
                        .foregroundStyle(.secondary).accessibilityHidden(true)
                }.padding(.horizontal, 14).padding(.vertical, 12).frame(minHeight: 44)
                    .foregroundStyle(HarborTheme.ink)
                    .background(HarborTheme.surface, in: .rect(cornerRadius: 8))
                    .overlay { RoundedRectangle(cornerRadius: 8).stroke(HarborTheme.ink.opacity(0.06), lineWidth: 1) }
                    .contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel(DesktopInterfaceText.value(title)).accessibilityValue(choiceTitle(selectedTitle))
                .accessibilityIdentifier(identifier ?? title)
        }
    }
    private func choiceTitle(_ value: String) -> String { localizeChoices ? DesktopInterfaceText.value(value) : value }
}

struct HarborSettingsToggle: View {
    let title: String
    var note: String? = nil
    @Binding var isOn: Bool

    init(_ title: String, note: String? = nil, isOn: Binding<Bool>) {
        self.title = title
        self.note = note
        self._isOn = isOn
    }

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 5) {
                Text(DesktopInterfaceText.value(title)).font(HarborTheme.font(14, weight: .semibold))
                if let note { Text(DesktopInterfaceText.value(note)).font(HarborTheme.font(13)).foregroundStyle(.secondary) }
            }.fixedSize(horizontal: false, vertical: true)
        }.toggleStyle(HarborSettingsSwitchStyle()).frame(minHeight: 44)
    }
}

private struct HarborSettingsSwitchStyle: ToggleStyle {
    @Environment(\.layoutDirection) private var direction
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            HStack(spacing: 16) {
                configuration.label.frame(maxWidth: .infinity, alignment: .leading)
                Capsule().fill(configuration.isOn ? HarborTheme.ink : ThemePreferences.shared.color("edge"))
                    .overlay(alignment: .leading) {
                        Circle().fill(HarborTheme.background).frame(width: 26, height: 26)
                            .offset(x: direction == .rightToLeft ? (configuration.isOn ? 3 : 19) : (configuration.isOn ? 19 : 3))
                    }.environment(\.layoutDirection, .leftToRight)
                    .frame(width: 48, height: 32).frame(height: 44)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: configuration.isOn)
            }.contentShape(Rectangle()).opacity(enabled ? 1 : 0.6)
        }.buttonStyle(.plain)
            .accessibilityRepresentation {
                Toggle(isOn: configuration.$isOn) { configuration.label }.toggleStyle(.switch)
            }
    }
}

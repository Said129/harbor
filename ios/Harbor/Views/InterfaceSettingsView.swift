import SwiftUI

struct InterfaceSettingsView: View {
    @Bindable var preferences = InterfacePreferences.shared
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                HarborSettingsSection(DesktopInterfaceText.value("Home layout")) {
                    Text(DesktopInterfaceText.value("The shape of the whole Home page. Everything below tunes the rows inside it."))
                        .font(HarborTheme.font(13)).foregroundStyle(.secondary)
                    HomeStylePicker(selection: $preferences.homeMode)
                    NavigationLink { NavigationSettingsView() } label: {
                        HStack {
                            Text(DesktopInterfaceText.value("Navigation items")).font(HarborTheme.font(14, weight: .semibold))
                            Spacer()
                            Image("desktop-chevron-right").resizable().scaledToFit().frame(width: 16, height: 16)
                        }.frame(minHeight: 44).contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityIdentifier("settings-navigation")
                }
                HarborSettingsSection(DesktopInterfaceText.value("Poster cards")) {
                    Text(DesktopInterfaceText.value("Scores")).font(HarborTheme.font(14, weight: .semibold))
                    HarborSettingsToggle("IMDb", isOn: $preferences.showImdbBadge)
                    HarborSettingsToggle("TMDB", isOn: $preferences.showTmdbBadge)
                }
                HarborSettingsSection(DesktopInterfaceText.value("Show pages")) {
                    HarborSettingsToggle(DesktopInterfaceText.value("Mark watched button"), isOn: $preferences.showWatchedButton)
                }
                HarborSettingsSection(DesktopInterfaceText.value("Episode cards")) {
                    HarborSettingsToggle(DesktopInterfaceText.value("Show episode description"), note: DesktopInterfaceText.value("Shows the episode synopsis on the cards. Turn it off to hide it."), isOn: $preferences.showEpisodeDescription)
                }
                HarborSettingsSection(DesktopInterfaceText.value("Spoilers")) {
                    HarborSettingsToggle(DesktopInterfaceText.value("Blur spoilers"), note: DesktopInterfaceText.value("Hides spoiler-prone episode details in episode lists until you have watched them."), isOn: $preferences.hideSpoilers)
                    if preferences.hideSpoilers {
                        VStack(spacing: 18) {
                            HarborSettingsToggle(DesktopInterfaceText.value("Blur thumbnails"), note: DesktopInterfaceText.value("Frosts the still image on each unwatched episode in the list."), isOn: $preferences.blurEpisodes)
                            HarborSettingsToggle(DesktopInterfaceText.value("Blur titles"), note: DesktopInterfaceText.value("Hides the episode name, which often gives the twist away on its own."), isOn: $preferences.spoilerHideTitles)
                            HarborSettingsToggle(DesktopInterfaceText.value("Blur descriptions"), note: DesktopInterfaceText.value("Hides the synopsis text under each unwatched episode."), isOn: $preferences.spoilerHideDescriptions)
                        }.padding(.leading, 14)
                            .overlay(alignment: .leading) { Rectangle().fill(ThemePreferences.shared.color("edge-soft")).frame(width: 1) }
                    }
                }
            }.padding(20)
        }.background(HarborTheme.background).navigationTitle(DesktopInterfaceText.value("Library"))
            .navigationBarTitleDisplayMode(.inline).tint(HarborTheme.accent)
            .accessibilityIdentifier("interface-settings-scroll")
    }
}

struct NavigationSettingsView: View {
    @Bindable var preferences = InterfacePreferences.shared
    @State private var resetRevision = 0
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text(DesktopInterfaceText.value("Navigation items")).font(HarborTheme.font(20, weight: .semibold))
                    Spacer()
                    Button { preferences.resetNavigation(); resetRevision += 1 } label: {
                        Label(DesktopInterfaceText.value("Reset"), image: "audio-reset-sync")
                            .font(HarborTheme.font(13, weight: .medium)).padding(.horizontal, 10).frame(minHeight: 44)
                    }.buttonStyle(.plain).accessibilityIdentifier("navigation-reset")
                }
                ForEach(preferences.orderedSections) { section in NavigationSettingRow(section: section, preferences: preferences, resetRevision: resetRevision) }
            }.padding(20)
        }.background(HarborTheme.background).navigationTitle(DesktopInterfaceText.value("Navigation"))
            .navigationBarTitleDisplayMode(.inline).tint(HarborTheme.accent)
            .accessibilityIdentifier("navigation-settings-scroll")
    }
}

private struct HomeStylePicker: View {
    @Binding var selection: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let choices = [("harbor", "Harbor curated", "home-style-harbor"), ("classic", "Classic Stremio", "home-style-classic")]
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(choices, id: \.0) { value, title, artwork in
                Button { selection = value } label: {
                    VStack(alignment: .leading, spacing: 10) {
                        Image(artwork).resizable().aspectRatio(16.0 / 10, contentMode: .fill)
                            .frame(maxWidth: .infinity).clipped().clipShape(.rect(cornerRadius: 10))
                            .overlay { RoundedRectangle(cornerRadius: 10).stroke(selection == value ? HarborTheme.accent : ThemePreferences.shared.color("edge-soft"), lineWidth: 1) }
                            .accessibilityHidden(true)
                        HStack(spacing: 8) {
                            Text(DesktopInterfaceText.value(title)).font(HarborTheme.font(14, weight: .semibold))
                            if selection == value { Image("desktop-check").resizable().scaledToFit().frame(width: 18, height: 18).foregroundStyle(HarborTheme.accent).accessibilityHidden(true) }
                        }.frame(minHeight: 44, alignment: .leading)
                    }.contentShape(Rectangle()).foregroundStyle(HarborTheme.ink)
                }.buttonStyle(.plain).accessibilityAddTraits(selection == value ? [.isSelected] : [])
                    .accessibilityIdentifier("home-style-\(value)")
            }
        }.animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: selection)
            .accessibilityElement(children: .contain).accessibilityLabel(DesktopInterfaceText.value("Home style"))
    }
}

private struct NavigationSettingRow: View {
    let section: HarborSection
    @Bindable var preferences: InterfacePreferences
    let resetRevision: Int
    @State private var draft = ""
    @FocusState private var editing: Bool
    private var hidden: Bool { preferences.navigationHidden.contains(section.rawValue) }
    private var name: String { preferences.label(section) }
    private func text(_ original: String) -> String { DesktopInterfaceText.value(original).replacingOccurrences(of: "{name}", with: name) }
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image("nav-\(section.icon)").resizable().scaledToFit().frame(width: 20, height: 20).padding(.trailing, 4).accessibilityHidden(true)
                TextField(section.title, text: $draft).font(HarborTheme.font(14, weight: .medium))
                    .focused($editing).autocorrectionDisabled().submitLabel(.done).onSubmit { commit(); editing = false }
                    .accessibilityLabel(text("Rename {name}")).accessibilityIdentifier("navigation-name-\(section.rawValue)")
                moveButton(-1, icon: "settings-chevron-up", label: "Move {name} up")
                moveButton(1, icon: "settings-chevron-down", label: "Move {name} down")
                if section != .home && section != .settings {
                    Button {
                        if !preferences.navigationHidden.insert(section.rawValue).inserted { preferences.navigationHidden.remove(section.rawValue) }
                    } label: {
                        Image(hidden ? "settings-eye-off" : "settings-eye").resizable().scaledToFit().frame(width: 16, height: 16).frame(width: 44, height: 44)
                            .foregroundStyle(hidden ? ThemePreferences.shared.color("danger") : ThemePreferences.shared.color("ink-subtle"))
                    }.buttonStyle(.plain).accessibilityLabel(text(hidden ? "Show {name} in navigation" : "Hide {name} from navigation"))
                        .accessibilityValue(DesktopInterfaceText.value(hidden ? "Hidden" : "Visible"))
                        .accessibilityIdentifier("navigation-visible-\(section.rawValue)")
                }
            }
            if preferences.navigationNames[section.rawValue] != nil {
                Button { preferences.navigationNames[section.rawValue] = nil; draft = section.title } label: {
                    Text(DesktopInterfaceText.value("Renamed")).font(HarborTheme.font(10.5, weight: .semibold)).tracking(1.4)
                        .padding(.horizontal, 8).frame(minHeight: 44).foregroundStyle(HarborTheme.accent)
                }.buttonStyle(.plain).accessibilityLabel(DesktopInterfaceText.value("Reset to default name"))
            }
        }.padding(.horizontal, 8).padding(.vertical, 6).background(HarborTheme.background, in: .rect(cornerRadius: 6))
            .overlay { RoundedRectangle(cornerRadius: 6).stroke(ThemePreferences.shared.color("edge-soft"), lineWidth: 1) }
            .opacity(hidden ? 0.6 : 1)
            .onAppear { draft = name }.onChange(of: name) { _, value in if !editing { draft = value } }
            .onChange(of: editing) { _, focused in if !focused { commit() } }
            .onChange(of: resetRevision) { _, _ in draft = name; editing = false }
    }
    private func moveButton(_ offset: Int, icon: String, label: String) -> some View {
        let order = preferences.orderedSections
        let index = order.firstIndex(of: section) ?? 0
        let destination = index + offset
        return Button {
            var ids = order.map(\.rawValue)
            guard ids.indices.contains(destination) else { return }
            ids.swapAt(index, destination); preferences.navigationOrder = ids
        } label: { Image(icon).resizable().scaledToFit().frame(width: 16, height: 16).frame(width: 44, height: 44) }
            .buttonStyle(.plain).disabled(!order.indices.contains(destination)).opacity(order.indices.contains(destination) ? 1 : 0.25)
            .accessibilityLabel(text(label)).accessibilityIdentifier("navigation-\(offset < 0 ? "up" : "down")-\(section.rawValue)")
    }
    private func commit() {
        let clean = String(draft.trimmingCharacters(in: .whitespacesAndNewlines).prefix(120))
        preferences.navigationNames[section.rawValue] = clean.isEmpty || clean == section.title ? nil : clean
        draft = name
    }
}

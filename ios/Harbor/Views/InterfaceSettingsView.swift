import SwiftUI

struct InterfaceSettingsView: View {
    let identity: HarborProfileSync
    @Bindable var preferences = InterfacePreferences.shared
    @AppStorage("tvdbOrderPanel") private var richEpisodeOrderPanel = true
    @AppStorage("tvdbSeasonType") private var episodeOrder = "aired"
    private var homeLanguagesValue: Binding<String> {
        Binding(get: { preferences.homeLanguages.joined(separator: ",") }, set: { (value: String) in preferences.homeLanguages = SubtitleLanguages.preferredCodes(value) })
    }
    /// Desktop's `episodeCardScale` as the choice tags "1.0", "1.2" and "1.45".
    private var cardScaleValue: Binding<String> {
        Binding(get: { String(EpisodeLayoutPolicy.cardScale(preferences.episodeCardScale)) }, set: { (value: String) in preferences.episodeCardScale = Double(value) ?? 1 })
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                HarborSettingsSection(DesktopInterfaceText.value("Motion")) {
                    HarborSettingsToggle(DesktopInterfaceText.value("Rotate featured banners automatically"), isOn: $preferences.autoRotateBanners)
                    HarborSettingsToggle(DesktopInterfaceText.value("Animated sidebar icons"), note: DesktopInterfaceText.value("Sidebar icons animate when pressed or hovered with a pointer. Turn this off to keep them static."), isOn: $preferences.navIconAnimations)
                }
                HarborSettingsSection(DesktopInterfaceText.value("Home layout")) {
                    Text(DesktopInterfaceText.value("The shape of the whole Home page. Everything below tunes the rows inside it."))
                        .font(HarborTheme.font(13)).foregroundStyle(.secondary)
                    HomeStylePicker(selection: $preferences.homeMode)
                    NavigationLink { HeroTrailerSettingsView() } label: {
                        HStack {
                            Text(DesktopInterfaceText.value("Hero trailers")).font(HarborTheme.font(14, weight: .semibold))
                            Spacer()
                            Image("desktop-chevron-right").resizable().scaledToFit().frame(width: 16, height: 16)
                        }.frame(minHeight: 44).contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityIdentifier("settings-hero-trailers-link")
                    NavigationLink { NavigationSettingsView(identity: identity) } label: {
                        HStack {
                            Text(DesktopInterfaceText.value("Navigation items")).font(HarborTheme.font(14, weight: .semibold))
                            Spacer()
                            Image("desktop-chevron-right").resizable().scaledToFit().frame(width: 16, height: 16)
                        }.frame(minHeight: 44).contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityIdentifier("settings-navigation")
                    HarborSettingsToggle(DesktopInterfaceText.value("Show every addon row"), note: DesktopInterfaceText.value("By default, addon rails that duplicate the built-in ones (Trending, Popular, Top Rated, etc.) are merged so you don't see the same row twice. Turn this on to show every one, duplicates and all."), isOn: $preferences.homeShowAllAddonRows).accessibilityIdentifier("settings-show-all-addon-rows")
                    HarborSettingsToggle(DesktopInterfaceText.value("Hide watched titles in catalogs"), note: DesktopInterfaceText.value("Movies you've watched and shows you've made progress on stop appearing in the built-in catalog rows, using your local watch history (and Trakt if connected). Continue Watching is never touched."), isOn: $preferences.hideWatchedInCatalogs).accessibilityIdentifier("settings-hide-watched")
                    HarborSettingsToggle(DesktopInterfaceText.value("Hide unreleased titles"), note: DesktopInterfaceText.value("Movies and shows with a future release date stop appearing in the built-in home catalog rows, so Home only shows what you can watch right now."), isOn: $preferences.hideUnreleased).accessibilityIdentifier("settings-hide-unreleased")
                    VStack(alignment: .leading, spacing: 10) {
                        Text(DesktopInterfaceText.value("Home catalogs")).font(HarborTheme.font(14, weight: .semibold))
                        Text(DesktopInterfaceText.value("Only show titles in these original languages on the Home rows. Leave all off to show everything."))
                            .font(HarborTheme.font(13)).foregroundStyle(.secondary)
                        HarborLanguagesPicker(value: homeLanguagesValue, identifier: "settings-home-languages")
                    }
                    HarborSettingsToggle(DesktopInterfaceText.value("Watchlist shows only saved titles"), note: DesktopInterfaceText.value("Keep the Library Watchlist tab limited to titles you added in Stremio. Turn this off to also include anything Stremio auto-added when you pressed play."), isOn: $preferences.libraryBookmarkedOnly).accessibilityIdentifier("settings-library-bookmarked-only")
                    HarborSettingsToggle(DesktopInterfaceText.value("Advance Continue Watching to the next episode"), note: DesktopInterfaceText.value("When you finish an episode, the Home Continue Watching card moves on to the next episode instead of sitting at 0 minutes left."), isOn: $preferences.cwAdvanceNext).accessibilityIdentifier("settings-cw-advance-next")
                    HarborSettingsToggle(DesktopInterfaceText.value("Keep anime in the Anime room only"), note: DesktopInterfaceText.value("Hides anime from the Home Continue Watching row. It still appears in the Anime tab's own Continue Watching."), isOn: $preferences.animeOnlyInAnimeRoom).accessibilityIdentifier("settings-anime-only-room")
                }
                HarborSettingsSection(DesktopInterfaceText.value("Poster cards")) {
                    Text(DesktopInterfaceText.value("Scores")).font(HarborTheme.font(14, weight: .semibold))
                    HarborSettingsToggle("IMDb", isOn: $preferences.showImdbBadge)
                    HarborSettingsToggle("TMDB", isOn: $preferences.showTmdbBadge)
                }
                ContinueEndingControls()
                ContinueSourceControls()
                HarborSettingsSection(DesktopInterfaceText.value("Show pages")) {
                    HarborSettingsToggle(DesktopInterfaceText.value("Mark watched button"), isOn: $preferences.showWatchedButton)
                    HarborSettingsToggle(DesktopInterfaceText.value("Remember your place on show pages"), note: DesktopInterfaceText.value("Reopen a show at the position where you left it, including its episode list."), isOn: $preferences.resumeDetailScroll)
                        .accessibilityIdentifier("settings-resume-detail-scroll")
                }
                HarborSettingsSection(DesktopInterfaceText.value("Episode ordering")) {
                    HarborSettingsToggle(DesktopInterfaceText.value("Rich season and order panel"), isOn: $richEpisodeOrderPanel)
                        .accessibilityIdentifier("settings-rich-episode-order")
                    if !richEpisodeOrderPanel {
                        HarborSettingsChoice(DesktopInterfaceText.value("Which order"),
                            selection: Binding(get: { (TVDBEpisodeOrderKind(setting: episodeOrder) ?? .aired).rawValue }, set: { episodeOrder = $0 }),
                            choices: TVDBEpisodeOrderKind.allCases.map { ($0.localizedLabel, $0.rawValue) }, identifier: "settings-episode-order")
                    }
                }
                HarborSettingsSection(DesktopInterfaceText.value("Episode cards")) {
                    HarborSettingsToggle(DesktopInterfaceText.value("Show episode description"), note: DesktopInterfaceText.value("Shows the episode synopsis on the cards. Turn it off to hide it."), isOn: $preferences.showEpisodeDescription)
                    HarborSettingsToggle(DesktopInterfaceText.value("Show episode ratings"), isOn: $preferences.showEpisodeRating).accessibilityIdentifier("settings-show-episode-rating")
                    HarborSettingsChoice(DesktopInterfaceText.value("Card size"), selection: cardScaleValue,
                        choices: [(DesktopInterfaceText.value("Default"), "1.0"), (DesktopInterfaceText.value("Large"), "1.2"), (DesktopInterfaceText.value("Extra large"), "1.45")],
                        localizeChoices: false, identifier: "settings-episode-card-scale")
                    Text(DesktopInterfaceText.value("How big episode cards are in the strip and grid layouts. Bigger cards show larger artwork."))
                        .font(HarborTheme.font(13)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                HarborSettingsSection(DesktopInterfaceText.value("Browsing")) {
                    NavigationLink { AnimePicksSettingsView() } label: {
                        HStack {
                            Text(DesktopInterfaceText.value("Tune anime")).font(HarborTheme.font(14, weight: .semibold))
                            Spacer()
                            Image("desktop-chevron-right").resizable().scaledToFit().frame(width: 16, height: 16)
                        }.frame(minHeight: 44).contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityIdentifier("settings-anime-picks")
                    HarborSettingsToggle(DesktopInterfaceText.value("Hide and skip episodes"), note: DesktopInterfaceText.value("Adds a Hide option when you right-click an episode. Hidden episodes disappear from the list and are skipped by Up Next. A Show hidden toggle on each show lets you bring them back."), isOn: $preferences.episodeHiding)
                        .accessibilityIdentifier("settings-episode-hiding")
                    HarborSettingsToggle(DesktopInterfaceText.value("Group episodes by story arc"), note: DesktopInterfaceText.value("Browse by story arc on supported shows, such as One Piece. Requires a TMDB key."), isOn: $preferences.episodeArcGroups)
                        .accessibilityIdentifier("settings-episode-arc-groups")
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

struct ContinueSourceControls: View {
    @AppStorage("cwSources") private var cwSources = ContinueWatchingSources.defaultValue
    @AppStorage("cwPerProfile") private var privateContinuing = false
    var body: some View {
        VStack(alignment: .leading, spacing: 30) {
            HarborSettingsToggle(DesktopInterfaceText.value("Keep Continue Watching private to each profile"),
                note: LocalProfileText.value(.sharedContinue),
                isOn: $privateContinuing).accessibilityIdentifier("settings-cw-private")
            HarborSettingsSection(DesktopInterfaceText.value("Continue Watching sources")) {
            Text(DesktopInterfaceText.value("Choose which services feed your Continue Watching row. Turn on as many as you like and Harbor merges them, keeping the most recent progress for each title. What you watch is still scrobbled to every connected service regardless of what you pick here."))
                .font(.caption).foregroundStyle(.secondary)
            HarborSettingsToggle(DesktopInterfaceText.value("Harbor library"), note: DesktopInterfaceText.value("Your own Harbor account progress. The primary source for almost everyone."),
                isOn: source(\.library)).disabled(privateContinuing).accessibilityIdentifier("settings-cw-library")
            HarborSettingsToggle(DesktopInterfaceText.value("Downloads"), note: DesktopInterfaceText.value("Titles you are part-way through in your local downloads, even offline."),
                isOn: source(\.local)).accessibilityIdentifier("settings-cw-local")
            HarborSettingsToggle(DesktopInterfaceText.value("Simkl progress"), note: DesktopInterfaceText.value("Pulls what you have part-watched on Simkl into the row, marked with the Simkl logo. Requires a connected Simkl account."),
                isOn: source(\.simkl)).disabled(privateContinuing).accessibilityIdentifier("settings-cw-simkl")
            HarborSettingsToggle(DesktopInterfaceText.value("Trakt progress"), note: DesktopInterfaceText.value("Pulls what you have part-watched on Trakt into the row, marked with the Trakt logo. Requires a connected Trakt account."),
                isOn: source(\.trakt)).disabled(privateContinuing).accessibilityIdentifier("settings-cw-trakt")
            if privateContinuing {
                Text(DesktopInterfaceText.value("Unavailable while Continue Watching is kept private to each profile, because Simkl progress is shared across every profile on this account.")).font(.caption).foregroundStyle(.secondary)
            }
            }
        }
    }
    private func source(_ key: WritableKeyPath<ContinueWatchingSources, Bool>) -> Binding<Bool> {
        Binding(get: { ContinueWatchingSources(rawValue: cwSources)[keyPath: key] }, set: { value in
            var next = ContinueWatchingSources(rawValue: cwSources); next[keyPath: key] = value; cwSources = next.rawValue
        })
    }
}

/// Desktop's Continue Watching group: caught-up shows, the end-of-series behaviour and the card artwork.
struct ContinueEndingControls: View {
    @Bindable var preferences = InterfacePreferences.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 30) {
        HarborSettingsSection(DesktopInterfaceText.value("Rows")) {
            HarborSettingsToggle(DesktopInterfaceText.value("New Episodes row"),
                note: DesktopInterfaceText.value("Adds a row under Continue Watching listing episodes that aired recently for shows you were already watching. Dismiss them one at a time or clear the whole row. Off by default."),
                isOn: $preferences.homeNewEpisodes).accessibilityIdentifier("settings-home-new-episodes")
        }
        HarborSettingsSection(DesktopInterfaceText.value("Continue Watching")) {
            HarborSettingsToggle(DesktopInterfaceText.value("Remove shows once you're caught up"),
                note: DesktopInterfaceText.value("On by default: once you've watched every episode that has aired, the show leaves Continue Watching and returns when a new episode drops. Turn it off to keep caught-up shows on the row."),
                isOn: $preferences.cwHideCaughtUp).accessibilityIdentifier("settings-cw-hide-caught-up")
            HarborSettingsChoice("When the latest episode ends", selection: $preferences.animeCwEnd,
                choices: [("Hide", "hide"), ("Timer", "timer")], identifier: "settings-cw-anime-end")
            Text(DesktopInterfaceText.value("Hide until the next episode airs, or keep showing a countdown to when it drops."))
                .font(.caption).foregroundStyle(.secondary)
            HarborSettingsToggle(DesktopInterfaceText.value("Prefer episode still artwork"),
                isOn: $preferences.cwPreferEpisodeStill).accessibilityIdentifier("settings-cw-prefer-still")
        }
        }
    }
}

struct NavigationSettingsView: View {
    let identity: HarborProfileSync
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
                    }.buttonStyle(.plain).disabled(!preferences.navigation.ready).accessibilityIdentifier("navigation-reset")
                }
                if let error = preferences.navigation.error {
                    Text(DesktopInterfaceText.value(error)).font(.caption).foregroundStyle(.orange)
                    if !preferences.navigation.ready { Button(DesktopInterfaceText.value("Retry")) { preferences.navigation.reload() }.buttonStyle(HarborAccountButtonStyle()) }
                }
                if preferences.navigation.scope != nil {
                    let cloud = identity
                    if cloud.signedIn {
                        if let error = cloud.navigation.error ?? cloud.error { Text(DesktopInterfaceText.value(error)).font(.caption).foregroundStyle(.orange) }
                        if cloud.navigation.hasParkedVersion {
                            Text(DesktopInterfaceText.value("Another device changed navigation. Your previous version is saved on this device.")).font(.caption).foregroundStyle(.secondary)
                            Button(DesktopInterfaceText.value("Restore my version")) { cloud.navigation.restoreMyVersion() }
                                .buttonStyle(HarborAccountButtonStyle()).disabled(cloud.busy || cloud.navigation.hasPendingChanges).accessibilityIdentifier("navigation-restore-version")
                        }
                        if cloud.navigation.hasPendingChanges { Text(DesktopInterfaceText.value("Navigation changes waiting to sync")).font(.caption).foregroundStyle(.secondary) }
                    }
                }
                ForEach(preferences.orderedSections) { section in NavigationSettingRow(section: section, preferences: preferences, resetRevision: resetRevision).disabled(!preferences.navigation.ready) }
            }.padding(20)
        }.background(HarborTheme.background).navigationTitle(DesktopInterfaceText.value("Navigation"))
            .navigationBarTitleDisplayMode(.inline).tint(HarborTheme.accent)
            .accessibilityIdentifier("navigation-settings-scroll")
    }
}

struct HomeStylePicker: View {
    @Binding var selection: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let choices = [
        ("harbor", "Harbor curated", "home-style-harbor", "Hero, Top 10, Trending, In Theaters, per-service rails. Your addons append underneath."),
        ("classic", "Classic Stremio", "home-style-classic", "Continue Watching, then your addon catalogs in install order. No hero, no Harbor rails.")
    ]
    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 16, alignment: .top)], alignment: .leading, spacing: 16) {
            ForEach(choices, id: \.0) { value, title, artwork, description in
                Button { selection = value } label: {
                    VStack(alignment: .leading, spacing: 10) {
                        Image(artwork).resizable().aspectRatio(16.0 / 10, contentMode: .fill)
                            .frame(maxWidth: .infinity).clipped().clipShape(.rect(cornerRadius: 10))
                            .overlay { RoundedRectangle(cornerRadius: 10).stroke(selection == value ? HarborTheme.accent : ThemePreferences.shared.color("edge-soft"), lineWidth: 1) }
                            .accessibilityHidden(true)
                        HStack(spacing: 8) {
                            Image(systemName: selection == value ? "largecircle.fill.circle" : "circle").accessibilityHidden(true)
                            Text(DesktopInterfaceText.value(title)).font(HarborTheme.font(14, weight: .semibold))
                        }.frame(minHeight: 44, alignment: .leading)
                        Text(DesktopInterfaceText.value(description)).font(HarborTheme.font(12.5)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
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
    @State private var draftScope: NavigationScope?
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
            .onAppear { draft = name; draftScope = preferences.navigation.scope }.onChange(of: name) { _, value in if !editing { draft = value } }
            .onChange(of: editing) { _, focused in if focused { draftScope = preferences.navigation.scope } else { commit() } }
            .onChange(of: preferences.navigation.scope) { _, _ in draftScope = nil; editing = false; draft = name }
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
        guard let draftScope, draftScope == preferences.navigation.scope else { draft = name; return }
        let clean = String(draft.trimmingCharacters(in: .whitespacesAndNewlines).prefix(120))
        preferences.navigation.change(in: draftScope) { $0.renamed[section.rawValue] = clean.isEmpty || clean == section.title ? nil : clean }
        draft = name
    }
}

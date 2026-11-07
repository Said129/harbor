import SwiftUI

/// Desktop's "Tune anime" dialog (`components/anime-genre-picker.tsx`) as a Settings page: favourite genres, hidden
/// origins and hiding watched titles. The Anime page's own Tune button and its hero hook are not part of this view.
struct AnimePicksSettingsView: View {
    @Bindable var preferences = AnimePicksPreferences.shared

    private var hideWatchedValue: Binding<Bool> {
        Binding(get: { preferences.hideWatched }, set: { (value: Bool) in preferences.setHideWatched(value) })
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                Text(DesktopInterfaceText.value("Steer your Top Picks and hero toward what you love, and hide what you don't."))
                    .font(HarborTheme.font(13)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                HarborSettingsSection(DesktopInterfaceText.value("Genres you want more of")) {
                    genreGrid
                    genreSummary
                }
                HarborSettingsSection(DesktopInterfaceText.value("Hide from your picks")) {
                    originGrid
                    HarborSettingsToggle(DesktopInterfaceText.value("Hide anime I've already watched"), isOn: hideWatchedValue)
                        .accessibilityIdentifier("anime-picks-hide-watched")
                }
            }.padding(20)
        }
        .background(HarborTheme.background)
        .navigationTitle(DesktopInterfaceText.value("Tune anime"))
        .navigationBarTitleDisplayMode(.inline)
        .tint(HarborTheme.accent)
        .accessibilityIdentifier("anime-picks-settings-scroll")
        .onAppear { preferences.reloadPreferences() }
    }

    private var genreGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8, alignment: .leading)], alignment: .leading, spacing: 8) {
            ForEach(AnimePicksPolicy.genres, id: \.id) { genre in
                HarborPill(title: DesktopInterfaceText.value(genre.label), selected: preferences.favoriteGenres.contains(genre.id)) {
                    preferences.toggleGenre(genre.id)
                }
                .accessibilityIdentifier("anime-picks-genre-\(genre.id)")
            }
        }
    }

    /// Desktop's footer: the selected count, or "None yet", and "Clear all" while anything is selected.
    private var genreSummary: some View {
        HStack(spacing: 12) {
            Text(genreCountText).font(.caption).foregroundStyle(.secondary)
            Spacer(minLength: 0)
            if !preferences.favoriteGenres.isEmpty {
                Button(DesktopInterfaceText.value("Clear all")) { preferences.setFavoriteGenres([]) }
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("anime-picks-clear-genres")
            }
        }
    }

    private var genreCountText: String {
        let count = preferences.favoriteGenres.count
        if count == 0 { return DesktopInterfaceText.value("None yet") }
        return DesktopInterfaceText.value("{count} selected", variables: ["count": String(count)])
    }

    /// Desktop's origin chips: a selected chip hides that origin.
    private var originGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 8, alignment: .leading)], alignment: .leading, spacing: 8) {
            ForEach(AnimePicksPolicy.origins, id: \.code) { origin in
                HarborPill(title: DesktopInterfaceText.value(origin.label), selected: preferences.excludeOrigins.contains(origin.code)) {
                    preferences.toggleOrigin(origin.code)
                }
                .accessibilityIdentifier("anime-picks-origin-\(origin.code)")
            }
        }
    }
}

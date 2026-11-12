import SwiftUI

/// Desktop's "Home Rail Settings" and anime title language (`views/settings/simkl-panel.tsx`).
/// The values are the active profile's UserDefaults keys, the same ones `SimklHomeRailPreferences` reads.
struct SimklRailsSettingsView: View {
    @AppStorage(SimklHomeRails.Keys.homeRails) private var homeRails = false
    @AppStorage(SimklHomeRails.Keys.upNext) private var upNext = false
    @AppStorage(SimklHomeRails.Keys.trending) private var trending = false
    @AppStorage(SimklHomeRails.Keys.moviesPlanToWatch) private var moviesPlanToWatch = true
    @AppStorage(SimklHomeRails.Keys.showsWatching) private var showsWatching = true
    @AppStorage(SimklHomeRails.Keys.showsPlanToWatch) private var showsPlanToWatch = true

    private func text(_ key: String) -> String { DesktopInterfaceText.value(key) }

    private func option(_ label: String, _ detail: String, isOn: Binding<Bool>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(text(label), isOn: isOn)
            Text(text(detail)).font(.caption).foregroundStyle(.secondary)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text(text("Choose which Simkl rails appear on your home screen.")).foregroundStyle(.secondary)
                option("Show Simkl rails on Home", "Display your Watching, Plan to Watch, Up Next, and Trending rows on the home screen.", isOn: $homeRails)
                    .accessibilityIdentifier("simkl-rails-home")
                option("Show Up Next on Simkl rail", "Display upcoming episodes from your watching and plan-to-watch lists.", isOn: $upNext)
                    .accessibilityIdentifier("simkl-rails-up-next")
                option("Show Simkl Trending Today rail", "Display today's trending movies, TV shows, and anime from Simkl.", isOn: $trending)
                    .accessibilityIdentifier("simkl-rails-trending")
                if !homeRails {
                    Text(text("Simkl rails are turned off, so none of the rows below appear on Home yet."))
                        .font(.caption).foregroundStyle(.orange)
                }
                VStack(alignment: .leading, spacing: 16) {
                    Text(text("Movies")).font(.headline)
                    option("Plan to Watch", "Show a row of the movies on your Simkl plan-to-watch list.", isOn: $moviesPlanToWatch)
                }
                VStack(alignment: .leading, spacing: 16) {
                    Text(text("TV Shows")).font(.headline)
                    option("Watching", "Show a row of the shows you are part way through.", isOn: $showsWatching)
                    option("Plan to Watch", "Show a row of the shows on your Simkl plan-to-watch list.", isOn: $showsPlanToWatch)
                }
                // The anime title language picker is not offered: iOS shows one title per Simkl row, so it would change nothing.
            }.padding(20).frame(maxWidth: 680, alignment: .leading).frame(maxWidth: .infinity, alignment: .leading)
        }.background(HarborTheme.background).foregroundStyle(HarborTheme.ink)
            .navigationTitle(text("Home Rail Settings")).navigationBarTitleDisplayMode(.inline)
            .accessibilityIdentifier("simkl-rails-settings-scroll")
    }
}

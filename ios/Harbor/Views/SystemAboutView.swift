import SwiftUI

struct SystemAboutView: View {
    @State private var restored = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HarborPageHeading(title: DesktopInterfaceText.value("About"))
                HarborSettingsSection("Onboarding") {
                    Text(DesktopInterfaceText.value("Replay the walkthrough or unhide every dismissed tip in the app.")).font(.caption).foregroundStyle(.secondary)
                    Button { AppGuidePreferences.shared.replay() } label: {
                        action("Replay walkthrough", description: "Re-runs the welcome flow and clears every dismissed tip.")
                    }.buttonStyle(HarborAccountButtonStyle()).accessibilityIdentifier("about-replay")
                    Button { AppGuidePreferences.shared.restoreHints(); restored = true } label: {
                        action(restored ? "Restored" : "Restore dismissed hints", description: "Brings back the small in-app tips you've dismissed without redoing the welcome flow.")
                    }.buttonStyle(HarborAccountButtonStyle()).accessibilityIdentifier("about-restore-hints")
                }
                HarborSettingsSection("About") {
                    info("Version", value: "\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "") (\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""))")
                    info("Build", value: "iOS / iPadOS · SwiftUI / libmpv")
                    info("Desktop reference", value: "0.9.132 (Beta)")
                    info("Compatibility", value: "iOS / iPadOS 17+")
                }
                HarborSettingsSection("Legal") {
                    NavigationLink { ReadingFontNoticesView() } label: {
                        Text(DesktopInterfaceText.value("Legal") + " · wuff / Brotli")
                    }
                    Text(DesktopInterfaceText.value("Harbor is an independent, open-source client for iPhone and iPad.")).font(.subheadline).foregroundStyle(.secondary)
                    Text(DesktopInterfaceText.value("It is not affiliated with, endorsed by, sponsored by, or in any way associated with {company}.", variables: ["company": "Stremio Ltd."])).font(.subheadline)
                    Text(DesktopInterfaceText.value("It is not affiliated with the maker of {product}, or with any company, addon author, or trademark holder referenced inside the app.", variables: ["product": "Stremio"])).font(.subheadline).foregroundStyle(.secondary)
                    Text(DesktopInterfaceText.value("{names}, and all other names, logos, and brand references are property of their respective owners and are used here only for compatibility and identification.", variables: ["names": "Stremio, Cinemeta, OpenSubtitles, Real-Debrid, Premiumize, AllDebrid, TorBox, DebridLink, TMDB, Trakt, IMDb, Netflix, Disney+"])).font(.subheadline).foregroundStyle(.secondary)
                    Text(DesktopInterfaceText.value("{app} itself does not host, distribute, or index any media. All streams come from third-party addons, debrid services, or your own {service} account that you configure yourself. You are responsible for what you choose to play and for complying with the laws of your jurisdiction.", variables: ["app": "Harbor", "service": "Stremio"])).font(.subheadline).foregroundStyle(.secondary)
                }
            }.padding(20).frame(maxWidth: 900).frame(maxWidth: .infinity)
        }.background(HarborTheme.background).foregroundStyle(HarborTheme.ink)
            .navigationTitle(DesktopInterfaceText.value("About")).navigationBarTitleDisplayMode(.inline).accessibilityIdentifier("system-about")
    }
    private func action(_ title: String, description: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(DesktopInterfaceText.value(title))
            Text(DesktopInterfaceText.value(description)).font(.caption).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private func info(_ title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) { Text(DesktopInterfaceText.value(title)); Spacer(); Text(value).foregroundStyle(.secondary).multilineTextAlignment(.trailing) }.font(HarborTheme.font(14)).frame(minHeight: 36)
    }
}

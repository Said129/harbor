import SwiftUI

struct SettingsView: View {
    let app: AppModel
    @State private var export: URL?
    @State private var error: String?
    @State private var query = ""
    private func matches(_ title: String, group: String? = nil) -> Bool {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let labels = [title, group].compactMap { $0 }.flatMap { [$0, DesktopInterfaceText.value($0)] }
        return term.isEmpty || labels.contains { $0.localizedCaseInsensitiveContains(term) }
    }
    private var playerPages: [PlayerSettingsPage] { [PlayerSettingsPage.playback, .video, .audio].filter { matches($0.title, group: "Playback") } }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HarborPageHeading(title: DesktopInterfaceText.value("Settings"))
                HarborSearchField(prompt: DesktopInterfaceText.value("Search settings"), text: $query)
                if matches("Your profile", group: "Account & setup") || matches("Stremio") {
                    group("Account & setup") {
                        ProfileAccountButton(app: app, expanded: true).accessibilityIdentifier("settings-account").padding(14)
                    }
                }
                if !playerPages.isEmpty {
                    group("Playback") {
                        ForEach(playerPages) { page in
                            NavigationLink { PlayerSettingsView(page: page).toolbar(.visible, for: .navigationBar) } label: {
                                SettingsRow(title: page.title, icon: page.icon)
                            }.accessibilityIdentifier("settings-\(page.rawValue)")
                        }
                    }
                }
                if matches("Subtitles", group: "Languages & subtitles") {
                    group("Languages & subtitles") {
                        NavigationLink { PlayerSettingsView(page: .subtitles).toolbar(.visible, for: .navigationBar) } label: {
                            SettingsRow(title: PlayerSettingsPage.subtitles.title, icon: PlayerSettingsPage.subtitles.icon)
                        }.accessibilityIdentifier("settings-subtitles")
                    }
                }
                if matches("Metadata providers", group: "Sources & library") || matches("Library", group: "Sources & library") {
                    group("Sources & library") {
                        if matches("Metadata providers", group: "Sources & library") {
                            NavigationLink { MetadataSettingsView().toolbar(.visible, for: .navigationBar) } label: {
                                SettingsRow(title: DesktopInterfaceText.value("Metadata providers"), icon: "nav-catalogs")
                            }.accessibilityIdentifier("settings-metadata")
                        }
                        if matches("Library", group: "Sources & library") {
                            NavigationLink { InterfaceSettingsView().toolbar(.visible, for: .navigationBar) } label: {
                                SettingsRow(title: DesktopInterfaceText.value("Library"), icon: "nav-library")
                            }.accessibilityIdentifier("settings-interface")
                        }
                    }
                }
                if matches("Colors", group: "Appearance") {
                    group("Appearance") {
                        NavigationLink { ThemeSettingsView().toolbar(.visible, for: .navigationBar) } label: { SettingsRow(title: DesktopInterfaceText.value("Colors"), icon: "desktop-palette") }.accessibilityIdentifier("settings-theme")
                    }
                }
                if matches("Downloads", group: "System") {
                    group("System") {
                        NavigationLink { DownloadsView(app: app).toolbar(.visible, for: .navigationBar) } label: {
                            SettingsRow(title: DesktopInterfaceText.value("Downloads"), icon: "nav-download")
                        }.accessibilityIdentifier("settings-downloads")
                    }
                }
                if matches("Export log", group: "Help & about") || matches("Share", group: "Help & about") || matches("Version", group: "Help & about") {
                    group("Help & about") {
                        if matches("Export log", group: "Help & about") {
                            Button { do { export = try Diagnostics.shared.export() } catch { self.error = safeMessage(error) } } label: { SettingsRow(title: DesktopInterfaceText.value("Export log"), icon: "ui-help") }
                        }
                        if let export, matches("Share", group: "Help & about") { ShareLink(item: export) { SettingsRow(title: DesktopInterfaceText.value("Share"), icon: "ui-help") } }
                        if let error { Text(error).font(.caption).foregroundStyle(.orange).padding(14) }
                        if matches("Version", group: "Help & about") {
                            HStack {
                                Text(DesktopInterfaceText.value("Version"))
                                Spacer(minLength: 10)
                                Text("\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "") (\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""))").foregroundStyle(.secondary)
                            }.font(HarborTheme.font(14)).padding(14).frame(minHeight: 44)
                        }
                    }
                }
            }.padding(20)
        }.background(HarborTheme.background).buttonStyle(.plain).accessibilityIdentifier("settings-scroll")
            .navigationTitle(DesktopInterfaceText.value("Settings")).toolbar(.hidden, for: .navigationBar)
    }
    private func group<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(DesktopInterfaceText.value(title)).font(HarborTheme.font(14, weight: .semibold)).accessibilityAddTraits(.isHeader)
            VStack(alignment: .leading, spacing: 0, content: content).frame(maxWidth: .infinity, alignment: .leading).background(HarborTheme.surface.opacity(0.65), in: .rect(cornerRadius: 12))
        }
    }
}

private struct SettingsRow: View {
    let title: String
    let icon: String
    var body: some View {
        HStack(spacing: 12) {
            Image(icon).resizable().scaledToFit().frame(width: 19, height: 19).foregroundStyle(.secondary)
            Text(title).font(HarborTheme.font(16.5, weight: .medium)).foregroundStyle(HarborTheme.ink).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Image("desktop-chevron-right").resizable().scaledToFit().frame(width: 14, height: 14).foregroundStyle(.secondary)
        }.padding(.horizontal, 14).frame(minHeight: 54).contentShape(Rectangle())
    }
}

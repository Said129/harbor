import SwiftUI

@MainActor struct ProfileLaunchSettingsView: View {
    let app: AppModel
    @State private var preferences = ProfileLaunchPreferences()
    @State private var ready = false
    @State private var error: String?
    private var profiles: [DeviceHouseholdProfile] { app.profileContext.profiles.profiles.filter { !$0.desktop.isKid } }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if profiles.count > 1 {
                HarborSettingsSection("Startup & default") {
                    HarborSettingsChoice("Who's watching", selection: Binding(get: { preferences.interval }, set: { interval in
                        var next = preferences; next.interval = interval; save(next)
                    }), choices: ProfileLaunchPreferences.Interval.allCases.map { ($0.title, $0) }, identifier: "profile-startup-interval")
                    Text(DesktopInterfaceText.value("Choose when Harbor asks you to pick a profile. Timed prompts appear when you return to Harbor."))
                        .font(HarborTheme.font(13)).foregroundStyle(.secondary)
                    HarborSettingsChoice("Start as", selection: Binding(get: { preferences.defaultProfile(in: profiles)?.id ?? "" }, set: { id in
                        var next = preferences; next.defaultID = id; save(next)
                    }), choices: [(DesktopInterfaceText.value("No default profile"), "")] + profiles.filter { $0.credential == nil }.map { ($0.desktop.name, $0.id) },
                        localizeChoices: false, identifier: "profile-startup-default")
                    Text(DesktopInterfaceText.value("Open this profile at launch. Timed prompts can still appear later. Profiles with a PIN cannot be a default."))
                        .font(HarborTheme.font(13)).foregroundStyle(.secondary)
                }.disabled(!ready || app.accountBusy)
            }
            if let error { Text(error).font(HarborTheme.font(13)).foregroundStyle(.orange).accessibilityIdentifier("profile-startup-error") }
            if !ready { Button(DesktopInterfaceText.value("Retry")) { load() }.buttonStyle(HarborAccountButtonStyle()) }
        }.task(id: app.interfaceProfileScope + "|" + app.settingsOwner) { load() }
    }
    private func load() {
        do { preferences = try app.profileLaunchPreferences(); ready = true; error = nil }
        catch { ready = false; self.error = safeMessage(error) }
    }
    private func save(_ next: ProfileLaunchPreferences) {
        do { try app.updateProfileLaunchPreferences(next); preferences = next; error = nil }
        catch { self.error = safeMessage(error) }
    }
}

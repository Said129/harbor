import SwiftUI

/// Desktop's desktop-notification toggle and the "What to send" and "Media types" options of the webhooks panel
/// (`desktop-field.tsx`, `webhooks-panel.tsx`). The alerts are local notifications for releases that are about to land.
/// The title is new: "Desktop notifications" reads oddly on iPhone, so the row and page use "Release notifications".
struct EpisodeAlertsSettingsView: View {
    let app: AppModel
    @Bindable private var preferences = EpisodeAlertPreferences.shared
    @State private var blocked = false
    private let scheduler = EpisodeAlertScheduler()

    private func text(_ key: String) -> String { DesktopInterfaceText.value(key) }
    private var leadChoices: [(String, Int)] {
        [("At release", 0), ("15 minutes before", 15), ("30 minutes before", 30), ("1 hour before", 60)]
    }
    private var enabledBinding: Binding<Bool> {
        Binding(get: { preferences.enabled }, set: { setEnabled($0) })
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                HarborSettingsSection("Release notifications") {
                    HarborSettingsToggle("Release notifications", note: "Get a system notification on this device when something you follow drops.",
                                         isOn: enabledBinding)
                        .accessibilityIdentifier("episode-alerts-enabled")
                    if blocked {
                        Text(text("Notifications are blocked for Harbor. Enable them in your system settings, then turn this back on."))
                            .font(HarborTheme.font(13)).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                    }
                    HarborSettingsChoice("Lead time", selection: $preferences.leadMinutes, choices: leadChoices, identifier: "episode-alerts-lead")
                    Text(text("Date-only releases have no hour, so they alert at 9:00 AM on their day."))
                        .font(HarborTheme.font(13)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                HarborSettingsSection("What to send", note: "Choose the calendars to follow. A release appears once in your alerts, even if several calendars list it.") {
                    HarborSettingsToggle("My library", note: "Episodes and movies from shows you've saved on Stremio.", isOn: $preferences.library)
                        .accessibilityIdentifier("episode-alerts-library")
                }
                HarborSettingsSection("Media types", note: "Choose which types of releases to include in calendar alerts.") {
                    HarborSettingsToggle("Movies", note: "Include film releases from every source you turned on above.", isOn: $preferences.movies)
                        .accessibilityIdentifier("episode-alerts-movies")
                    HarborSettingsToggle("TV", note: "Include series premieres and new episodes. Anime is counted separately.", isOn: $preferences.series)
                        .accessibilityIdentifier("episode-alerts-tv")
                    HarborSettingsToggle("Anime", note: "Include anime episodes and seasons, even when TV is turned off.", isOn: $preferences.anime)
                        .accessibilityIdentifier("episode-alerts-anime")
                }
            }.padding(20)
        }.background(HarborTheme.background).foregroundStyle(HarborTheme.ink)
            .navigationTitle(text("Release notifications")).navigationBarTitleDisplayMode(.inline)
            .accessibilityIdentifier("episode-alerts-scroll")
            .task { await updateBlocked() }
            .onChange(of: preferences.settings) { _, _ in reschedule() }
    }

    /// Turning the alerts on asks the system for permission first; a refusal leaves them off and says why.
    private func setEnabled(_ on: Bool) {
        guard on else {
            preferences.enabled = false
            blocked = false
            return
        }
        Task {
            let granted = await scheduler.requestAuthorization()
            blocked = !granted
            preferences.enabled = granted
        }
    }

    private func updateBlocked() async {
        let allowed = await scheduler.authorized()
        blocked = preferences.enabled && !allowed
    }

    private func reschedule() {
        Task { await EpisodeAlertRefresh.refresh(app: app, force: true) }
    }
}

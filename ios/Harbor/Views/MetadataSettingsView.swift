import SwiftUI

struct MetadataSettingsView: View {
    @Bindable var preferences = MetadataPreferences.shared
    @State private var editingKey = false
    private let countries = ["US", "ES", "GB", "FR", "DE", "IT", "PT", "MX", "AR", "BR", "JP"]
    private let languages = ["es-ES", "en-US", "fr-FR", "ja-JP", "pt-BR"]
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                HarborSettingsSection(DesktopInterfaceText.value("Metadata providers")) {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 10) {
                            Image("metadata-tmdb").resizable().scaledToFit().frame(width: 20, height: 20).accessibilityHidden(true)
                            Text("TMDB").font(HarborTheme.font(16.5, weight: .medium))
                            Text(DesktopInterfaceText.value("Recommended").uppercased()).font(HarborTheme.font(11, weight: .bold)).tracking(0.6)
                                .padding(.horizontal, 8).padding(.vertical, 4).foregroundStyle(HarborTheme.accent)
                                .background(HarborTheme.accent.opacity(0.12), in: .rect(cornerRadius: 6))
                        }
                        Text(DesktopInterfaceText.value("Trending, Popular, In Theaters, and the per service rails."))
                            .font(HarborTheme.font(15.5)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: 16) {
                            Circle().fill(preferences.tmdbKey.isEmpty ? ThemePreferences.shared.color("edge") : Color("metadata-key-saved")).frame(width: 8, height: 8)
                            Text(DesktopInterfaceText.value(preferences.tmdbKey.isEmpty ? "Not set" : "Saved")).font(HarborTheme.font(15.5)).foregroundStyle(.secondary)
                            Spacer(minLength: 0)
                            Button(DesktopInterfaceText.value(preferences.tmdbKey.isEmpty ? "Add key" : "Manage")) { editingKey = true }
                                .buttonStyle(HarborAccountButtonStyle()).accessibilityIdentifier("metadata-manage-key")
                        }
                    }.padding(16).background(HarborTheme.surface, in: .rect(cornerRadius: 10))
                        .overlay { RoundedRectangle(cornerRadius: 10).stroke(ThemePreferences.shared.color("edge-soft"), lineWidth: 1) }
                    if let error = preferences.error { Text(error).font(HarborTheme.font(13)).foregroundStyle(ThemePreferences.shared.color("danger")) }
                }
                HarborSettingsSection(DesktopInterfaceText.value("Region & language")) {
                    HarborSettingsChoice(DesktopInterfaceText.value("Region"), selection: $preferences.region, choices: countries.map { (Locale.current.localizedString(forRegionCode: $0) ?? $0, $0) })
                }
                HarborSettingsSection(DesktopInterfaceText.value("Titles and descriptions")) {
                    HarborSettingsChoice(DesktopInterfaceText.value("Metadata language"), selection: $preferences.language, choices: languages.map { (Locale.current.localizedString(forIdentifier: $0) ?? $0, $0) })
                    HarborSettingsToggle(DesktopInterfaceText.value("Translate titles"), note: DesktopInterfaceText.value("Show translated names in the language selected above. Turn off to keep original titles."), isOn: $preferences.translateTitles)
                }
            }
            .padding(20)
        }.background(HarborTheme.background).foregroundStyle(HarborTheme.ink)
            .navigationTitle(DesktopInterfaceText.value("Metadata providers")).navigationBarTitleDisplayMode(.inline)
            .accessibilityIdentifier("metadata-settings-scroll")
            .sheet(isPresented: $editingKey) { MetadataKeyEditor(preferences: preferences) }
    }
}

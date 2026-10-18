import SwiftUI

struct StreamingSettingsView: View {
    let app: AppModel
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text(DesktopInterfaceText.value("Pick what you actually use")).font(HarborTheme.displayFont(30)).accessibilityAddTraits(.isHeader)
                Text(DesktopInterfaceText.value("Harbor pulls the most popular titles each service has right now. Toggle off anything you don't subscribe to.")).foregroundStyle(.secondary)
                StreamingServicePicker(preferences: StreamingPreferences.forOwner(app.user?.id ?? "guest"))
                NavigationLink { StreamingServicesView(app: app) } label: {
                    Label(DesktopInterfaceText.value("Browse services"), systemImage: "square.grid.3x3").frame(minHeight: 44)
                }.buttonStyle(HarborAccountButtonStyle()).accessibilityIdentifier("streaming-browse-services")
                let cloud = ProfilePreferences.forOwner(app.user?.id ?? "guest").cloud
                if cloud.signedIn {
                    HarborSettingsSection(DesktopInterfaceText.value("Sync")) {
                        if let error = cloud.services.error ?? cloud.error { Text(DesktopInterfaceText.value(error)).font(.caption).foregroundStyle(.orange) }
                        if cloud.services.hasParkedVersion {
                            Text(DesktopInterfaceText.value("Another device changed services. Your previous version is saved on this device.")).font(.caption).foregroundStyle(.secondary)
                            Button(DesktopInterfaceText.value("Restore my version")) { cloud.services.restoreMyVersion() }
                                .buttonStyle(HarborAccountButtonStyle()).disabled(cloud.busy || cloud.services.hasPendingChanges || StreamingPreferences.forOwner(app.user?.id ?? "guest").cloudWritePending).accessibilityIdentifier("services-restore-version")
                        }
                        if cloud.services.hasPendingChanges { Text(DesktopInterfaceText.value("Services changes waiting to sync")).font(.caption).foregroundStyle(.secondary) }
                        Button(DesktopInterfaceText.value("Sync")) { Task { await cloud.sync() } }
                            .buttonStyle(HarborAccountButtonStyle()).disabled(cloud.busy).accessibilityIdentifier("services-sync-now")
                    }
                }
            }.padding(20)
        }.background(HarborTheme.background).foregroundStyle(HarborTheme.ink).navigationTitle(DesktopInterfaceText.value("Streaming services")).navigationBarTitleDisplayMode(.inline)
    }
}

struct StreamingServicePicker: View {
    let preferences: StreamingPreferences
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 8)], spacing: 8) {
                ForEach(StreamingServiceDefinition.all) { service in
                    let enabled = preferences.isEnabled(service.key)
                    let scope = preferences.scope
                    Button { preferences.setEnabled(!enabled, for: service.key, in: scope) } label: {
                        StreamingServiceLogo(service: service).frame(maxWidth: .infinity).frame(height: 72)
                            .opacity(enabled ? 1 : 0.55)
                            .background(enabled ? HarborTheme.surface : HarborTheme.background, in: .rect(cornerRadius: 12))
                            .overlay { RoundedRectangle(cornerRadius: 12).stroke(enabled ? HarborTheme.ink.opacity(0.5) : HarborTheme.ink.opacity(0.08), lineWidth: 1) }
                            .overlay(alignment: .topTrailing) {
                                if enabled { Image(systemName: "checkmark.circle.fill").font(.system(size: 14)).padding(6).foregroundStyle(HarborTheme.ink) }
                            }
                    }.buttonStyle(.plain).accessibilityLabel(service.name)
                        .accessibilityValue(DesktopInterfaceText.value(enabled ? "On" : "Off"))
                        .accessibilityAddTraits(enabled ? [.isSelected] : []).accessibilityIdentifier("streaming-" + service.key)
                }
            }.disabled(!preferences.ready || preferences.cloudWritePending).animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: preferences.signature)
            if let error = preferences.error {
                Text(DesktopInterfaceText.value(error)).font(.caption).foregroundStyle(.orange)
                if !preferences.ready { Button(DesktopInterfaceText.value("Retry")) { preferences.reload() } }
            }
            if MetadataPreferences.shared.tmdbKey.isEmpty {
                Text(DesktopInterfaceText.value("These rails activate once a TMDB key is set. You can come back to this anytime in Settings.")).font(.caption).foregroundStyle(.secondary)
            }
        }.accessibilityIdentifier("streaming-service-picker")
    }
}

struct StreamingServiceLogo: View {
    let service: StreamingServiceDefinition
    var height: CGFloat = 22
    var horizontalPadding: CGFloat = 12
    var body: some View {
        Image(service.asset).renderingMode(.template).resizable().scaledToFit()
            .frame(maxWidth: height * 5, maxHeight: CGFloat(service.logoHeight) * height / 22).padding(.horizontal, horizontalPadding).foregroundStyle(HarborTheme.ink).accessibilityHidden(true)
    }
}

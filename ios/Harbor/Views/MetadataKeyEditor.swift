import SwiftUI

struct MetadataKeyEditor: View {
    @Bindable var preferences: MetadataPreferences
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var key = ""
    @State private var revealed = false
    @State private var busy = false
    @State private var error: String?
    @State private var verification: Task<Void, Never>?
    @FocusState private var focused: Bool
    private var dirty: Bool { key.trimmingCharacters(in: .whitespacesAndNewlines) != preferences.tmdbKey }
    private var saved: Bool { !dirty && !preferences.tmdbKey.isEmpty }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                keyField
                actions
                if let error { Text(error).font(HarborTheme.font(13)).foregroundStyle(ThemePreferences.shared.color("danger")).fixedSize(horizontal: false, vertical: true) }
                Link("themoviedb.org/settings/api", destination: URL(string: "https://www.themoviedb.org/settings/api")!)
                    .font(HarborTheme.font(14)).underline().frame(minHeight: 44).tint(HarborTheme.ink)
            }.padding(20)
        }.background(HarborTheme.background).foregroundStyle(HarborTheme.ink).presentationDragIndicator(.visible)
            .accessibilityIdentifier("metadata-key-editor")
            .onAppear { key = preferences.tmdbKey }
            .onDisappear { verification?.cancel(); verification = nil }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(DesktopInterfaceText.value("TMDB · catalogs and rails")).font(HarborTheme.font(20, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button { dismiss() } label: {
                Image("episode-close").resizable().scaledToFit().frame(width: 18, height: 18).frame(width: 44, height: 44)
            }.buttonStyle(.plain).accessibilityLabel(DesktopInterfaceText.value("Close")).accessibilityIdentifier("metadata-key-close")
        }
    }

    private var keyField: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(DesktopInterfaceText.value("TMDB API key (v3)")).font(HarborTheme.font(14, weight: .semibold))
            HStack(spacing: 8) {
                Image("metadata-tmdb").resizable().scaledToFit().frame(width: 28, height: 28).accessibilityHidden(true)
                Group {
                    if revealed { TextField(DesktopInterfaceText.value("v3 API key"), text: $key) }
                    else { SecureField(DesktopInterfaceText.value("v3 API key"), text: $key) }
                }.font(HarborTheme.font(16.5)).textInputAutocapitalization(.never).autocorrectionDisabled()
                    .focused($focused).submitLabel(.done).onSubmit { save() }.disabled(busy).privacySensitive()
                    .accessibilityIdentifier("metadata-key-field")
                if !key.isEmpty {
                    Button { revealed.toggle() } label: {
                        Image(revealed ? "metadata-key-hide" : "metadata-key-show").resizable().scaledToFit()
                            .frame(width: 19, height: 19).frame(width: 44, height: 44)
                    }.buttonStyle(.plain).foregroundStyle(.secondary)
                        .accessibilityLabel(DesktopInterfaceText.value(revealed ? "Hide" : "Show"))
                        .accessibilityIdentifier("metadata-key-reveal")
                }
            }.padding(.horizontal, 12).frame(minHeight: 56)
                .background(HarborTheme.surface, in: .rect(cornerRadius: 10))
                .overlay { RoundedRectangle(cornerRadius: 10).stroke(ThemePreferences.shared.color(focused ? "edge" : "edge-soft"), lineWidth: 1) }
            Text(DesktopInterfaceText.value("Use the v3 key, not the read access token.")).font(HarborTheme.font(13)).foregroundStyle(.secondary)
        }
    }

    private var saveButton: some View {
        Button(action: save) {
            HStack(spacing: 8) {
                if saved { Image("metadata-key-check").resizable().scaledToFit().frame(width: 15, height: 15) }
                Text(DesktopInterfaceText.value(saved ? "Saved" : "Save"))
            }.font(HarborTheme.font(15, weight: .semibold)).padding(.horizontal, 16).frame(minHeight: 44)
                .foregroundStyle(saved ? HarborTheme.accent : HarborTheme.background)
                .background(saved ? HarborTheme.accent.opacity(0.12) : HarborTheme.ink, in: .rect(cornerRadius: 8))
        }.buttonStyle(.plain).disabled(busy || !dirty || key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityIdentifier("metadata-key-save")
    }

    private var actions: some View {
        HStack(spacing: 14) {
            saveButton
            if busy { HarborLoader(size: 44).frame(width: 44, height: 44) }
            Spacer(minLength: 0)
            if !preferences.tmdbKey.isEmpty {
                Button(DesktopInterfaceText.value("Remove"), role: .destructive, action: remove)
                    .font(HarborTheme.font(14, weight: .medium)).frame(minHeight: 44).disabled(busy)
                    .accessibilityIdentifier("metadata-key-remove")
            }
        }.animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: dirty)
    }

    private func save() {
        let candidate = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !busy, dirty, !candidate.isEmpty else { return }
        focused = false; busy = true; error = nil
        verification = Task { @MainActor in
            defer { busy = false; verification = nil }
            do {
                var configuration = preferences.configuration()
                configuration.tmdbKey = candidate
                let service = TMDBService()
                _ = try await service.page(service.definitions("movie")[0], page: 1, configuration: configuration)
                try Task.checkCancellation()
                try preferences.save(candidate)
                key = candidate
            } catch is CancellationError {} catch { self.error = safeMessage(error) }
        }
    }

    private func remove() {
        guard !busy else { return }
        do { try preferences.save(""); key = ""; error = nil } catch { self.error = safeMessage(error) }
    }
}

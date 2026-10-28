import SwiftUI
import UIKit

struct TraktSettingsView: View {
    @State private var model: TraktAccountModel
    private let library: LibraryModel?
    @State private var transfers: TraktLibraryModel?
    @State private var connecting = false
    @State private var disconnecting = false
    @AppStorage("cwSources") private var sources = ContinueWatchingSources.defaultValue
    @AppStorage("cwPerProfile") private var privateContinuing = false
    @MainActor init(app: AppModel) {
        let owner = app.personalOwner, scope = app.accountOperationScope
        self.init(model: TraktAccountModel(store: .forOwner(owner), active: { [weak app] in
            app?.personalOwner == owner && app?.accountOperationScope == scope && app?.storageReady == true
        }), library: app.library, transfers: TraktLibraryModel(app: app))
    }
    @MainActor init(model: TraktAccountModel, library: LibraryModel? = nil, transfers: TraktLibraryModel? = nil) {
        _model = State(initialValue: model); self.library = library; _transfers = State(initialValue: transfers)
    }
    private func text(_ value: String) -> String { DesktopInterfaceText.value(value) }
    private var progress: Binding<Bool> {
        .init(get: { ContinueWatchingSources(rawValue: sources).trakt }, set: { value in
            var next = ContinueWatchingSources(rawValue: sources); next.trakt = value; sources = next.rawValue
        })
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(spacing: 16) {
                    Image("tracker-trakt").resizable().scaledToFit().frame(width: 48, height: 48).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Trakt").font(HarborTheme.font(24, weight: .semibold))
                        Text(text(model.store.session == nil ? "Not connected" : "Connected")).foregroundStyle(.secondary).accessibilityIdentifier("trakt-connection-state")
                    }
                }
                if let session = model.store.session {
                    if let name = session.username { Text(name).font(HarborTheme.font(18, weight: .medium)).accessibilityIdentifier("trakt-account-name") }
                    Button(role: .destructive) { disconnecting = true } label: { Text(text("Disconnect")).frame(minHeight: 44) }
                        .buttonStyle(HarborAccountButtonStyle()).accessibilityIdentifier("trakt-disconnect")
                } else {
                    Button { connecting = true } label: { Text(text("Connect Trakt")).frame(maxWidth: .infinity, minHeight: 44) }
                        .buttonStyle(HarborAccountButtonStyle(primary: true)).disabled(!model.store.ready).accessibilityIdentifier("trakt-connect")
                }
                HarborSettingsToggle("Trakt progress", note: "Pulls what you have part-watched on Trakt into the row, marked with the Trakt logo. Requires a connected Trakt account.", isOn: progress)
                    .disabled(privateContinuing).accessibilityIdentifier("trakt-enable-progress")
                if privateContinuing {
                    Text(text("Unavailable while Continue Watching is kept private to each profile, because Trakt progress is shared across every profile on this account.")).font(.caption).foregroundStyle(.secondary)
                }
                if model.store.session != nil, let library, let transfers { TraktWatchlistTransferView(model: transfers, library: library) }
                Link(destination: URL(string: "https://trakt.tv")!) { Label("trakt.tv", systemImage: "arrow.up.right.square").frame(minHeight: 44) }.accessibilityIdentifier("trakt-website")
                if let error = model.error { Text(text(error)).foregroundStyle(.orange).accessibilityIdentifier("trakt-error") }
                if !model.store.ready { Button(text("Retry")) { model.load() }.frame(minHeight: 44).accessibilityIdentifier("trakt-reload") }
            }.padding(20).frame(maxWidth: 680, alignment: .leading).frame(maxWidth: .infinity, alignment: .leading)
        }.background(HarborTheme.background).foregroundStyle(HarborTheme.ink).navigationTitle("Trakt").navigationBarTitleDisplayMode(.inline)
            .accessibilityIdentifier("trakt-settings-scroll").task { model.load() }.onDisappear { model.cancel() }
            .sheet(isPresented: $connecting) { TraktDeviceAuthorizationView(model: model).presentationDetents([.medium, .large]).presentationDragIndicator(.visible) }
            .confirmationDialog(text("Disconnect"), isPresented: $disconnecting, titleVisibility: .visible) {
                Button(text("Disconnect"), role: .destructive) { model.disconnect() }; Button(text("Cancel"), role: .cancel) { }
            }
    }
}
struct TraktDeviceAuthorizationView: View {
    let model: TraktAccountModel
    @State private var copied = false
    @State private var attempt = UUID()
    @Environment(\.dismiss) private var dismiss
    private func text(_ value: String) -> String { DesktopInterfaceText.value(value) }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text(text(model.store.session == nil ? "Authorize Harbor on Trakt" : "Connected")).font(HarborTheme.font(22, weight: .semibold))
                    if model.store.session != nil {
                        Label(text("Connected"), systemImage: "checkmark.circle.fill").foregroundStyle(.green).accessibilityIdentifier("trakt-authorized")
                    } else if let pin = model.pin {
                        Text(text("Step 1 · Open Trakt")).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        Link(destination: pin.verificationURL) { Label("trakt.tv/activate", systemImage: "arrow.up.right.square").frame(maxWidth: .infinity, minHeight: 44, alignment: .leading) }.accessibilityIdentifier("trakt-authorize-link")
                        Text(text("Step 2 · Enter this code")).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        Button {
                            UIPasteboard.general.setItems([["public.utf8-plain-text": pin.userCode]], options: [.localOnly: true, .expirationDate: Date().addingTimeInterval(120)]); copied = true
                        } label: {
                            HStack {
                                Text(pin.userCode).font(.system(size: 27, weight: .semibold, design: .monospaced)).tracking(3).minimumScaleFactor(0.5).lineLimit(1)
                                Spacer(minLength: 12); Label(text(copied ? "Copied" : "Copy"), systemImage: copied ? "checkmark" : "doc.on.doc").font(.caption)
                            }.padding(16).frame(maxWidth: .infinity, minHeight: 64).background(HarborTheme.surface, in: .rect(cornerRadius: 12))
                        }.buttonStyle(.plain).accessibilityIdentifier("trakt-pin-code")
                        HStack(spacing: 10) { ProgressView(); Text(text("Waiting for you to authorize on trakt.tv…")).font(.callout).foregroundStyle(.secondary) }
                    } else if model.busy { ProgressView(text("Requesting code from Trakt…")).frame(maxWidth: .infinity, minHeight: 100) }
                    if let error = model.error {
                        Text(text(authorizationMessage(error))).foregroundStyle(.orange).accessibilityIdentifier("trakt-authorization-error")
                        Button(text("Try again")) { attempt = UUID() }.buttonStyle(HarborAccountButtonStyle(primary: true)).accessibilityIdentifier("trakt-retry")
                    }
                }.padding(22).frame(maxWidth: 680, alignment: .leading).frame(maxWidth: .infinity, alignment: .leading)
            }.background(HarborTheme.background).foregroundStyle(HarborTheme.ink).accessibilityIdentifier("trakt-authorization-scroll")
                .navigationTitle(text("Connect Trakt")).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button(text("Cancel")) { model.cancel(); dismiss() }.accessibilityIdentifier("trakt-cancel") } }
        }.task(id: attempt) { await model.begin() }
            .task(id: copied) { if copied { try? await Task.sleep(for: .milliseconds(1_400)); if !Task.isCancelled { copied = false } } }
            .task(id: model.store.session != nil) { if model.store.session != nil { try? await Task.sleep(for: .milliseconds(1_400)); if !Task.isCancelled { dismiss() } } }
            .onDisappear { model.cancel() }
    }
    private func authorizationMessage(_ value: String) -> String {
        switch value {
        case "Authorization was denied. Try again.": "Trakt reported that authorization was denied. Try again if this was unintentional."
        case "Code expired. Try again.": "The authorization code timed out before you finished. Try again."
        case "Could not connect to Trakt. Try again.": "Couldn't reach Trakt. Check your connection and try again."
        default: value
        }
    }
}

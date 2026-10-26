import SwiftUI
import UIKit

struct SimklSettingsView: View {
    @State private var model: SimklAccountModel
    @State private var connecting = false
    @State private var disconnecting = false
    @AppStorage("simklEnableUserRatings") private var ratings = true
    @AppStorage("simklScrobbleEnabled") private var scrobble = true
    @MainActor init(app: AppModel) {
        let owner = app.personalOwner, scope = app.accountOperationScope
        self.init(model: SimklAccountModel(store: SimklAccountStore.forOwner(owner), active: { [weak app] in
            app?.personalOwner == owner && app?.accountOperationScope == scope && app?.interfaceProfileScope != "unbound"
        }))
    }
    @MainActor init(model: SimklAccountModel) { _model = State(initialValue: model) }
    private func text(_ key: String) -> String { DesktopInterfaceText.value(key) }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(spacing: 16) {
                    Image("tracker-simkl").resizable().scaledToFit().frame(width: 48, height: 48).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Simkl").font(HarborTheme.font(24, weight: .semibold))
                        Text(text(model.store.session == nil ? "Not connected" : "Connected")).foregroundStyle(.secondary)
                            .accessibilityIdentifier("simkl-connection-state")
                    }
                }
                if let session = model.store.session {
                    if let name = session.username { Text(name).font(HarborTheme.font(18, weight: .medium)).accessibilityIdentifier("simkl-account-name") }
                    Toggle(text("Enable User Ratings"), isOn: $ratings).accessibilityIdentifier("simkl-enable-ratings")
                    Toggle(text("Scrobble to SIMKL"), isOn: $scrobble).accessibilityIdentifier("simkl-enable-scrobble")
                    Text(text("Automatically track what you are playing and save watch progress in real-time.")).font(.caption).foregroundStyle(.secondary)
                    Button(role: .destructive) { disconnecting = true } label: { Text(text("Disconnect")).frame(minHeight: 44) }
                        .buttonStyle(HarborAccountButtonStyle()).accessibilityIdentifier("simkl-disconnect")
                } else {
                    Button { connecting = true } label: { Text(text("Connect Simkl")).frame(maxWidth: .infinity, minHeight: 44) }
                        .buttonStyle(HarborAccountButtonStyle(primary: true)).disabled(!model.store.ready)
                        .accessibilityIdentifier("simkl-connect")
                }
                Link(destination: URL(string: "https://simkl.com")!) {
                    Label("simkl.com", systemImage: "arrow.up.right.square").frame(minHeight: 44)
                }.accessibilityIdentifier("simkl-website")
                if let error = model.error { Text(text(error)).foregroundStyle(.orange).accessibilityIdentifier("simkl-error") }
                if !model.store.ready { Button(text("Retry")) { model.load() }.frame(minHeight: 44).accessibilityIdentifier("simkl-reload") }
            }.padding(20).frame(maxWidth: 680, alignment: .leading).frame(maxWidth: .infinity, alignment: .leading)
        }.background(HarborTheme.background).foregroundStyle(HarborTheme.ink)
            .navigationTitle("Simkl").navigationBarTitleDisplayMode(.inline).accessibilityIdentifier("simkl-settings-scroll")
            .task { model.load() }
            .onDisappear { model.cancel() }
            .sheet(isPresented: $connecting) { SimklDeviceAuthorizationView(model: model).presentationDetents([.medium, .large]).presentationDragIndicator(.visible) }
            .confirmationDialog(text("Disconnect"), isPresented: $disconnecting, titleVisibility: .visible) {
                Button(text("Disconnect"), role: .destructive) {
                    model.disconnect()
                    if model.store.session == nil {
                        ratings = true
                        scrobble = true
                        try? SimklPendingWatches.forOwner(model.store.owner).bind(nil)
                        let library = SimklLibraryStore.forOwner(model.store.owner); library.bind(nil)
                        Task { try? await library.clear() }
                    }
                }
                Button(text("Cancel"), role: .cancel) { }
            }
    }
}

private struct SimklDeviceAuthorizationView: View {
    let model: SimklAccountModel
    @State private var copied = false
    @State private var attempt = UUID()
    @Environment(\.dismiss) private var dismiss
    private func text(_ key: String) -> String { DesktopInterfaceText.value(key) }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text(text(model.store.session == nil ? "Authorize Harbor on Simkl" : "Connected")).font(HarborTheme.font(22, weight: .semibold))
                    if model.store.session != nil {
                        Label(text("Connected to Simkl"), systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                            .accessibilityIdentifier("simkl-authorized")
                    } else if let pin = model.pin {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(text("Step 1 · Open Simkl")).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            Link(destination: pin.verificationURL) { Label("https://simkl.com/pin", systemImage: "arrow.up.right.square").frame(maxWidth: .infinity, minHeight: 44, alignment: .leading) }
                                .accessibilityIdentifier("simkl-authorize-link")
                        }
                        VStack(alignment: .leading, spacing: 10) {
                            Text(text("Step 2 · Enter this code")).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            Button {
                                UIPasteboard.general.setItems([["public.utf8-plain-text": pin.userCode]], options: [.localOnly: true, .expirationDate: Date().addingTimeInterval(120)])
                                copied = true
                            } label: {
                                HStack {
                                    Text(pin.userCode).font(.system(size: 27, weight: .semibold, design: .monospaced)).tracking(3).minimumScaleFactor(0.5).lineLimit(1)
                                    Spacer(minLength: 12); Label(text(copied ? "Copied" : "Copy"), systemImage: copied ? "checkmark" : "doc.on.doc").font(.caption)
                                }.padding(16).frame(maxWidth: .infinity, minHeight: 64).background(HarborTheme.surface, in: .rect(cornerRadius: 12))
                            }.buttonStyle(.plain).accessibilityIdentifier("simkl-pin-code")
                        }
                        HStack(spacing: 10) { ProgressView(); Text(text("Waiting for you to authorize on simkl.com…")).font(.callout).foregroundStyle(.secondary) }
                    } else if model.busy { ProgressView(text("Requesting code from Simkl…")).frame(maxWidth: .infinity, minHeight: 100) }
                    if let error = model.error {
                        Text(text(error)).foregroundStyle(.orange).accessibilityIdentifier("simkl-authorization-error")
                        Button(text("Try again")) { attempt = UUID() }.buttonStyle(HarborAccountButtonStyle(primary: true)).accessibilityIdentifier("simkl-retry")
                    }
                }.padding(22).frame(maxWidth: 680, alignment: .leading).frame(maxWidth: .infinity, alignment: .leading)
            }.background(HarborTheme.background).foregroundStyle(HarborTheme.ink).accessibilityIdentifier("simkl-authorization-scroll")
                .navigationTitle(text("Connect Simkl")).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button(text("Cancel")) { model.cancel(); dismiss() }.accessibilityIdentifier("simkl-cancel") } }
        }.task(id: attempt) { await model.begin() }
            .task(id: copied) { if copied { try? await Task.sleep(for: .milliseconds(1_400)); if !Task.isCancelled { copied = false } } }
            .task(id: model.store.session != nil) {
                if model.store.session != nil { try? await Task.sleep(for: .milliseconds(1_400)); if !Task.isCancelled { dismiss() } }
            }
            .onDisappear { model.cancel() }
    }
}

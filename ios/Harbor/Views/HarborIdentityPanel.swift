import SwiftUI

struct HarborIdentityPanel: View {
    let profile: ProfilePreferences
    @State private var username = ""
    @State private var password = ""
    @FocusState private var editing: Bool
    private var cloud: HarborProfileSync { profile.cloud }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Harbor account").font(HarborTheme.font(22, weight: .semibold))
            if cloud.signedIn {
                HStack(spacing: 14) { ProfileAvatar(profile: profile, size: 64); VStack(alignment: .leading, spacing: 6) { Text(profile.value.name).font(HarborTheme.font(17, weight: .semibold)); if let handle = cloud.handle { Text("@" + handle).font(HarborTheme.font(14)).foregroundStyle(.secondary) } } }
                Button("Sincronizar") { Task { await cloud.sync() } }.buttonStyle(HarborAccountButtonStyle())
                Button("Cerrar sesión", role: .destructive) { Task { await cloud.signOut() } }
            } else {
                TextField("Username", text: $username).textContentType(.username).textInputAutocapitalization(.never).autocorrectionDisabled().focused($editing)
                    .padding(13).background(HarborTheme.surface, in: .rect(cornerRadius: 10)).accessibilityIdentifier("harbor-username").disabled(!cloud.ready)
                SecureField("Password", text: $password).textContentType(.password).focused($editing)
                    .padding(13).background(HarborTheme.surface, in: .rect(cornerRadius: 10)).accessibilityIdentifier("harbor-password").disabled(!cloud.ready)
                Button("Sign in") {
                    editing = false; let secret = password; password = ""
                    Task { await cloud.signIn(username: username, password: secret) }
                }.buttonStyle(HarborAccountButtonStyle(primary: true)).disabled(!cloud.ready || username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || password.isEmpty)
                    .accessibilityIdentifier("harbor-login")
            }
            if cloud.busy { ProgressView() }
            if let error = cloud.error { Text(error).font(HarborTheme.font(13)).foregroundStyle(.orange) }
            if !cloud.ready { Button("Reintentar") { cloud.reload() } }
        }.disabled(cloud.busy).onDisappear { password = "" }
    }
}

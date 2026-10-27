import SwiftUI

struct HarborIdentityPanel: View {
    let profile: ProfilePreferences
    let cloud: HarborProfileSync
    @State private var username = ""
    @State private var password = ""
    @State private var customServer = false
    @State private var serverURL = ""
    private enum Field: Hashable { case username, password, server }
    @FocusState private var editing: Field?
    private var selectedServer: HarborIdentityServer? {
        if customServer { return try? HarborIdentityServer(serverURL) }
        return .community
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(DesktopInterfaceText.value("Harbor account")).font(HarborTheme.font(22, weight: .semibold))
            if cloud.signedIn {
                HStack(spacing: 14) { ProfileAvatar(profile: profile, size: 64); VStack(alignment: .leading, spacing: 6) { Text(profile.value.name).font(HarborTheme.font(17, weight: .semibold)); if let handle = cloud.handle { Text("@" + handle).font(HarborTheme.font(14)).foregroundStyle(.secondary) } } }
                if let server = cloud.server { Text(server.host).font(HarborTheme.font(13)).foregroundStyle(.secondary).accessibilityIdentifier("harbor-connected-server") }
                if cloud.serverRetired {
                    Text(HarborError(code: "harbor-server-retired").localizedDescription).font(HarborTheme.font(13)).foregroundStyle(.orange)
                } else {
                    Button("Sincronizar") { Task { await cloud.sync() } }.buttonStyle(HarborAccountButtonStyle())
                }
                Button("Cerrar sesión", role: .destructive) { Task { await cloud.signOut() } }.accessibilityIdentifier("harbor-signout")
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Picker("Servidor", selection: $customServer) {
                        Text("Harbor Community").tag(false)
                        Text("Personalizado").tag(true)
                    }.pickerStyle(.segmented).accessibilityIdentifier("harbor-server-choice")
                    if customServer {
                        TextField("https://servidor.example", text: $serverURL).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                            .focused($editing, equals: .server)
                            .padding(13).background(HarborTheme.surface, in: .rect(cornerRadius: 10)).accessibilityIdentifier("harbor-server-url")
                    } else {
                        Text(HarborIdentityServer.community.host).font(HarborTheme.font(13)).foregroundStyle(.secondary)
                    }
                    Text(LocalProfileText.value(.serverAccount))
                        .font(HarborTheme.font(13)).foregroundStyle(.secondary)
                        .accessibilityIdentifier("harbor-server-note")
                }
                TextField(DesktopInterfaceText.value("Username"), text: $username).textContentType(.username).textInputAutocapitalization(.never).autocorrectionDisabled().focused($editing, equals: .username)
                    .padding(13).background(HarborTheme.surface, in: .rect(cornerRadius: 10)).accessibilityIdentifier("harbor-username").disabled(!cloud.ready)
                SecureField(DesktopInterfaceText.value("Password"), text: $password).textContentType(.password).focused($editing, equals: .password)
                    .padding(13).background(HarborTheme.surface, in: .rect(cornerRadius: 10)).accessibilityIdentifier("harbor-password").disabled(!cloud.ready)
                Button(DesktopInterfaceText.value("Sign in")) {
                    guard let server = selectedServer else { return }
                    editing = nil; let secret = password; password = ""
                    Task { await cloud.signIn(username: username, password: secret, server: server) }
                }.buttonStyle(HarborAccountButtonStyle(primary: true)).disabled(!cloud.ready || selectedServer == nil || selectedServer?.retired == true || username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || password.isEmpty)
                    .accessibilityIdentifier("harbor-login")
            }
            if cloud.busy { ProgressView() }
            if let error = cloud.error { Text(error).font(HarborTheme.font(13)).foregroundStyle(.orange) }
            if !cloud.ready { Button("Reintentar") { cloud.reload() } }
        }.disabled(cloud.busy).onChange(of: customServer) { _, _ in editing = nil; password = "" }
            .onChange(of: serverURL) { _, _ in password = "" }.onDisappear { password = "" }
    }
}

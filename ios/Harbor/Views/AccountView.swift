import SwiftUI

struct AccountView: View {
    let app: AppModel
    @State private var email = ""
    @State private var password = ""
    @State private var error: String?
    @State private var browserBusy = false
    @State private var web = StremioWebLogin()
    @FocusState private var editing: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            if let user = app.user {
                Section("Tu cuenta") {
                    Text(user.displayName).accessibilityIdentifier("account-user")
                    Text("\(app.addons.count) addons recuperados")
                    Button("Sincronizar addons") {
                        Task {
                            error = nil
                            do { try await app.syncAccount() } catch { self.error = safeMessage(error) }
                        }
                    }.accessibilityIdentifier("account-sync")
                    Button("Cerrar sesión", role: .destructive) {
                        Task {
                            error = nil
                            do { try await app.signOut() } catch { self.error = safeMessage(error) }
                        }
                    }.accessibilityIdentifier("account-signout")
                }
            } else {
                Section {
                    Text("Usa la misma cuenta de Stremio que utilizas en Harbor. Tus addons configurados se recuperarán al iniciar sesión.")
                    Button("Iniciar sesión con Stremio") {
                        editing = false
                        Task {
                            browserBusy = true; error = nil
                            defer { browserBusy = false }
                            do {
                                let key = try await web.start()
                                try await app.signIn(authKey: key)
                                dismiss()
                            }
                            catch let failure as HarborError where failure.code == "account-cancelled" { }
                            catch { self.error = safeMessage(error) }
                        }
                    }.accessibilityIdentifier("account-browser-login")
                    Text("Acceso oficial con correo, Apple o Facebook.").font(.caption).foregroundStyle(.secondary)
                }
                Section("Correo y contraseña") {
                    TextField("Correo de Stremio", text: $email).keyboardType(.emailAddress)
                        .textContentType(.username).textInputAutocapitalization(.never).autocorrectionDisabled()
                        .focused($editing).accessibilityIdentifier("account-email")
                    SecureField("Contraseña", text: $password).textContentType(.password)
                        .focused($editing).accessibilityIdentifier("account-password")
                    Button("Iniciar sesión") {
                        editing = false
                        let suppliedPassword = password
                        password = ""
                        Task {
                            error = nil
                            do { try await app.signIn(email: email, password: suppliedPassword); dismiss() }
                            catch { self.error = safeMessage(error) }
                        }
                    }.disabled(email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || password.isEmpty)
                        .accessibilityIdentifier("account-login")
                }
            }
            if app.accountBusy || browserBusy { ProgressView("Recuperando tu cuenta…") }
            if let error = error ?? app.accountError { Text(error).foregroundStyle(.orange).accessibilityIdentifier("account-error") }
        }
        .disabled(app.accountBusy || browserBusy)
        .navigationTitle(app.user == nil ? "Iniciar sesión" : "Cuenta")
        .toolbar { Button("Cerrar") { dismiss() } }
        .onDisappear { password = ""; web.cancel() }
    }
}

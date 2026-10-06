import SwiftUI
import PhotosUI

struct ProfileAccountButton: View {
    let app: AppModel
    var expanded = false
    var body: some View {
        let profile = ProfilePreferences.forOwner(app.user?.id ?? "guest")
        Button { app.showAccount = true } label: {
            HStack(spacing: 10) {
                ProfileAvatar(profile: profile, size: expanded ? 38 : 28)
                if expanded {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(profile.value.name.isEmpty ? app.user?.displayName ?? "Invitado" : profile.value.name).font(.caption.bold()).lineLimit(1)
                        Text(app.user == nil ? "Perfil de este iPhone" : "Sesión iniciada en Stremio").font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }.frame(minHeight: 44)
        }.buttonStyle(.plain).accessibilityLabel("Cuenta")
    }
}

struct ProfileEditor: View {
    let user: AccountUser?
    let profile: ProfilePreferences
    @State private var name = ""
    @State private var chosenPhoto: PhotosPickerItem?
    @State private var avatars = false
    @State private var photoError: String?
    private var displayedName: String { profile.value.name.isEmpty ? user?.displayName ?? "Invitado" : profile.value.name }
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("Tu perfil").font(.title3.bold())
            Text("Tu avatar, nombre y color en este iPhone.").font(.subheadline).foregroundStyle(.secondary)
            HStack(spacing: 18) {
                ProfileAvatar(profile: profile)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Nombre visible").font(.caption).foregroundStyle(.secondary)
                    TextField("Nombre", text: $name).padding(13).background(HarborTheme.surface, in: .rect(cornerRadius: 10)).accessibilityIdentifier("profile-name")
                }
            }
            Button("Guardar nombre") { profile.update { $0.name = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80)) } }.buttonStyle(.bordered).disabled(!profile.ready)
            Divider()
            Label("Avatar", systemImage: "photo").font(.headline)
            Text("Sube una foto o elige uno del catálogo original de Harbor.").font(.subheadline).foregroundStyle(.secondary)
            HStack(spacing: 12) {
                PhotosPicker(selection: $chosenPhoto, matching: .images) { Text("Subir foto").font(.subheadline).padding(12).background(HarborTheme.surface, in: .rect(cornerRadius: 9)) }
                Button { avatars = true } label: {
                    HStack(spacing: -7) { ForEach(DesktopAvatar.catalog.prefix(5)) { Image($0.asset).resizable().scaledToFill().frame(width: 29, height: 29).clipShape(.circle).overlay { Circle().stroke(HarborTheme.background, lineWidth: 2) } } }
                    Text("\(DesktopAvatar.catalog.count)").font(.caption2).padding(4).background(HarborTheme.surface, in: .capsule)
                }.accessibilityLabel("Elegir avatar de Harbor")
            }.disabled(!profile.ready)
            if profile.value.photo != nil { Button("Usar mi avatar de Harbor") { profile.update { $0.photo = nil } }.font(.caption) }
            Divider()
            Label("Tu color", systemImage: "paintpalette").font(.headline)
            Text("Colorea el anillo de tu avatar.").font(.subheadline).foregroundStyle(.secondary)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 14) {
                ForEach(ProfilePreferences.colors, id: \.self) { hex in
                    Button { profile.update { $0.color = hex } } label: {
                        Circle().fill(ProfilePreferences.color(hex)).frame(width: 34, height: 34).overlay { if profile.value.color == hex { Image(systemName: "checkmark").font(.caption.bold()).foregroundStyle(.black) } }.frame(minWidth: 44, minHeight: 44)
                    }.buttonStyle(.plain).accessibilityLabel("Color \(hex)").accessibilityAddTraits(profile.value.color == hex ? [.isSelected] : [])
                }
            }.disabled(!profile.ready)
            ColorPicker("Personalizado", selection: Binding(get: { profile.color }, set: { profile.setColor($0) }), supportsOpacity: false).disabled(!profile.ready)
            if let error = profile.error ?? photoError { Text(error).font(.caption).foregroundStyle(.orange) }
            if !profile.ready { Button("Recuperar perfil") { profile.reload() } }
        }.onAppear { name = displayedName }
            .task(id: chosenPhoto) {
                guard let chosenPhoto else { return }
                do {
                    guard let data = try await chosenPhoto.loadTransferable(type: Data.self) else { throw HarborError(code: "profile-photo") }
                    try Task.checkCancellation(); try profile.setPhoto(data); photoError = nil
                } catch is CancellationError { return }
                catch { photoError = "No se pudo abrir esta foto. Prueba con otra imagen." }
            }
            .sheet(isPresented: $avatars) {
                NavigationStack {
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 64))], spacing: 15) {
                            ForEach(DesktopAvatar.catalog) { avatar in
                                Button { profile.update { $0.avatar = avatar.id; $0.photo = nil }; avatars = false } label: { Image(avatar.asset).resizable().scaledToFill().frame(width: 64, height: 64).clipShape(.circle).overlay { Circle().stroke(profile.value.avatar == avatar.id ? profile.color : .clear, lineWidth: 3) } }.accessibilityLabel(avatar.name)
                            }
                        }.padding()
                    }.background(HarborTheme.background).navigationTitle("Avatares de Harbor").toolbar { Button("Cerrar") { avatars = false } }
                }
            }
    }
}

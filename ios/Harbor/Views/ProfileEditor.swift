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
                        Text(profile.value.name.isEmpty ? app.user?.displayName ?? "Invitado" : profile.value.name).font(HarborTheme.font(13, weight: .semibold)).lineLimit(1)
                        Text(app.user == nil ? "Perfil de este iPhone" : "Sesión iniciada en Stremio").font(HarborTheme.font(11)).foregroundStyle(.secondary)
                    }
                }
            }.frame(minHeight: 44)
        }.buttonStyle(.plain).accessibilityLabel("Cuenta").accessibilityIdentifier("main-account")
    }
}

struct ProfileEditor: View {
    let user: AccountUser?
    let profile: ProfilePreferences
    @State private var name = ""
    @State private var chosenPhoto: PhotosPickerItem?
    @State private var avatars = false
    @State private var photoError: String?
    @State private var previousName = ""
    @FocusState private var editingName: Bool
    private var cloud: HarborProfileSync { profile.cloud }
    private var editable: Bool { profile.ready && (!cloud.signedIn || cloud.hydrated) && !cloud.busy }
    private var displayedName: String { profile.value.name.isEmpty ? user?.displayName ?? "Invitado" : profile.value.name }
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("Tu perfil").font(HarborTheme.font(20, weight: .semibold)).accessibilityAddTraits(.isHeader)
            Text("Tu avatar, nombre e identificador en Harbor.").font(HarborTheme.font(15)).foregroundStyle(.secondary)
            HStack(spacing: 18) {
                ProfileAvatar(profile: profile, size: 88)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Nombre para mostrar").font(HarborTheme.font(15)).foregroundStyle(.secondary)
                    TextField("Nombre", text: $name).textFieldStyle(.plain).font(HarborTheme.font(17, weight: .medium))
                        .padding(.horizontal, 12).frame(minHeight: 48).background(HarborTheme.surface, in: .rect(cornerRadius: 10))
                        .overlay { RoundedRectangle(cornerRadius: 10).stroke(HarborTheme.ink.opacity(0.06), lineWidth: 1) }
                        .accessibilityIdentifier("profile-name")
                        .focused($editingName).onSubmit { saveName() }.disabled(!editable)
                }
            }
            if let handle = cloud.handle { Text("@" + handle).font(HarborTheme.font(14)).foregroundStyle(.secondary) }
            if name.trimmingCharacters(in: .whitespacesAndNewlines) != displayedName { Button("Guardar"){ saveName() }.buttonStyle(HarborAccountButtonStyle()).disabled(!editable) }
            Divider()
            profileLabel("Avatar", icon: "desktop-image")
            Text("Sube una imagen tuya o elige una del catálogo de Harbor.").font(HarborTheme.font(15)).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 12) {
                PhotosPicker(selection: $chosenPhoto, matching: .images) { Text("Subir foto") }.buttonStyle(HarborAccountButtonStyle())
                avatarFan
            }.disabled(!editable)
            if profile.value.photo != nil { Button("Usar mi avatar de Harbor") { profile.update { $0.photo = nil; $0.remoteAvatar = nil; $0.initialsAvatar = false } }.font(HarborTheme.font(13)).disabled(!editable) }
            Divider()
            profileLabel("Tu color", icon: "desktop-palette")
            Text("Da color a tu nombre, al cursor en Ver juntos y al anillo alrededor de tu avatar.").font(HarborTheme.font(15)).foregroundStyle(.secondary)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 14) {
                ForEach(ProfilePreferences.colors, id: \.self) { hex in
                    Button { profile.update { $0.color = hex } } label: {
                        Circle().fill(ProfilePreferences.color(hex)).frame(width: 32, height: 32).overlay {
                            if profile.value.color == hex {
                                Image("music-check").resizable().scaledToFit().frame(width: 13, height: 13).foregroundStyle(.black)
                                    .frame(width: 18, height: 18).background(.white, in: .circle).accessibilityHidden(true)
                            }
                        }.frame(minWidth: 44, minHeight: 44)
                    }.buttonStyle(.plain).accessibilityLabel("Color \(hex)").accessibilityAddTraits(profile.value.color == hex ? [.isSelected] : [])
                }
            }.disabled(!editable)
            ColorPicker("Personalizado", selection: Binding(get: { profile.color }, set: { profile.setColor($0) }), supportsOpacity: false).font(HarborTheme.font(14, weight: .medium)).disabled(!editable)
            if cloud.busy { ProgressView() }
            if let error = profile.error ?? photoError ?? cloud.error { Text(error).font(HarborTheme.font(13)).foregroundStyle(.orange) }
            if cloud.signedIn { Button("Sincronizar") { Task { await cloud.sync() } }.buttonStyle(HarborAccountButtonStyle()).disabled(cloud.busy) }
            if !profile.ready { Button("Recuperar perfil") { profile.reload() } }
        }.onAppear { name = displayedName; previousName = displayedName }
            .onChange(of: displayedName) { _, value in if !editingName || name == previousName { name = value }; previousName = value }
            .onChange(of: editingName) { before, after in if before && !after { saveName() } }
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
                                Button { profile.update { $0.avatar = avatar.id; $0.photo = nil; $0.remoteAvatar = nil; $0.initialsAvatar = false }; avatars = false } label: { Image(avatar.asset).resizable().scaledToFill().frame(width: 64, height: 64).clipShape(.circle).overlay { Circle().stroke(profile.value.avatar == avatar.id ? profile.color : .clear, lineWidth: 3) } }.accessibilityLabel(avatar.name).disabled(!editable)
                            }
                        }.padding()
                    }.background(HarborTheme.background).navigationTitle("Avatares de Harbor").toolbar { Button("Cerrar") { avatars = false } }
                }.font(HarborTheme.font()).foregroundStyle(HarborTheme.ink).tint(HarborTheme.accent).preferredColorScheme(.dark)
            }
    }
    private func saveName() {
        guard editable else { return }
        let next = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(32))
        guard !next.isEmpty, next != displayedName else { return }
        profile.update { $0.name = next }; name = next
    }

    private func profileLabel(_ title: String, icon: String) -> some View {
        HStack(spacing: 12) {
            Image(icon).resizable().scaledToFit().frame(width: 18, height: 18).foregroundStyle(.secondary).accessibilityHidden(true)
            Text(title).font(HarborTheme.font(16, weight: .semibold))
        }
    }

    private var avatarFan: some View {
        HStack(spacing: 0) {
            Button { avatars = true } label: {
                HStack(spacing: 12) {
                    HStack(spacing: -12) {
                        ForEach(Array(DesktopAvatar.catalog.prefix(5).enumerated()), id: \.element.id) { index, avatar in
                            Image(avatar.asset).resizable().scaledToFill().frame(width: 36, height: 36).clipShape(.circle)
                                .overlay { Circle().stroke(HarborTheme.background, lineWidth: 2) }
                                .overlay(alignment: .bottomTrailing) {
                                    if index == min(4, DesktopAvatar.catalog.count - 1) {
                                        Text("\(DesktopAvatar.catalog.count)").font(HarborTheme.font(9, weight: .bold)).foregroundStyle(.black)
                                            .padding(.horizontal, 5).padding(.vertical, 2).background(.white, in: .capsule).offset(x: 4, y: 4)
                                    }
                                }
                        }
                    }.accessibilityHidden(true)
                    Text("o usa uno de nuestros avatares").font(HarborTheme.font(15, weight: .medium)).foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }.padding(.horizontal, 10).padding(.vertical, 8).frame(minHeight: 52).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel("Elegir avatar de Harbor")
            Button {
                guard let avatar = DesktopAvatar.catalog.randomElement() else { return }
                profile.update { $0.avatar = avatar.id; $0.photo = nil; $0.remoteAvatar = nil; $0.initialsAvatar = false }
            } label: {
                Image("music-shuffle").resizable().scaledToFit().frame(width: 15, height: 15)
                    .foregroundStyle(.secondary).frame(width: 44, height: 52).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel("Avatar aleatorio")
                .overlay(alignment: .leading) { Rectangle().fill(HarborTheme.ink.opacity(0.06)).frame(width: 1) }
        }.overlay { RoundedRectangle(cornerRadius: 12).stroke(HarborTheme.ink.opacity(0.06), lineWidth: 1) }
    }
}

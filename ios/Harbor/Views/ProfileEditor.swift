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
                        if app.user != nil { Text(DesktopInterfaceText.value("profile.signedIn")).font(HarborTheme.font(11)).foregroundStyle(.secondary) }
                    }
                }
            }.frame(minHeight: 44)
        }.buttonStyle(.plain).accessibilityLabel(DesktopInterfaceText.value("Account")).accessibilityIdentifier("main-account")
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
    @State private var fanAvatars = Array(DesktopAvatar.catalog.shuffled().prefix(5))
    @State private var avatarQuery = ""
    @State private var avatarGroup = ""
    @FocusState private var editingName: Bool
    private var cloud: HarborProfileSync { profile.cloud }
    private var editable: Bool { profile.ready && (!cloud.signedIn || cloud.hydrated) && !cloud.busy }
    private var displayedName: String { profile.value.name.isEmpty ? user?.displayName ?? "Invitado" : profile.value.name }
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text(DesktopInterfaceText.value("Your profile")).font(HarborTheme.font(20, weight: .semibold)).accessibilityAddTraits(.isHeader)
            Text(DesktopInterfaceText.value("Your avatar, name, and handle across Harbor.")).font(HarborTheme.font(15)).foregroundStyle(.secondary)
            HStack(spacing: 18) {
                ProfileAvatar(profile: profile, size: 88)
                VStack(alignment: .leading, spacing: 8) {
                    Text(DesktopInterfaceText.value("Display name")).font(HarborTheme.font(15)).foregroundStyle(.secondary)
                    TextField(DesktopInterfaceText.value("Name"), text: $name).textFieldStyle(.plain).font(HarborTheme.font(17, weight: .medium))
                        .padding(.horizontal, 12).frame(minHeight: 48).background(HarborTheme.surface, in: .rect(cornerRadius: 10))
                        .overlay { RoundedRectangle(cornerRadius: 10).stroke(HarborTheme.ink.opacity(0.06), lineWidth: 1) }
                        .accessibilityIdentifier("profile-name")
                        .focused($editingName).onSubmit { saveName() }.disabled(!editable)
                }
            }
            if let handle = cloud.handle { Text("@" + handle).font(HarborTheme.font(14)).foregroundStyle(.secondary) }
            if name.trimmingCharacters(in: .whitespacesAndNewlines) != displayedName { Button(DesktopInterfaceText.value("Save")){ saveName() }.buttonStyle(HarborAccountButtonStyle()).disabled(!editable) }
            Divider()
            profileLabel("Avatar", icon: "profile-upload-plus")
            Text(DesktopInterfaceText.value("Upload a picture of your own, or pick one from the Harbor catalog.")).font(HarborTheme.font(15)).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 12) {
                PhotosPicker(selection: $chosenPhoto, matching: .images) { Text(DesktopInterfaceText.value("Upload photo")) }.buttonStyle(HarborAccountButtonStyle())
                avatarFan
            }.disabled(!editable)
            if profile.value.photo != nil { Button(DesktopInterfaceText.value("Reset to default")) { profile.update { $0.avatar = "harbor_animal_01"; $0.photo = nil; $0.remoteAvatar = nil; $0.initialsAvatar = false } }.font(HarborTheme.font(13)).disabled(!editable) }
            Divider()
            profileLabel("Your color", icon: "desktop-palette")
            Text(DesktopInterfaceText.value("Colors your name, your cursor in Watch Together, and the ring around your avatar.")).font(HarborTheme.font(15)).foregroundStyle(.secondary)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 14) {
                ForEach(ProfilePreferences.colors, id: \.self) { hex in
                    Button { profile.update { $0.color = hex } } label: {
                        Circle().fill(ProfilePreferences.color(hex)).frame(width: 32, height: 32).overlay {
                            if profile.value.color == hex {
                                Image("profile-preset-check").resizable().scaledToFit().frame(width: 13, height: 13).foregroundStyle(.black)
                                    .frame(width: 18, height: 18).background(.white, in: .circle).accessibilityHidden(true)
                            }
                        }.frame(minWidth: 44, minHeight: 44)
                    }.buttonStyle(.plain).accessibilityLabel("Color \(hex)").accessibilityAddTraits(profile.value.color == hex ? [.isSelected] : [])
                }
            }.disabled(!editable)
            ColorPicker(DesktopInterfaceText.value("Custom"), selection: Binding(get: { profile.color }, set: { profile.setColor($0) }), supportsOpacity: false).font(HarborTheme.font(14, weight: .medium)).disabled(!editable)
            if cloud.busy { ProgressView() }
            if let error = profile.error ?? photoError ?? cloud.error { Text(error).font(HarborTheme.font(13)).foregroundStyle(.orange) }
            if cloud.signedIn { Button(DesktopInterfaceText.value("Sync")) { Task { await cloud.sync() } }.buttonStyle(HarborAccountButtonStyle()).disabled(cloud.busy) }
            if !profile.ready { Button(DesktopInterfaceText.value("Retry")) { profile.reload() } }
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
                    avatarGallery
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
            Text(DesktopInterfaceText.value(title)).font(HarborTheme.font(16, weight: .semibold))
        }
    }

    private var avatarFan: some View {
        HStack(spacing: 0) {
            Button { avatars = true } label: {
                HStack(spacing: 12) {
                    HStack(spacing: -12) {
                        ForEach(Array(fanAvatars.enumerated()), id: \.element.id) { index, avatar in
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
                    Text(DesktopInterfaceText.value("or use one of our avatars")).font(HarborTheme.font(15, weight: .medium)).foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }.padding(.horizontal, 10).padding(.vertical, 8).frame(minHeight: 52).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel(DesktopInterfaceText.value("Choose an avatar")).accessibilityIdentifier("profile-avatar-picker")
            Button {
                guard let avatar = DesktopAvatar.catalog.randomElement() else { return }
                profile.update { $0.avatar = avatar.id; $0.photo = nil; $0.remoteAvatar = nil; $0.initialsAvatar = false }
            } label: {
                Image("profile-avatar-shuffle").resizable().scaledToFit().frame(width: 15, height: 15)
                    .foregroundStyle(.secondary).frame(width: 44, height: 52).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel(DesktopInterfaceText.value("Random avatar"))
                .overlay(alignment: .leading) { Rectangle().fill(HarborTheme.ink.opacity(0.06)).frame(width: 1) }
        }.overlay { RoundedRectangle(cornerRadius: 12).stroke(HarborTheme.ink.opacity(0.06), lineWidth: 1) }
    }

    private var matchingAvatars: [DesktopAvatar] {
        let query = avatarQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        return DesktopAvatar.catalog.filter { avatar in
            (avatarGroup.isEmpty || avatar.group == avatarGroup) && (query.isEmpty || avatar.name.localizedCaseInsensitiveContains(query))
        }
    }
    private var avatarGallery: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                HarborSearchField(prompt: DesktopInterfaceText.value("Search"), text: $avatarQuery).accessibilityIdentifier("profile-avatar-search")
                ScrollView(.horizontal) {
                    HStack(spacing: 6) {
                        HarborPill(title: DesktopInterfaceText.value("All"), selected: avatarGroup.isEmpty) { avatarGroup = "" }
                        ForEach(DesktopAvatar.groups, id: \.self) { group in
                            HarborPill(title: DesktopInterfaceText.value(group), selected: avatarGroup == group) { avatarGroup = group; avatarQuery = "" }
                        }
                    }
                }.scrollIndicators(.hidden)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 84))], spacing: 16) {
                    ForEach(matchingAvatars) { avatar in
                        Button { profile.update { $0.avatar = avatar.id; $0.photo = nil; $0.remoteAvatar = nil; $0.initialsAvatar = false }; avatars = false } label: {
                            HarborAvatarTile(avatar: avatar, selected: profile.value.photo == nil && profile.value.avatar == avatar.id)
                        }.buttonStyle(HarborAvatarPressStyle()).accessibilityLabel(avatar.name).disabled(!editable).accessibilityIdentifier("profile-avatar-choice")
                    }
                }
                if matchingAvatars.isEmpty { Text(DesktopInterfaceText.value("No matches.")).font(HarborTheme.font(13.5)).foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.vertical, 64) }
            }.padding()
        }.background(HarborTheme.background).navigationTitle(DesktopInterfaceText.value("Choose an avatar"))
            .toolbar { Button(DesktopInterfaceText.value("Close")) { avatars = false }.accessibilityIdentifier("profile-avatar-close") }
    }
}

private struct HarborAvatarTile: View {
    let avatar: DesktopAvatar
    let selected: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(avatar.asset).resizable().scaledToFill().aspectRatio(1, contentMode: .fit)
                .background(HarborTheme.surface).clipShape(.rect(cornerRadius: 13))
                .overlay { RoundedRectangle(cornerRadius: 13).stroke(selected ? HarborTheme.accent : HarborTheme.ink.opacity(0.08), lineWidth: selected ? 2 : 1) }
            Text(avatar.name).font(HarborTheme.font(11.5, weight: selected ? .semibold : .regular)).foregroundStyle(selected ? HarborTheme.ink : HarborTheme.ink.opacity(0.55)).lineLimit(1)
        }.accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}

private struct HarborAvatarPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.scaleEffect(!reduceMotion && configuration.isPressed ? 0.99 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: configuration.isPressed)
    }
}

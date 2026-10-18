import SwiftUI
import UIKit
import PhotosUI

private struct HouseholdEditingTarget: Identifiable {
    let id = UUID()
    let profile: DeviceHouseholdProfile?
}
private struct HouseholdUnlockTarget: Identifiable {
    let id = UUID()
    let profile: DeviceHouseholdProfile
    let editing: Bool
}
/// Normal profiles only. Unsupported Desktop child records remain in the roster
/// for lossless synchronization and never become mobile destinations or controls.
@MainActor struct HouseholdProfilesView: View {
    let app: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var editor: HouseholdEditingTarget?
    @State private var unlock: HouseholdUnlockTarget?
    @State private var selecting: String?
    @State private var exiting = false
    @State private var error: String?
    private var profiles: HouseholdProfileStore { app.profileContext.profiles }
    private var normal: [DeviceHouseholdProfile] { profiles.profiles.filter { !$0.desktop.isKid } }
    private var busy: Bool { selecting != nil || app.accountBusy || profiles.verifying }

    var body: some View {
        ZStack {
            Color.black.opacity(0.9).ignoresSafeArea()
            ScrollView {
                VStack(spacing: 28) {
                    if let unlock { pin(unlock) }
                    else if let editor {
                        HouseholdProfileForm(app: app, profile: editor.profile) { self.editor = nil }
                            .id(editor.id)
                    } else { list }
                }.padding(.horizontal, 24).padding(.vertical, 44).frame(maxWidth: 760).frame(maxWidth: .infinity)
            }.scrollDismissesKeyboard(.interactively)
        }.font(HarborTheme.font()).foregroundStyle(HarborTheme.ink).tint(HarborTheme.accent)
            .opacity(exiting ? 0 : 1)
            .animation(reduceMotion ? nil : .timingCurve(0.16, 1, 0.3, 1, duration: 0.34), value: exiting)
            .interactiveDismissDisabled(busy || !app.storageReady || !app.profileContext.ready)
            .task(id: selecting) { await selectPending() }
            .task { app.prepareProfileAppearances() }
            .accessibilityIdentifier("household-profiles")
    }
    private var list: some View {
        VStack(spacing: 36) {
            HStack {
                Spacer()
                if app.profileContext.ready {
                    Button {
                        Task {
                            do { try await app.closeProfiles() }
                            catch { self.error = safeMessage(error) }
                        }
                    } label: { Image(systemName: "xmark").frame(width: 44, height: 44) }
                        .buttonStyle(.plain).accessibilityLabel(DesktopInterfaceText.value("Close")).disabled(busy)
                }
            }
            VStack(spacing: 10) {
                Text(DesktopInterfaceText.value("Who's watching?")).font(HarborTheme.displayFont(36)).multilineTextAlignment(.center)
                Text(DesktopInterfaceText.value("Pick a profile to continue.")).font(HarborTheme.font(14)).foregroundStyle(.secondary)
            }.opacity(selecting == nil ? 1 : 0).offset(y: selecting == nil ? 0 : -4)
                .animation(reduceMotion ? nil : .timingCurve(0.16, 1, 0.3, 1, duration: 0.36), value: selecting)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120, maximum: 148), spacing: 24)], spacing: 32) {
                ForEach(normal) { profile in tile(profile) }
                if profiles.active?.desktop.isPrimary == true {
                    Button { editor = HouseholdEditingTarget(profile: nil) } label: {
                        VStack(spacing: 12) {
                            Image(systemName: "plus").font(.system(size: 28, weight: .light)).frame(width: 96, height: 96)
                                .overlay { Circle().stroke(HarborTheme.ink.opacity(0.2), style: StrokeStyle(lineWidth: 1, dash: [5])) }
                            Text(DesktopInterfaceText.value("New profile")).font(HarborTheme.font(14))
                        }.frame(minHeight: 140)
                    }.buttonStyle(.plain).accessibilityIdentifier("household-profile-create").disabled(busy)
                }
            }
            if let error { Text(error).font(HarborTheme.font(13)).foregroundStyle(.orange).multilineTextAlignment(.center) }
            if !profiles.ready {
                Button(DesktopInterfaceText.value("Retry")) { Task { await app.retryStartup() } }.buttonStyle(HarborAccountButtonStyle())
            }
        }
    }
    private func tile(_ profile: DeviceHouseholdProfile) -> some View {
        VStack(spacing: 10) {
            ZStack(alignment: .topTrailing) {
                Button {
                    error = nil
                    if profiles.requiresPIN(profile.id) { unlock = HouseholdUnlockTarget(profile: profile, editing: false) }
                    else { selecting = profile.id }
                } label: {
                    ProfileAvatar(profile: ProfilePreferences.forOwner(profiles.appearanceOwner(profile)), size: 96)
                        .overlay(alignment: .bottomTrailing) {
                            if profile.credential != nil {
                                Image(systemName: "lock.fill").font(.system(size: 12, weight: .semibold)).frame(width: 28, height: 28)
                                    .background(HarborTheme.background, in: .circle).offset(x: 3, y: 3)
                            }
                        }
                }.buttonStyle(.plain).accessibilityLabel(DesktopInterfaceText.value("Switch to {name}").replacingOccurrences(of: "{name}", with: profile.desktop.name))
                    .accessibilityIdentifier("household-select-" + profile.syncID).disabled(busy)
                if profiles.active?.desktop.isPrimary == true || profiles.active?.id == profile.id {
                    Button {
                        if profiles.requiresPIN(profile.id) { unlock = HouseholdUnlockTarget(profile: profile, editing: true) }
                        else { editor = HouseholdEditingTarget(profile: profile) }
                    } label: {
                        Image(systemName: "pencil").font(.system(size: 12, weight: .semibold)).frame(width: 44, height: 44)
                            .background(HarborTheme.background.opacity(0.95), in: .circle)
                    }.buttonStyle(.plain).offset(x: 18, y: -18).disabled(busy)
                        .accessibilityLabel(DesktopInterfaceText.value("Edit {name}").replacingOccurrences(of: "{name}", with: profile.desktop.name))
                        .accessibilityIdentifier("household-edit-" + profile.syncID)
                }
            }
            Text(verbatim: profile.desktop.name).font(HarborTheme.font(14, weight: .medium)).multilineTextAlignment(.center).lineLimit(2)
            if profile.desktop.isPrimary {
                Text(DesktopInterfaceText.value("profile.primary").uppercased()).font(HarborTheme.font(10, weight: .bold)).tracking(1.4)
                    .foregroundStyle(ProfilePreferences.color(profile.desktop.raw["color"].string?.replacingOccurrences(of: "#", with: "") ?? "7dd3fc"))
            }
        }.frame(minHeight: 148).scaleEffect(selecting == profile.id && !reduceMotion ? 1.12 : 1)
            .opacity(selecting == nil || selecting == profile.id ? 1 : 0.15)
            .animation(reduceMotion ? nil : .timingCurve(0.16, 1, 0.3, 1, duration: 0.44), value: selecting)
    }
    private func pin(_ target: HouseholdUnlockTarget) -> some View {
        ProfilePINEntryView(requestID: target.id.uuidString, title: target.profile.desktop.name,
            subtitle: DesktopInterfaceText.value("Profile is locked. Enter the 4-digit PIN to continue."), mode: .verify,
            failureMessage: DesktopInterfaceText.value("Wrong PIN"), complete: { password in
                if target.editing {
                    guard try await profiles.verifyForEditing(target.profile.id, password: password) else { return false }
                    unlock = nil; editor = HouseholdEditingTarget(profile: target.profile); return true
                }
                guard try await app.selectProfile(target.profile.id, password: password) else { return false }
                app.showProfiles = false; return true
            }, back: { unlock = nil })
    }
    private func selectPending() async {
        guard let id = selecting else { return }
        do {
            if !reduceMotion {
                try await Task.sleep(for: .milliseconds(340)); exiting = true
                try await Task.sleep(for: .milliseconds(340))
            }
            guard try await app.selectProfile(id) else { throw HarborError(code: "profile-locked") }
            app.showProfiles = false
        } catch is CancellationError { return }
        catch { self.error = safeMessage(error); exiting = false; selecting = nil }
    }
}

@MainActor private struct HouseholdProfileForm: View {
    let app: AppModel
    let done: () -> Void
    @State private var draft: HouseholdProfileDraft
    @State private var gallery = false
    @State private var avatarSearch = ""
    @State private var chosenPhoto: PhotosPickerItem?
    @State private var photoRequest: UUID?
    private var loadingPhoto: Bool { photoRequest != nil }
    @State private var pinAction: String?
    @State private var error: String?
    @State private var saving = false
    @State private var saveRequest: UUID?
    @State private var deleteConfirmation = false
    private var profiles: HouseholdProfileStore { app.profileContext.profiles }
    private var advanced: Bool { draft.original == nil || profiles.active?.desktop.isPrimary == true }
    init(app: AppModel, profile: DeviceHouseholdProfile?, done: @escaping () -> Void) {
        self.app = app; self.done = done
        _draft = State(initialValue: profile.map { HouseholdProfileDraft(profile: $0) } ?? HouseholdProfileDraft(sharingWith: app.profileContext.profiles.profiles.first { $0.desktop.isPrimary }?.id))
    }
    var body: some View {
        ZStack {
            if let pinAction { pin(pinAction) }
            else if gallery { avatars }
            else { form }
        }.frame(maxWidth: 520)
            .task(id: saveRequest) { guard saveRequest != nil else { return }; await save() }
            .task(id: chosenPhoto) { await loadPhoto() }
            .interactiveDismissDisabled(saving)
            .onDisappear { draft.pin = .keep; draft.parentPIN = .keep; draft.photo = .keep }
    }
    private var form: some View {
        VStack(alignment: .leading, spacing: 22) {
            Button(DesktopInterfaceText.value("common.back")) { done() }.frame(minHeight: 44).disabled(saving)
            Text(DesktopInterfaceText.value(draft.original == nil ? "New profile" : "Edit profile")).font(HarborTheme.displayFont(30))
            HStack(spacing: 20) {
                Button { gallery = true } label: {
                    MobileProfileAvatar(value: preview, size: 88)
                }.buttonStyle(.plain).accessibilityLabel(DesktopInterfaceText.value("Choose an avatar"))
                TextField(DesktopInterfaceText.value("Name"), text: $draft.name).textFieldStyle(.plain)
                    .padding(14).background(HarborTheme.surface, in: .rect(cornerRadius: 10)).accessibilityIdentifier("household-profile-name")
            }
            HStack(spacing: 18) {
                PhotosPicker(selection: $chosenPhoto, matching: .images) { Text(DesktopInterfaceText.value("Upload photo")) }
                    .buttonStyle(HarborAccountButtonStyle()).accessibilityIdentifier("household-profile-photo")
                if loadingPhoto { ProgressView() }
                if preview.photo != nil {
                    Button(DesktopInterfaceText.value("Reset to default")) {
                        draft.photo = .remove; draft.avatar = .string("/avatars/harbor_animal_01.webp")
                    }.font(HarborTheme.font(13))
                }
            }.disabled(loadingPhoto)
            ColorPicker(DesktopInterfaceText.value("Your color"), selection: Binding(get: { ProfilePreferences.color(draft.color.replacingOccurrences(of: "#", with: "")) }, set: { color in
                var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
                if UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a) { draft.color = String(format: "#%02x%02x%02x", Int(r * 255), Int(g * 255), Int(b * 255)) }
            }), supportsOpacity: false)
            if advanced {
                Divider()
                if draft.original?.desktop.isPrimary != true {
                    Toggle(DesktopInterfaceText.value("Share with {name}", variables: ["name": profiles.profiles.first { $0.desktop.isPrimary }?.desktop.name ?? ""]), isOn: Binding(get: { draft.sharingWith != nil }, set: { share in
                        draft.sharingWith = share ? profiles.profiles.first { $0.desktop.isPrimary }?.id : nil
                    })).accessibilityIdentifier("household-profile-share")
                }
                Toggle(DesktopInterfaceText.value("Use shared settings"), isOn: $draft.settingsLinked).accessibilityIdentifier("household-profile-linked-settings")
                Text(DesktopInterfaceText.value("Profile PIN")).font(HarborTheme.font(16, weight: .semibold))
                if draft.original?.credential != nil && draft.pin != .remove {
                    Button(DesktopInterfaceText.value("Change")) { pinAction = "change" }
                    Button(DesktopInterfaceText.value("Remove")) { pinAction = "remove" }
                } else { Button(DesktopInterfaceText.value("Set a PIN")) { pinAction = "set" } }
                if draft.pin != .keep { Text(DesktopInterfaceText.value("Save changes")).font(.caption).foregroundStyle(.secondary) }
            }
            if let error { Text(error).font(HarborTheme.font(13)).foregroundStyle(.orange).accessibilityIdentifier("household-profile-error") }
            Button { saveRequest = UUID() } label: {
                HStack { if saving { ProgressView() }; Text(DesktopInterfaceText.value("Save")) }.frame(maxWidth: .infinity)
            }.buttonStyle(HarborAccountButtonStyle(primary: true)).disabled(saving || loadingPhoto || draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("household-profile-save")
            if let profile = draft.original, !profile.desktop.isPrimary {
                if advanced { Button(DesktopInterfaceText.value("Transfer primary")) { Task { await promote(profile) } }.disabled(saving) }
                Button(DesktopInterfaceText.value("Delete profile"), role: .destructive) { deleteConfirmation = true }.disabled(saving)
                    .confirmationDialog(DesktopInterfaceText.value("Delete this profile?") , isPresented: $deleteConfirmation, titleVisibility: .visible) {
                        Button(DesktopInterfaceText.value("Delete profile"), role: .destructive) { Task { await remove(profile) } }
                    }
            }
        }.disabled(saving)
    }
    private var avatars: some View {
        VStack(alignment: .leading, spacing: 18) {
            Button(DesktopInterfaceText.value("common.back")) { gallery = false }.frame(minHeight: 44)
            TextField(DesktopInterfaceText.value("Search"), text: $avatarSearch).textFieldStyle(.roundedBorder)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 64), spacing: 14)], spacing: 18) {
                ForEach(DesktopAvatar.catalog.filter { avatarSearch.isEmpty || $0.name.localizedCaseInsensitiveContains(avatarSearch) }) { avatar in
                    Button { draft.avatar = .string("/avatars/\(avatar.id).webp"); draft.photo = .remove; gallery = false } label: {
                        Image(avatar.asset).resizable().scaledToFill().frame(width: 64, height: 64).clipShape(.circle)
                    }.buttonStyle(.plain).accessibilityLabel(avatar.name)
                }
            }
        }
    }
    private var preview: MobileProfile {
        let photo: ProfilePhotoRecord?
        switch draft.photo {
        case .keep: photo = draft.original?.localPhotoID.flatMap(ProfilePhotoStore.shared.cachedPhoto)
        case .remove: photo = nil
        case .replace(let data, let account): photo = ProfilePhotoRecord(photo: data, account: account)
        }
        return HouseholdAppearanceBinding.project(name: draft.name, color: draft.color, avatar: draft.avatar, photo: photo)
    }
    private func loadPhoto() async {
        guard let chosenPhoto else { return }
        let scope = app.accountOperationScope, request = UUID()
        photoRequest = request; defer { if photoRequest == request { photoRequest = nil } }
        do {
            guard let data = try await chosenPhoto.loadTransferable(type: Data.self) else { throw HarborError(code: "profile-photo") }
            try Task.checkCancellation()
            guard scope == app.accountOperationScope, photoRequest == request else { throw HarborError(code: "profile-editor-changed") }
            draft.photo = .replace(try ProfilePhotoStore.normalized(data), account: app.harborIdentity.cloud.accountID)
            draft.avatar = .null; error = nil
        } catch is CancellationError { return }
        catch { self.error = safeMessage(error) }
    }
    private func pin(_ action: String) -> some View {
        let verifying = action == "change" || action == "remove"
        return ProfilePINEntryView(requestID: action, title: DesktopInterfaceText.value(verifying ? "Enter current PIN" : "Set a PIN"),
            subtitle: DesktopInterfaceText.value(action == "remove" ? "Confirm your current PIN to remove the lock." : verifying ? "Confirm your current PIN, then pick a new one." : "Pick a 4-digit PIN. You'll be asked for it before this profile opens."),
            mode: verifying ? .verify : .set, failureMessage: DesktopInterfaceText.value("Wrong PIN"), complete: { password in
                if verifying {
                    guard let original = draft.original, try await profiles.verifyForEditing(original.id, password: password) else { return false }
                    if action == "remove" { draft.pin = .remove; pinAction = nil } else { pinAction = "set" }
                } else { draft.pin = .set(password); pinAction = nil }
                return true
            }, back: { pinAction = nil })
    }
    private func save() async {
        guard !saving, !loadingPhoto else { return }; saving = true; error = nil
        defer { saving = false; saveRequest = nil }
        do { try await app.saveProfile(draft); draft.pin = .keep; done() }
        catch is CancellationError { return }
        catch { self.error = safeMessage(error) }
    }
    private func promote(_ profile: DeviceHouseholdProfile) async {
        guard !saving else { return }; saving = true; defer { saving = false }
        do { try profiles.makePrimary(profile.id); try await app.refreshSelectedProfile(); done() }
        catch { self.error = safeMessage(error) }
    }
    private func remove(_ profile: DeviceHouseholdProfile) async {
        guard !saving else { return }; saving = true; defer { saving = false }
        do { try profiles.remove(profile.id); try await app.refreshSelectedProfile(); done() }
        catch { self.error = safeMessage(error) }
    }
}

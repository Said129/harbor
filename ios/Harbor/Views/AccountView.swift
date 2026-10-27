import SwiftUI

struct AccountView: View {
    let app: AppModel
    @State private var section = "profile"
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text(DesktopInterfaceText.value("Account")).font(HarborTheme.font(30, weight: .semibold)).accessibilityAddTraits(.isHeader)
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        HarborPill(title: DesktopInterfaceText.value("Your profile"), selected: section == "profile") { section = "profile" }.accessibilityIdentifier("account-tab-profile")
                        HarborPill(title: DesktopInterfaceText.value("Profiles"), selected: section == "profiles") { section = "profiles" }.accessibilityIdentifier("account-tab-profiles")
                        HarborPill(title: DesktopInterfaceText.value("Harbor account"), selected: section == "harbor", icon: "harbor-brand") { section = "harbor" }.accessibilityIdentifier("account-tab-harbor")
                    }
                }.scrollIndicators(.hidden).accessibilityIdentifier("account-tabs")
                Button { app.openProfiles() } label: {
                    Label(DesktopInterfaceText.value("Manage profiles"), systemImage: "person.2")
                        .frame(maxWidth: .infinity, alignment: .leading).frame(minHeight: 44)
                }.buttonStyle(HarborAccountButtonStyle()).accessibilityIdentifier("account-manage-profiles")
                if section == "profile" {
                    ProfileEditor(profile: ProfilePreferences.forOwner(app.personalOwner), identity: app.harborIdentity).id(app.interfaceProfileScope)
                } else if section == "profiles" {
                    HarborSettingsSection("Profiles", note: "Create profiles for the people who use Harbor. Each can have its own appearance, settings, and PIN.") {
                        ProfileLaunchSettingsView(app: app)
                    }
                } else {
                    HarborIdentityPanel(profile: ProfilePreferences.forOwner(app.personalOwner), cloud: app.harborIdentity).id(app.harborIdentityOwner)
                }
            }.padding(22)
        }.accessibilityIdentifier("account-scroll").background(HarborTheme.background)
            .font(HarborTheme.font(15)).foregroundStyle(HarborTheme.ink).textFieldStyle(.plain)
            .disabled(app.accountBusy).navigationTitle("").navigationBarTitleDisplayMode(.inline)
            .toolbar { Button(DesktopInterfaceText.value("Close")) { dismiss() }.accessibilityIdentifier("account-close") }
    }
}

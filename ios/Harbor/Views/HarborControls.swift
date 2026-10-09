import SwiftUI

struct HarborAccountButtonStyle: ButtonStyle {
    var primary = false
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(HarborTheme.font(13, weight: .semibold))
            .padding(.horizontal, 16).frame(minHeight: 44)
            .foregroundStyle(primary ? Color.black : HarborTheme.ink)
            .background(primary ? Color.white : HarborTheme.surface, in: .rect(cornerRadius: 9))
            .opacity(enabled ? configuration.isPressed ? 0.7 : 1 : 0.4)
    }
}

struct HarborPageHeading: View {
    let title: String
    var eyebrow: String? = nil
    var subtitle: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            if let eyebrow { Text(eyebrow.uppercased()).font(.system(size: 9, weight: .semibold)).tracking(3).foregroundStyle(.secondary) }
            Text(title).font(.custom("Fraunces-9ptBlack", size: 32).weight(.medium))
            if let subtitle { Text(subtitle).font(.subheadline).foregroundStyle(.secondary) }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct HarborPill: View {
    let title: String
    var selected = false
    var icon: String? = nil
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon { Image(icon).resizable().scaledToFit().frame(width: 15, height: 15) }
                Text(title).font(HarborTheme.font(12, weight: .semibold))
            }.padding(.horizontal, 14).frame(minHeight: 38)
                .foregroundStyle(selected ? Color.black : HarborTheme.ink.opacity(0.65))
                .background(selected ? Color.white : HarborTheme.surface.opacity(0.65), in: .capsule)
        }.buttonStyle(.plain).accessibilityLabel(title).accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}

struct HarborSearchField: View {
    let prompt: String
    @Binding var text: String
    var body: some View {
        HStack(spacing: 9) {
            Image("nav-search").resizable().scaledToFit().frame(width: 16, height: 16).foregroundStyle(.secondary)
            TextField(prompt, text: $text).font(HarborTheme.font(14)).textInputAutocapitalization(.never).autocorrectionDisabled().submitLabel(.search)
            if !text.isEmpty { Button { text = "" } label: { Image("desktop-x").resizable().scaledToFit().frame(width: 14, height: 14).foregroundStyle(.secondary).frame(width: 44, height: 44).contentShape(Rectangle()) }.buttonStyle(.plain).accessibilityLabel(DesktopInterfaceText.value("Clear search")) }
        }.padding(.horizontal, 14).frame(minHeight: 44).background(HarborTheme.surface.opacity(0.6), in: .capsule)
            .overlay { Capsule().stroke(.white.opacity(0.04), lineWidth: 1) }
    }
}

struct HarborCatalogEmptyView: View {
    let app: AppModel
    var body: some View {
        VStack(spacing: 16) {
            Image("catalog-empty-puzzle").resizable().scaledToFit().frame(width: 30, height: 30).foregroundStyle(HarborTheme.ink.opacity(0.35)).accessibilityHidden(true)
            VStack(spacing: 6) {
                Text(DesktopInterfaceText.value("No catalogs yet")).font(HarborTheme.font(17, weight: .semibold))
                Text(DesktopInterfaceText.value("Install a Stremio addon and its catalogs show up here as poster rails, ready to browse."))
                    .font(HarborTheme.font(13)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            NavigationLink { AddonsView(app: app) } label: {
                Text(DesktopInterfaceText.value("Browse addons")).font(HarborTheme.font(13, weight: .semibold))
                    .padding(.horizontal, 20).frame(minHeight: 44).foregroundStyle(HarborTheme.background).background(HarborTheme.ink, in: .capsule)
            }.buttonStyle(.plain).accessibilityIdentifier("empty-catalog-browse-addons")
        }.multilineTextAlignment(.center).padding(.horizontal, 28).padding(.vertical, 50).frame(maxWidth: .infinity)
            .background(HarborTheme.background.opacity(0.3), in: .rect(cornerRadius: 16))
            .overlay { RoundedRectangle(cornerRadius: 16).stroke(HarborTheme.ink.opacity(0.1), style: StrokeStyle(lineWidth: 1, dash: [4, 4])) }
    }
}

struct HarborNoMatchesView: View {
    var text = "No catalogs match your search."
    var body: some View {
        Text(DesktopInterfaceText.value(text)).font(HarborTheme.font(13)).foregroundStyle(.secondary).multilineTextAlignment(.center)
            .padding(.horizontal, 24).padding(.vertical, 48).frame(maxWidth: .infinity)
            .background(HarborTheme.background.opacity(0.3), in: .rect(cornerRadius: 16))
            .overlay { RoundedRectangle(cornerRadius: 16).stroke(HarborTheme.ink.opacity(0.1), style: StrokeStyle(lineWidth: 1, dash: [4, 4])) }
    }
}

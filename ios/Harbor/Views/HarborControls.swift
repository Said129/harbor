import SwiftUI

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
            if !text.isEmpty { Button { text = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }.accessibilityLabel("Borrar búsqueda") }
        }.padding(.horizontal, 14).frame(minHeight: 44).background(HarborTheme.surface.opacity(0.6), in: .capsule)
            .overlay { Capsule().stroke(.white.opacity(0.04), lineWidth: 1) }
    }
}

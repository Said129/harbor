import SwiftUI

struct HarborActionHint: ViewModifier {
    let id: String
    let title: String
    let selected: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func body(content: Content) -> some View {
        content.scaleEffect(selected == id && !reduceMotion ? 1.06 : 1)
            .overlay(alignment: .topLeading) {
                if selected == id {
                    Text(title).font(HarborTheme.font(12, weight: .medium)).foregroundStyle(HarborTheme.ink)
                        .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 12).padding(.vertical, 8).frame(minWidth: 110, maxWidth: 150)
                        .background(ThemePreferences.shared.color("elevated"), in: .rect(cornerRadius: 8))
                        .overlay { RoundedRectangle(cornerRadius: 8).stroke(HarborTheme.ink.opacity(0.12), lineWidth: 1) }
                        .shadow(color: .black.opacity(0.35), radius: 8, y: 4).offset(y: -42)
                        .allowsHitTesting(false).transition(.opacity.combined(with: .scale(scale: reduceMotion ? 1 : 0.95)))
                }
            }
    }
}

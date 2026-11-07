import SwiftUI

/// The jumps Desktop offers for the seek buttons and keys (`lib/seek-step.ts`).
enum SeekSteps {
    static let options: [Double] = [1, 3, 5, 10, 15, 30, 60, 90]

    /// A saved value outside the list falls back, as Desktop's `sanitizeSeekStep`.
    static func sanitized(_ value: Double, fallback: Double) -> Double { options.contains(value) ? value : fallback }

    /// The choices to list: Desktop's, plus a saved value that is not one of them so it stays visible.
    static func choices(including current: Double) -> [Double] { options.contains(current) ? options : (options + [current]).sorted() }
}

/// Puts the leave confirm over the player. A modifier of its own keeps the player's long modifier chain quick to type-check.
struct PlayerLeaveConfirmOverlay: ViewModifier {
    let presented: Bool
    let keep: () -> Void
    let leave: (Bool) -> Void

    func body(content: Content) -> some View {
        content.overlay {
            if presented { PlayerLeaveConfirm(keep: keep, leave: leave) }
        }
    }
}

/// Desktop's leave confirm (`components/player/leave-confirm-modal.tsx`): shown when Esc would close the player.
struct PlayerLeaveConfirm: View {
    let keep: () -> Void
    /// Called with whether "Don't ask me again" was ticked.
    let leave: (Bool) -> Void
    @State private var remember = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.7).ignoresSafeArea().onTapGesture(perform: keep).accessibilityHidden(true)
            VStack(spacing: 16) {
                Text(DesktopInterfaceText.value("Leave the show?")).font(HarborTheme.font(22, weight: .bold)).multilineTextAlignment(.center)
                Text(DesktopInterfaceText.value("We'll save your spot so you can pick up right where you left off."))
                    .font(HarborTheme.font(15)).foregroundStyle(.secondary).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                Toggle(isOn: $remember) { Text(DesktopInterfaceText.value("Don't ask me again")).font(HarborTheme.font(14)) }
                    .toggleStyle(.switch).frame(minHeight: 44).accessibilityIdentifier("player-leave-remember")
                HStack(spacing: 12) {
                    Button(action: keep) { Text(DesktopInterfaceText.value("Keep watching")).frame(maxWidth: .infinity) }
                        .buttonStyle(HarborAccountButtonStyle()).keyboardShortcut(.cancelAction).accessibilityIdentifier("player-leave-keep")
                    Button { leave(remember) } label: { Text(DesktopInterfaceText.value("Leave")).frame(maxWidth: .infinity) }
                        .buttonStyle(HarborAccountButtonStyle(primary: true)).keyboardShortcut(.defaultAction).accessibilityIdentifier("player-leave-confirm-button")
                }
            }.padding(24).frame(maxWidth: 420).background(HarborTheme.surface, in: .rect(cornerRadius: 20))
                .overlay { RoundedRectangle(cornerRadius: 20).stroke(HarborTheme.ink.opacity(0.1), lineWidth: 1) }.padding(.horizontal, 16)
        }
        .accessibilityElement(children: .contain).accessibilityAddTraits(.isModal).accessibilityIdentifier("player-leave-confirm")
    }
}

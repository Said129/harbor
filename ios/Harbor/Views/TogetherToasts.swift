import SwiftUI

/// Desktop's `together-invite-toast.tsx` and `together-summon-toast.tsx`: while joined to a room, the host starting a title or
/// calling the room to a screen shows a card at the top with a button that goes there. A modifier of its own on the shell, like
/// `SimklPendingRecovery`. Desktop also opens the invite by itself after four seconds; that is left out here because a phone has
/// no pointer to hold it back and the title page would open behind a player that is already on screen.
struct TogetherToastDriver: ViewModifier {
    let select: (HarborSection) -> Void
    let open: (Media) -> Void
    @State private var session = TogetherSession.shared

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                Group {
                    if let incoming = session.incomingInvite {
                        inviteCard(incoming)
                    } else if let incoming = session.incomingSummon {
                        summonCard(incoming)
                    }
                }.padding(.horizontal, 12).padding(.top, 56)
            }
            .animation(.easeOut(duration: 0.2), value: session.incomingInvite?.at)
            .animation(.easeOut(duration: 0.2), value: session.incomingSummon?.at)
    }

    private func inviteCard(_ incoming: TogetherIncomingInvite) -> some View {
        let invite = incoming.invite
        let guestPick = invite.guestPick == true
        let eyebrow = guestPick ? DesktopInterfaceText.value("Pick your source")
            : DesktopInterfaceText.value("{name} started watching", variables: ["name": incoming.name])
        return card(image: invite.backgroundUrl ?? invite.posterUrl, eyebrow: eyebrow, title: invite.mediaTitle,
                    detail: TogetherToastRules.episodeLabel(invite.episode),
                    action: guestPick ? DesktopInterfaceText.value("Choose") : DesktopInterfaceText.value("Join"),
                    accept: { open(TogetherToastRules.media(from: invite)); session.dismissInvite() },
                    dismiss: { session.dismissInvite() })
            .accessibilityIdentifier("together-invite-toast")
    }

    private func summonCard(_ incoming: TogetherIncomingSummon) -> some View {
        let target = incoming.target
        return card(image: target.backgroundUrl ?? target.posterUrl,
                    eyebrow: DesktopInterfaceText.value("{name} wants you here", variables: ["name": incoming.name]),
                    title: TogetherToastRules.headline(target), detail: nil, action: DesktopInterfaceText.value("Sure"),
                    accept: {
                        switch TogetherToastRules.destination(target) {
                        case .section(let section): select(section)
                        case .media(let media): open(media)
                        case nil: break
                        }
                        session.dismissSummon()
                    },
                    dismiss: { session.dismissSummon() })
            .accessibilityIdentifier("together-summon-toast")
    }

    private func card(image: String?, eyebrow: String, title: String, detail: String?, action: String,
                      accept: @escaping () -> Void, dismiss: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            AsyncImage(url: image.flatMap(URL.init(string:))) { $0.resizable().scaledToFill() } placeholder: { HarborTheme.surface }
                .frame(width: 56, height: 40).clipShape(Capsule())
            VStack(alignment: .leading, spacing: 2) {
                Text(eyebrow.uppercased()).font(HarborTheme.font(10, weight: .semibold)).tracking(1.2).foregroundStyle(HarborTheme.accent).lineLimit(1)
                HStack(spacing: 6) {
                    Text(title).font(HarborTheme.font(13, weight: .semibold)).lineLimit(1)
                    if let detail { Text(detail).font(HarborTheme.font(11)).foregroundStyle(.secondary) }
                }
            }
            Spacer(minLength: 0)
            Button(action: accept) {
                Text(action).font(HarborTheme.font(12, weight: .semibold)).padding(.horizontal, 14).frame(minHeight: 36)
                    .background(HarborTheme.ink, in: Capsule()).foregroundStyle(ThemePreferences.shared.color("canvas"))
            }.buttonStyle(.plain)
            Button(action: dismiss) {
                Image(systemName: "xmark").font(.system(size: 13, weight: .semibold)).frame(width: 36, height: 36)
            }.buttonStyle(.plain).foregroundStyle(.secondary).accessibilityLabel(DesktopInterfaceText.value("Dismiss"))
        }
        .padding(6)
        .background(HarborTheme.surface, in: Capsule())
        .overlay { Capsule().stroke(ThemePreferences.shared.color("edge-soft"), lineWidth: 1) }
        .shadow(color: .black.opacity(0.45), radius: 14, y: 8)
        .foregroundStyle(HarborTheme.ink)
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}

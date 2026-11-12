import SwiftUI
import UIKit

/// Watch Together room sheet: create or join a room, share the invite, see members, chat. Presented from the player
/// or detail screen (hook described in the report). Everything it shows comes from `TogetherSession`.
struct TogetherSheet: View {
    @State private var session = TogetherSession.shared
    @State private var preferences = TogetherPreferences.shared
    @State private var nameDraft = ""
    @State private var codeDraft = ""
    @State private var chatDraft = ""

    var body: some View {
        NavigationStack {
            List {
                if preferences.relayURL.isEmpty {
                    needsRelaySection
                } else if session.snapshot.state == .joined {
                    roomSections
                } else {
                    joinSections
                }
            }
            .navigationTitle(DesktopInterfaceText.value("Watch together"))
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { nameDraft = preferences.displayName }
        }
    }

    @ViewBuilder private var needsRelaySection: some View {
        Section {
            Text(DesktopInterfaceText.value("Paste a wss:// URL that a friend or your community shared with you."))
                .font(.footnote)
            NavigationLink {
                TogetherSettingsView()
            } label: {
                Text(DesktopInterfaceText.value("Open Settings"))
            }
        } header: {
            Text(DesktopInterfaceText.value("Watch Together needs a relay."))
        }
    }

    @ViewBuilder private var joinSections: some View {
        let connecting = session.snapshot.state == .connecting
        Section {
            TextField(DesktopInterfaceText.value("Your name"), text: $nameDraft)
                .onSubmit { commitName() }
            Button {
                createRoom()
            } label: {
                Text(DesktopInterfaceText.value("Start a new room"))
            }
            .disabled(connecting)
        }
        Section {
            TextField(DesktopInterfaceText.value("Paste invite link"), text: $codeDraft)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .onSubmit { joinTapped() }
            Button {
                joinTapped()
            } label: {
                Text(DesktopInterfaceText.value("Join"))
            }
            .disabled(codeDraft.togetherTrimmed.isEmpty || connecting)
        } header: {
            Text(DesktopInterfaceText.value("or join"))
        } footer: {
            Text(DesktopInterfaceText.value("or paste an invite link"))
        }
        if session.snapshot.state == .error {
            Section {
                Text(DesktopInterfaceText.value(session.snapshot.lastError ?? ""))
                    .foregroundStyle(.red)
                Button {
                    session.retry()
                } label: {
                    Text(DesktopInterfaceText.value("Try again"))
                }
            }
        }
    }

    @ViewBuilder private var roomSections: some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                Text(DesktopInterfaceText.value("Room code"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(roomCode)
                    .font(.system(.title2, design: .monospaced))
                    .textSelection(.enabled)
            }
            Button {
                UIPasteboard.general.string = roomCode
            } label: {
                Text(DesktopInterfaceText.value("Copy room code"))
            }
            if let link = inviteURL {
                ShareLink(item: link) {
                    Text(DesktopInterfaceText.value("Invite link"))
                }
                Button {
                    UIPasteboard.general.string = link.absoluteString
                } label: {
                    Text(DesktopInterfaceText.value("Copy invite link"))
                }
            }
        }
        // The lobby: until the host starts the room, each member shows whether they are ready (Desktop's lobby gate).
        Section {
            ForEach(sortedParticipants, id: \.id) { participant in
                HStack {
                    Text(participant.name)
                    Spacer()
                    if !session.snapshot.started {
                        Image(systemName: participant.ready ? "checkmark.circle.fill" : "circle.dashed")
                            .foregroundStyle(participant.ready ? Color.green : Color.secondary)
                            .accessibilityLabel(DesktopInterfaceText.value(participant.ready ? "Ready" : "Not ready yet"))
                    }
                }
            }
        } header: {
            Text(DesktopInterfaceText.value("{n} watching", variables: ["n": String(sortedParticipants.count)]))
        } footer: {
            if !session.snapshot.started {
                Text(DesktopInterfaceText.value(session.isHost ? "Press play to start the room for everyone" : "Waiting for the host to start"))
            }
        }
        // The title the room is on, from the last state sent by a member. The player compares it with the title on screen.
        if let roomTitle = session.snapshot.syncState?.mediaTitle, !roomTitle.isEmpty {
            Section {
                Text(DesktopInterfaceText.value("In this room: {title}", variables: ["title": roomTitle]))
            }
        }
        chatSection
        if session.isHost {
            Section {
                ForEach(TogetherToastRules.summonViews.indices, id: \.self) { index in
                    Button {
                        let option = TogetherToastRules.summonViews[index]
                        session.summon(TogetherSummonTarget(view: option.view, label: option.label))
                    } label: {
                        Text(DesktopInterfaceText.value(TogetherToastRules.summonViews[index].label))
                    }
                }
            } header: {
                Text(DesktopInterfaceText.value("Call guests"))
            } footer: {
                Text(DesktopInterfaceText.value("Sends guests a pointer to this screen in their app"))
            }
        }
        if session.isHost {
            Section {
                Toggle(DesktopInterfaceText.value("Guests pick their own source"), isOn: Binding(
                    get: { preferences.guestsPick },
                    set: { preferences.setGuestsPick($0) }
                ))
            } footer: {
                Text(DesktopInterfaceText.value("Prompts guests to choose instead of auto-matching"))
            }
        }
        Section {
            Button(role: .destructive) {
                session.leaveRoom()
            } label: {
                Text(DesktopInterfaceText.value("Leave room"))
            }
        }
    }

    @ViewBuilder private var chatSection: some View {
        Section {
            if session.chat.isEmpty {
                Text(DesktopInterfaceText.value("Say hi."))
                    .foregroundStyle(.secondary)
            }
            ForEach(session.chat) { message in
                VStack(alignment: .leading, spacing: 2) {
                    Text(message.name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(message.text)
                }
            }
            HStack {
                TextField(DesktopInterfaceText.value("Message"), text: $chatDraft)
                    .onSubmit { sendChat() }
                Button {
                    sendChat()
                } label: {
                    Text(DesktopInterfaceText.value("Send"))
                }
                .disabled(chatDraft.togetherTrimmed.isEmpty)
            }
        } header: {
            Text(DesktopInterfaceText.value("Chat"))
        }
    }

    private var roomCode: String { session.snapshot.room ?? "" }

    private var sortedParticipants: [TogetherParticipant] {
        session.snapshot.participants.sorted { $0.joinedAt < $1.joinedAt }
    }

    private var inviteURL: URL? {
        guard let room = session.snapshot.room else { return nil }
        return URL(string: TogetherInviteLink.build(relayURL: preferences.relayURL, roomCode: room))
    }

    private func createRoom() {
        commitName()
        session.createRoom()
    }

    private func joinTapped() {
        commitName()
        switch TogetherJoinInput.resolve(codeDraft) {
        case .link(let link):
            // Desktop also switches the saved relay to the one in the link.
            preferences.setRelayURL(link.relayURL)
            session.join(code: link.roomCode)
        case .room(let code):
            session.join(code: code)
        case .empty:
            break
        }
    }

    private func commitName() {
        let trimmed = nameDraft.togetherTrimmed
        if !trimmed.isEmpty && trimmed != preferences.displayName {
            session.setDisplayName(trimmed)
        }
    }

    private func sendChat() {
        let text = chatDraft.togetherTrimmed
        if text.isEmpty { return }
        session.sendChat(text)
        chatDraft = ""
    }
}

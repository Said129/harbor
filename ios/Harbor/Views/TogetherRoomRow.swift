import SwiftUI

/// The Settings row that opens the Watch Together room sheet (create or join a room, invite, chat). The sheet lives here so
/// Settings only needs one line. Playback sync with the player is not connected yet: rooms, invites and chat work.
struct TogetherRoomRow: View {
    @State private var presenting = false

    var body: some View {
        Button { presenting = true } label: {
            SettingsRow(title: DesktopInterfaceText.value("Start a new room"), icon: "nav-catalogs")
        }
        .buttonStyle(.plain).accessibilityIdentifier("settings-watch-together-room")
        .sheet(isPresented: $presenting) { TogetherSheet() }
    }
}

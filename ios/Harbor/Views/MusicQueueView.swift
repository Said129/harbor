import SwiftUI

@MainActor struct MusicQueueView: View {
    @Bindable var player: MusicPlayback
    private func text(_ key: String) -> String { DesktopInterfaceText.value(key) }
    var body: some View {
        let snapshot = player.queueSnapshot
        List {
            if let current = snapshot.current {
                Section(text("music.queue.nowPlaying")) {
                    MusicPlaybackRow(item: current, owner: snapshot.owner) { player.playQueueItem(current, in: snapshot) }
                        .accessibilityIdentifier("music-queue-current")
                }
            }
            Section {
                if player.shuffle { Text(text("music.queue.shuffleNote")).font(.caption).foregroundStyle(.secondary) }
                if snapshot.upcoming.isEmpty { Text(text("music.queue.empty")).foregroundStyle(.secondary) }
                ForEach(snapshot.upcoming) { item in row(item, snapshot: snapshot) }
                    .onMove { offsets, destination in player.moveUpcoming(from: offsets, to: destination, in: snapshot) }
            } header: {
                HStack {
                    Text(text("music.row.upNext")); Spacer()
                    Text(DesktopInterfaceText.value("music.queue.count", variables: ["count": String(snapshot.upcoming.count)]))
                }
            } footer: {
                if !snapshot.upcoming.isEmpty { Text(text("music.queue.dragHint")) }
            }
            if !snapshot.previous.isEmpty {
                DisclosureGroup(text("music.queue.previous")) {
                    ForEach(snapshot.previous) { item in row(item, snapshot: snapshot) }
                }
            }
        }.navigationTitle(text("music.transport.queue")).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) { EditButton().disabled(snapshot.upcoming.isEmpty) }
                ToolbarItem(placement: .bottomBar) {
                    Button(text("music.transport.clearQueue")) { player.clearUpcoming(in: snapshot) }
                        .disabled(snapshot.upcoming.isEmpty)
                }
            }.environment(\.musicPlaybackSession, player.playbackSession).accessibilityIdentifier("music-queue-editor")
    }
    private func row(_ item: MusicPlaybackItem, snapshot: MusicQueueSnapshot) -> some View {
        MusicPlaybackRow(item: item, owner: snapshot.owner) { player.playQueueItem(item, in: snapshot) }
            .swipeActions {
                Button(role: .destructive) { player.removeQueueItem(item, in: snapshot) } label: {
                    Label(DesktopInterfaceText.value("music.queue.remove", variables: ["title": item.track.title]), systemImage: "trash")
                }
            }.contextMenu {
                Button(text("music.queue.playNext")) { player.prioritizeQueueItem(item, in: snapshot) }
                if let index = snapshot.upcoming.firstIndex(where: { $0.id == item.id }) {
                    Button {
                        player.moveUpcoming(from: IndexSet(integer: index), to: index - 1, in: snapshot)
                    } label: {
                        Label(DesktopInterfaceText.value("music.queue.moveUp", variables: ["title": item.track.title]), systemImage: "arrow.up")
                    }.disabled(index == 0)
                    Button {
                        player.moveUpcoming(from: IndexSet(integer: index), to: index + 2, in: snapshot)
                    } label: {
                        Label(DesktopInterfaceText.value("music.queue.moveDown", variables: ["title": item.track.title]), systemImage: "arrow.down")
                    }.disabled(index == snapshot.upcoming.count - 1)
                }
                Button(DesktopInterfaceText.value("music.queue.remove", variables: ["title": item.track.title]), role: .destructive) { player.removeQueueItem(item, in: snapshot) }
            }
    }
}

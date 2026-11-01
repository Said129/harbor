import SwiftUI

@MainActor struct MusicLyricsView: View {
    @Bindable var player: MusicPlayback
    let client: MusicLyricsClient?
    @State private var lines: [MusicLyricLine] = []
    @State private var loading = false
    @State private var follow = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var active: Int? { MusicLyricsTiming.index(lines, at: player.position) }
    var body: some View {
        ScrollViewReader { proxy in
            VStack(spacing: 12) {
                if loading { ProgressView() }
                else if lines.isEmpty { Text(DesktopInterfaceText.value("music.lyrics.empty")).foregroundStyle(.secondary) }
                else {
                    Toggle(DesktopInterfaceText.value("music.lyrics.follow"), isOn: $follow)
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 20) {
                            ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                                Button { player.seek(line.at) } label: {
                                    Text(line.text.isEmpty ? "♪" : line.text).font(.title3.weight(active == index ? .bold : .regular))
                                        .foregroundStyle(active == index ? HarborTheme.ink : .secondary).frame(maxWidth: .infinity, alignment: .leading)
                                        .frame(minHeight: 44).contentShape(.rect)
                                }.buttonStyle(.plain).id(index)
                            }
                        }.padding(.vertical, 16)
                    }.frame(height: 320)
                }
                Link("LRCLIB", destination: URL(string: "https://lrclib.net")!).font(.caption)
            }.onChange(of: active) { _, index in
                guard follow, let index else { return }
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.16)) { proxy.scrollTo(index, anchor: .center) }
            }
        }.task(id: player.currentItem?.id) {
            lines = []; loading = true; defer { loading = false }
            guard let track = player.currentTrack, let client else { return }
            do { let value = try await client.load(track); try Task.checkCancellation(); lines = value ?? [] }
            catch { }
        }.accessibilityIdentifier("music-lyrics")
    }
}

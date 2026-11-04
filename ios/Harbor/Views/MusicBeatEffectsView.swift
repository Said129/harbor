import Observation
import SwiftUI

/// Desktop's 90 ms coalescing keeps continuous touch edits from building an
/// unbounded native-command queue. Closing waits for its acknowledged edit.
@MainActor @Observable private final class MusicBeatEffectsModel {
    private(set) var draft: MusicAudioEffects
    private(set) var applying = false
    private(set) var failed = false
    var current: Bool { player.effectLease == lease }
    @ObservationIgnored private let player: MusicPlayback
    @ObservationIgnored private let session: MusicPlaybackSession
    @ObservationIgnored private let lease: UUID
    @ObservationIgnored private var pending: MusicAudioEffects?
    @ObservationIgnored private var operation: Task<Void, Never>?
    @ObservationIgnored private var closed = false
    init(player: MusicPlayback, session: MusicPlaybackSession, owner: UUID?) throws {
        self.player = player; self.session = session
        lease = try player.beginEffects(using: session, lease: owner ?? UUID()); draft = player.audioEffects
    }
    func select(_ kind: String) { var value = draft; value.kind = value.kind == kind ? "off" : kind; update(value) }
    func depth(_ number: Double) { var value = draft; value.depth = number; update(value) }
    func beats(_ number: Double) { var value = draft; value.beats = number; update(value) }
    func bpm(_ number: Double) { var value = draft; value.bpm = number; update(value) }
    func reset() { update(.init()) }
    private func update(_ value: MusicAudioEffects) {
        guard !closed else { return }
        draft = value; pending = value; failed = false
        guard operation == nil else { return }
        applying = true
        operation = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.operation = nil; self.applying = false }
            while !self.closed && self.pending != nil {
                do {
                    try await Task.sleep(for: .milliseconds(90))
                    while self.player.audioApplying || self.player.resolving {
                        try self.session.validate()
                        guard !self.closed else { return }
                        try await Task.sleep(for: .milliseconds(25))
                    }
                    guard !self.closed, let value = self.pending else { return }
                    self.pending = nil
                    try await self.player.applyEffects(value, lease: self.lease, using: self.session)
                } catch is CancellationError { return }
                catch { self.failed = true; self.pending = nil }
            }
        }
    }
    func close() {
        guard !closed else { return }
        closed = true; pending = nil
        let previous = operation, player = player, lease = lease, session = session
        Task { @MainActor in
            await previous?.value
            await player.endEffects(lease, using: session)
        }
    }
}

@MainActor struct MusicBeatEffectsSection: View {
    let player: MusicPlayback
    let session: MusicPlaybackSession
    private let owner: UUID?
    @State private var model: MusicBeatEffectsModel?
    @State private var failed = false
    init(player: MusicPlayback, session: MusicPlaybackSession, owner: UUID? = nil) {
        self.player = player; self.session = session; self.owner = owner
    }
    private func text(_ key: String) -> String { DesktopInterfaceText.value(key) }
    var body: some View {
        Section(text("dj.fx.beat")) {
            if let model { MusicBeatEffectsControls(model: model).disabled(!model.current) }
            else if !failed { ProgressView(text("music.loading")).accessibilityIdentifier("music-beat-fx-loading") }
            if failed { Text(text("music.audio.saveError")).font(.caption).foregroundStyle(.orange) }
        }.task {
            guard model == nil else { return }
            do {
                while player.audioApplying || player.resolving {
                    try session.validate()
                    try await Task.sleep(for: .milliseconds(25))
                }
                try Task.checkCancellation()
                model = try MusicBeatEffectsModel(player: player, session: session, owner: owner); failed = false
            } catch is CancellationError { }
            catch { failed = true }
        }.onDisappear { if owner == nil { model?.close(); model = nil } }
    }
}

@MainActor private struct MusicBeatEffectsControls: View {
    let model: MusicBeatEffectsModel
    private let divisions: [(Double, String)] = [
        (0.0625, "1/16"), (0.125, "1/8"), (0.25, "1/4"), (0.5, "1/2"), (0.75, "3/4"),
        (1, "1"), (1.5, "3/2"), (2, "2"), (4, "4"), (8, "8"), (16, "16")
    ]
    private var kinds: [String] { ["echo", "delay", "spiral", "wide"].filter { MusicAudioRuntime.supports(MusicAudioEffects(kind: $0)) } }
    private func text(_ key: String) -> String { DesktopInterfaceText.value(key) }
    var body: some View {
        LazyVGrid(columns: [.init(.flexible()), .init(.flexible())], spacing: 10) {
            ForEach(kinds, id: \.self) { kind in
                Button(text("dj.fx." + kind)) { model.select(kind) }
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .buttonStyle(.bordered).tint(model.draft.kind == kind ? HarborTheme.accent : .secondary)
                    .accessibilityAddTraits(model.draft.kind == kind ? .isSelected : [])
                    .accessibilityIdentifier("music-beat-fx-" + kind)
            }
        }
        VStack(alignment: .leading) {
            HStack { Text(text("dj.fx.depth")); Spacer(); Text(model.draft.depth.formatted(.percent.precision(.fractionLength(0)))).monospacedDigit() }
            Slider(value: Binding(get: { model.draft.depth }, set: { model.depth($0) }), in: 0...1, step: 0.01)
                .accessibilityLabel(text("dj.fx.depth"))
        }
        Picker(text("dj.fx.beats"), selection: Binding(get: { model.draft.beats }, set: { model.beats($0) })) {
            ForEach(divisions, id: \.0) { value in Text(value.1).tag(value.0) }
        }
        Stepper(value: Binding(get: { model.draft.bpm }, set: { model.bpm($0) }), in: 40...220, step: 1) {
            LabeledContent(text("dj.bpm"), value: model.draft.bpm.formatted(.number.precision(.fractionLength(0...1))))
        }
        Button(text("music.audio.reset")) { model.reset() }
        if model.applying { ProgressView().accessibilityLabel(text("dj.fx.title")) }
        if model.failed { Text(text("music.audio.saveError")).font(.caption).foregroundStyle(.orange) }
    }
}

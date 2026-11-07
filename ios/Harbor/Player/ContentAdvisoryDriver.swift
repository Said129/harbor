import SwiftUI

/// Desktop's content advisory during playback (`views/player/hooks/use-content-advisory.ts` and the two cards). It loads the
/// title's parental guide when the card is on, shows the card once per source when playback starts, and offers the one-time
/// invitation otherwise. The rules are in `ContentAdvisory`; the timeline is in `ContentAdvisoryToastState`. A modifier of its
/// own keeps the player's long modifier chain quick to type-check.
struct ContentAdvisoryDriver: ViewModifier {
    let state: PlayerState
    let session: PlaybackSession
    let media: Media?
    @State private var guide: ContentAdvisoryGuide?
    @State private var toast = ContentAdvisoryToastState()
    @State private var prompt = ContentAdvisoryPromptState()
    /// Desktop's `playKey`: playback has been seen to run for the current source.
    @State private var sourceStarted = false

    private var preferences: ContentAdvisoryPreferences { .shared }
    private var ignores: ContentAdvisoryIgnores { .shared }

    /// The title the guide is about: the first IMDb id among the playing target and the media. Desktop's TMDB lookup is not made here.
    private var titleID: String? {
        let media = session.media ?? self.media
        return ContentAdvisory.imdbID(in: session.target.id)
            ?? ContentAdvisory.imdbID(in: media?.id)
            ?? ContentAdvisory.imdbID(in: media?.imdbID)
    }

    /// Desktop's `status === "playing"`, read from the same fields the Trakt tracker reads.
    private var playing: Bool {
        state.loaded && !state.paused && !state.buffering && !state.restarting && !state.ended && state.error == nil
    }

    private var started: Bool {
        ContentAdvisory.hasPlaybackStarted(position: state.position)
    }

    private var hasContent: Bool {
        guide.map { ContentAdvisory.showsContent($0) } ?? false
    }

    private var triggerReady: Bool {
        sourceStarted && started && hasContent
    }

    /// Desktop's `snap.firstFrameReady && status === "playing" && imdbId`.
    private var promptReady: Bool {
        playing && state.renderReady && titleID != nil
    }

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .topLeading) { cards }
            .task(id: fetchKey) { await loadGuide() }
            .task(id: toast) { await runToast() }
            .task(id: prompt) { await runPrompt() }
            .onChange(of: playing) { _, now in
                if now { sourceStarted = true }
            }
            .onChange(of: session.source.url) { _, _ in restartForSource() }
            .onChange(of: triggerReady, initial: true) { _, _ in updateToast() }
            .onChange(of: preferences.showToast, initial: true) { _, _ in
                updateToast()
                applyPrompt(ready: promptReady)
            }
            .onChange(of: promptReady, initial: true) { _, ready in applyPrompt(ready: ready) }
    }

    /// The overlay for the cards. A fresh guide is needed only while the card is on, as in Desktop.
    private var cards: some View {
        ContentAdvisoryOverlay(
            toast: toast,
            guide: guide,
            theme: preferences.theme,
            showsIgnore: preferences.showIgnoreButton && titleID != nil,
            prompt: prompt,
            onToastPointer: { inside in
                if inside { toast.pointerEntered() } else { toast.pointerLeft() }
            },
            onDismiss: { toast.dismiss() },
            onIgnore: {
                if let titleID { ignores.ignore(titleID) }
                toast.dismiss()
            },
            onPromptPointer: { inside in prompt.pointerChanged(inside: inside) },
            onTurnOn: {
                preferences.showToast = true
                prompt.close()
            },
            onNotNow: { prompt.close() })
    }

    /// Desktop's `enabled && imdbId && !ignored` fetch. The key changes when the card is switched on or the title changes.
    private var fetchKey: String {
        "\(preferences.showToast)|\(titleID ?? "")"
    }

    @MainActor private func loadGuide() async {
        guide = nil
        guard preferences.showToast, let titleID, !ignores.isIgnored(titleID) else { return }
        let loaded = await HarborAdvisoryRatings.shared.guide(titleID)
        if !Task.isCancelled { guide = loaded }
    }

    @MainActor private func updateToast() {
        toast.update(enabled: preferences.showToast, ready: triggerReady)
    }

    /// Desktop resets the timeline when the source changes, and marks the new source started if it is already playing.
    @MainActor private func restartForSource() {
        guide = nil
        toast = ContentAdvisoryToastState()
        sourceStarted = playing
        updateToast()
    }

    @MainActor private func applyPrompt(ready: Bool) {
        switch ContentAdvisory.promptDecision(seen: preferences.nudgeSeen, toastOn: preferences.showToast, ready: ready) {
        case .none: break
        case .markSeen: preferences.markNudgeSeen()
        case .show:
            preferences.markNudgeSeen()
            prompt.show()
        }
    }

    /// Waits for the current step of the toast timeline. Any change to the state cancels the wait and starts the next one.
    @MainActor private func runToast() async {
        let step = toast
        guard let delay = step.pendingDelay else { return }
        do { try await Task.sleep(for: .seconds(delay)) } catch { return }
        switch step.phase {
        case .holding: toast.holdElapsed()
        case .collapsing: toast.exitElapsed()
        case .idle, .done: break
        }
    }

    @MainActor private func runPrompt() async {
        let step = prompt
        guard let delay = step.pendingDelay else { return }
        do { try await Task.sleep(for: .seconds(delay)) } catch { return }
        switch step.phase {
        case .visible: prompt.holdElapsed()
        case .exiting: prompt.exitElapsed()
        case .idle: break
        }
    }
}

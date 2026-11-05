import SwiftUI

/// What Desktop's default player hotkeys (`lib/hotkeys.ts`) do on an iPad with a hardware keyboard.
/// The bindings are Desktop's defaults; remapping them is not ported.
enum PlayerShortcut: String, CaseIterable, Identifiable, Sendable {
    case playPause, seekBack, seekForward, seekBackShort, seekForwardShort, seekBack30, seekForward30
    case start, end, volumeUp, volumeDown, mute, subtitleDelayDown, subtitleDelayUp, subtitleDelayDownFine, subtitleDelayUpFine, stats, close
    var id: String { rawValue }

    var key: KeyEquivalent {
        switch self {
        case .playPause: .space
        case .seekBack, .seekBackShort: .leftArrow
        case .seekForward, .seekForwardShort: .rightArrow
        case .seekBack30: KeyEquivalent(",")
        case .seekForward30: KeyEquivalent(".")
        case .start: .home
        case .end: .end
        case .volumeUp: .upArrow
        case .volumeDown: .downArrow
        case .mute: KeyEquivalent("m")
        case .subtitleDelayDown: KeyEquivalent("z")
        case .subtitleDelayUp: KeyEquivalent("x")
        case .subtitleDelayDownFine: KeyEquivalent("z")
        case .subtitleDelayUpFine: KeyEquivalent("x")
        case .stats: KeyEquivalent("i")
        case .close: .escape
        }
    }
    var modifiers: EventModifiers {
        switch self {
        case .seekBackShort, .seekForwardShort, .subtitleDelayDownFine, .subtitleDelayUpFine: .shift
        default: []
        }
    }

    /// Seconds a seek shortcut moves; the player's own jump setting is Desktop's "seek step".
    func seekSeconds(back: Double, forward: Double, short: Double = 5) -> Double? {
        switch self {
        case .seekBack: -back
        case .seekForward: forward
        case .seekBackShort: -short
        case .seekForwardShort: short
        case .seekBack30: -30
        case .seekForward30: 30
        default: nil
        }
    }
}

/// Invisible buttons that carry the keyboard shortcuts, so they work without any visible control.
struct PlayerKeyboardShortcuts: View {
    let state: PlayerState
    let enabled: Bool
    let seekBack: Double
    let seekForward: Double
    let jump: (Double) -> Void
    let togglePause: () -> Void
    let close: () -> Void

    var body: some View {
        ZStack {
            ForEach(PlayerShortcut.allCases) { shortcut in
                Button { perform(shortcut) } label: { Color.clear }
                    .keyboardShortcut(shortcut.key, modifiers: shortcut.modifiers)
            }
        }
        .frame(width: 0, height: 0).opacity(0).allowsHitTesting(false).accessibilityHidden(true).disabled(!enabled)
    }

    private func perform(_ shortcut: PlayerShortcut) {
        if let seconds = shortcut.seekSeconds(back: seekBack, forward: seekForward) { jump(seconds); return }
        switch shortcut {
        case .playPause: togglePause()
        case .start: state.controller?.run(["seek", "0", "absolute+exact"])
        case .end: if state.duration > 1 { state.controller?.run(["seek", String(max(0, state.duration - 1)), "absolute+exact"]) }
        case .volumeUp: state.controller?.run(["add", "volume", "5"])
        case .volumeDown: state.controller?.run(["add", "volume", "-5"])
        case .mute: state.controller?.set("mute", state.muted ? "no" : "yes")
        case .subtitleDelayDown: state.controller?.run(["add", "sub-delay", "-0.1"])
        case .subtitleDelayUp: state.controller?.run(["add", "sub-delay", "0.1"])
        // Shift halves the step, as on Desktop.
        case .subtitleDelayDownFine: state.controller?.run(["add", "sub-delay", "-0.05"])
        case .subtitleDelayUpFine: state.controller?.run(["add", "sub-delay", "0.05"])
        case .stats: PlaybackPreferences.shared.options.showStats.toggle()
        case .close: close()
        default: break
        }
    }
}

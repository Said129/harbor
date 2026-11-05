import SwiftUI

/// Desktop's "Still watching?" check-in (`views/player/hooks/use-still-watching.ts`): after several
/// episodes start by themselves with no input, playback pauses to ask before the next one.
struct StillWatchingCounter: Equatable, Sendable {
    private(set) var runs = 0

    /// Whether the next automatic episode must wait for an answer. A free pass counts one run.
    mutating func gate(enabled: Bool, threshold: Int) -> Bool {
        guard enabled, threshold > 0 else { return false }
        if runs + 1 >= threshold { return true }
        runs += 1
        return false
    }
    /// Any touch or answer starts the count again.
    mutating func reset() { runs = 0 }
}

/// One counter for the whole app: each episode is a new player, and the count must survive the change.
@MainActor
final class StillWatching {
    static let shared = StillWatching()
    private var counter = StillWatchingCounter()
    func gate(enabled: Bool, threshold: Int) -> Bool { counter.gate(enabled: enabled, threshold: threshold) }
    func reset() { counter.reset() }
}

/// Desktop's prompt: Keep watching, or Stop with a 45 second countdown that stops by itself.
struct StillWatchingPrompt: View {
    static let timeoutSeconds = 45
    let show: String
    let nextLabel: String?
    let keepWatching: () -> Void
    let stop: () -> Void
    @State private var remaining = StillWatchingPrompt.timeoutSeconds

    var body: some View {
        ZStack {
            Color.black.opacity(0.7).ignoresSafeArea().accessibilityHidden(true)
            VStack(spacing: 0) {
                Text(DesktopInterfaceText.value("Still watching?")).font(HarborTheme.displayFont(27)).multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                Text(nextLabel.map { "\(show) · \($0)" } ?? show).font(HarborTheme.font(14)).foregroundStyle(.white.opacity(0.6))
                    .multilineTextAlignment(.center).padding(.top, 8)
                VStack(spacing: 10) {
                    Button(action: keepWatching) {
                        Text(DesktopInterfaceText.value("Keep watching")).font(HarborTheme.font(15, weight: .semibold)).frame(maxWidth: .infinity, minHeight: 48)
                            .foregroundStyle(.black).background(.white, in: .rect(cornerRadius: 12))
                    }.accessibilityIdentifier("still-watching-continue")
                    Button(action: stop) {
                        Text(DesktopInterfaceText.value("Stop ({n})", variables: ["n": String(remaining)])).font(HarborTheme.font(15, weight: .medium)).monospacedDigit()
                            .frame(maxWidth: .infinity, minHeight: 48).foregroundStyle(.white.opacity(0.85))
                            .background(.white.opacity(0.08), in: .rect(cornerRadius: 12))
                            .overlay { RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.15), lineWidth: 1) }
                    }.accessibilityIdentifier("still-watching-stop")
                }.padding(.top, 28)
            }.padding(.horizontal, 28).padding(.vertical, 32).frame(maxWidth: 420)
                .background(Color(white: 0.04).opacity(0.85), in: .rect(cornerRadius: 16))
                .overlay { RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.1), lineWidth: 1) }.padding(.horizontal, 24)
        }
        .buttonStyle(.plain).accessibilityElement(children: .contain).accessibilityIdentifier("still-watching-prompt")
        .task {
            while remaining > 0, !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                if !Task.isCancelled { remaining -= 1 }
            }
            if remaining == 0, !Task.isCancelled { stop() }
        }
    }
}

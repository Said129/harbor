import SwiftUI

struct PlayerSkipControl: View {
    let segment: SkipSegment
    let skip: () -> Void
    let dismiss: () -> Void
    var body: some View {
        HStack(spacing: 0) {
            Button(action: skip) { Label(segment.label, systemImage: "forward.end.fill").font(.subheadline.weight(.semibold)).padding(.horizontal, 16).frame(minHeight: 44) }
                .accessibilityIdentifier("player-skip-intro")
            Button(action: dismiss) { Image(systemName: "xmark").frame(width: 44, height: 44) }.accessibilityLabel(DesktopInterfaceText.value("Dismiss"))
                .accessibilityIdentifier("player-skip-dismiss")
        }.buttonStyle(.plain).foregroundStyle(.white).background(.black.opacity(0.8), in: .capsule)
            .overlay { Capsule().stroke(.white.opacity(0.25), lineWidth: 1) }.fixedSize(horizontal: false, vertical: true)
    }
}

enum PlayerSkipAction {
    @MainActor static func perform(_ segment: SkipSegment, state: PlayerState) {
        guard state.loaded, !state.ended, !state.restarting, state.error == nil, segment.active(at: state.position),
              SkipSegment.merge([[segment]], duration: state.duration).first == segment else { return }
        state.controller?.run(["seek", String(segment.end), "absolute+exact"])
    }
}

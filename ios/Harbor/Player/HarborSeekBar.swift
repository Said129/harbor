import SwiftUI

/// Harbor's original six-point track, with a full touch target and native
/// accessibility adjustment. Only releasing a scrub sends a seek to mpv.
struct HarborSeekBar: View {
    let position: Double
    let duration: Double
    var enabled = true
    var previewOnly = false
    var editing: (Bool) -> Void = { _ in }
    var seek: (Double) -> Void = { _ in }
    @State private var scrub: Double?
    @GestureState private var dragging = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var valid: Bool { enabled && duration.isFinite && duration > 0 }
    private var displayed: Double { min(duration.isFinite ? max(0, duration) : 0, max(0, scrub ?? (position.isFinite ? position : 0))) }
    private var fraction: Double { duration.isFinite && duration > 0 ? displayed / duration : 0 }
    var body: some View {
        GeometryReader { bounds in
            let width = max(0, bounds.size.width)
            let x = width * fraction
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.15)).frame(height: dragging ? 10 : 6)
                Capsule().fill(ThemePreferences.shared.seekColor).frame(width: x, height: dragging ? 10 : 6)
                if dragging || previewOnly {
                    Circle().fill(ThemePreferences.shared.seekColor).frame(width: dragging ? 22 : 16, height: dragging ? 22 : 16)
                        .overlay { Circle().stroke(.black.opacity(0.5), lineWidth: 2) }
                        .shadow(color: .black.opacity(0.45), radius: 3, y: 2).offset(x: x - (dragging ? 11 : 8))
                }
                if dragging {
                    Text(Self.time(displayed)).font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white).padding(.horizontal, 8).padding(.vertical, 5)
                        .background(.black.opacity(0.9), in: .rect(cornerRadius: 6))
                        .overlay { RoundedRectangle(cornerRadius: 6).stroke(.white.opacity(0.1), lineWidth: 1) }
                        .fixedSize().position(x: min(max(32, x), max(32, width - 32)), y: -6)
                }
            }.frame(height: 44).contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0)
                    .updating($dragging) { _, value, _ in if valid && !previewOnly { value = true } }
                    .onChanged { value in
                        guard valid, !previewOnly, width > 0 else { return }
                        if scrub == nil { editing(true) }
                        scrub = min(1, max(0, value.location.x / width)) * duration
                    }
                    .onEnded { value in
                        guard valid, !previewOnly, width > 0 else { return }
                        seek(min(1, max(0, value.location.x / width)) * duration)
                        scrub = nil; editing(false)
                    })
                .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: dragging)
        }.frame(height: 44).opacity(valid || previewOnly ? 1 : 0.4)
            .accessibilityElement(children: .ignore).accessibilityLabel("Posición de reproducción")
            .accessibilityValue("\(Self.time(displayed)) de \(Self.time(duration))")
            .accessibilityAdjustableAction { direction in
                guard valid, !previewOnly else { return }
                let step = direction == .increment ? PlaybackPreferences.shared.options.seekForwardSeconds : -PlaybackPreferences.shared.options.seekBackSeconds
                seek(min(duration, max(0, displayed + step)))
            }.accessibilityIdentifier("player-timeline")
            .onChange(of: dragging) { _, active in if !active { scrub = nil; editing(false) } }
            .onChange(of: valid) { _, available in if !available { scrub = nil; editing(false) } }
            .onDisappear { editing(false) }
    }
    static func time(_ value: Double) -> String {
        guard value.isFinite, value >= 0, value < Double(Int.max) else { return "0:00" }
        let seconds = Int(value)
        return seconds >= 3600 ? String(format: "%d:%02d:%02d", seconds / 3600, (seconds / 60) % 60, seconds % 60) : String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

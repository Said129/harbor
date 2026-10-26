import SwiftUI

struct PosterBehaviorControls: View {
    let samples: [Media]
    @AppStorage("posterFocusedCard") private var focused = false
    @AppStorage("posterBackdropExpansion") private var expansion = false
    @AppStorage("posterDockMagnification") private var dock = false
    @AppStorage("posterDockTransitionMs") private var milliseconds = 760.0
    private func text(_ key: String) -> String { DesktopInterfaceText.value(key) }
    var body: some View {
        HarborSettingsSection(text("Card behaviour")) {
            HarborSettingsToggle(text("Focused Card"), note: text("Emphasize the selected card across the page while gently darkening and blurring the other cards."), isOn: $focused)
                .accessibilityIdentifier("poster-focused-card")
            HarborSettingsToggle(text("Expanding Cards"), note: text("Expand poster cards during keyboard or remote navigation across poster rows, using preloaded wide artwork."), isOn: $expansion)
                .accessibilityIdentifier("poster-backdrop-expansion")
            HarborSettingsToggle(text("Poster dock magnification"), note: text("Gently magnify nearby posters as you move across a poster row."), isOn: $dock)
                .accessibilityIdentifier("poster-dock-magnification")
            if dock {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text(text("Animation speed")).font(HarborTheme.font(15, weight: .medium))
                        Spacer()
                        Text(text("{ms} ms").replacingOccurrences(of: "{ms}", with: String(Int(PosterBehaviorPolicy.transitionMilliseconds(milliseconds)))))
                            .font(HarborTheme.font(15, weight: .semibold)).monospacedDigit().foregroundStyle(.secondary)
                    }
                    Text(text("How long a poster takes to grow and settle as the pointer passes it.")).font(.caption).foregroundStyle(.secondary)
                    Slider(value: Binding(get: { PosterBehaviorPolicy.transitionMilliseconds(milliseconds) }, set: { milliseconds = $0 }), in: 250...1_500, step: 50)
                        .accessibilityLabel(text("Animation speed")).accessibilityIdentifier("poster-dock-duration")
                    if milliseconds != 760 {
                        Button { milliseconds = 760 } label: { Label(text("Reset"), image: "audio-reset-sync").frame(minHeight: 44) }
                            .buttonStyle(.plain).accessibilityIdentifier("poster-dock-duration-reset")
                    }
                    Text(text("Preview")).font(HarborTheme.font(13, weight: .medium)).foregroundStyle(.secondary)
                    PosterDockPreview(samples: samples, milliseconds: milliseconds)
                }.padding(16).background(HarborTheme.surface, in: .rect(cornerRadius: 12))
            }
        }
    }
}

private struct PosterDockPreview: View {
    let samples: [Media]
    let milliseconds: Double
    @State private var pointerX: Double?
    @State private var accessibleIndex = 0
    @Environment(\.layoutDirection) private var direction
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var items: [Media] { Array(samples.prefix(4)) }
    var body: some View {
        GeometryReader { geometry in
            let width = max(1, (geometry.size.width - 36) / 4)
            HStack(alignment: .bottom, spacing: 12) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, media in
                    poster(media, index: index, width: width, viewport: geometry.size)
                }
                if items.count < 4 { Spacer(minLength: 0) }
            }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom).padding(.bottom, 7)
                .contentShape(Rectangle())
                .onContinuousHover { phase in switch phase { case .active(let point): pointerX = Double(point.x); case .ended: pointerX = nil } }
                .simultaneousGesture(DragGesture(minimumDistance: 4).onChanged { value in
                    if abs(value.translation.width) > abs(value.translation.height) { pointerX = Double(value.location.x) }
                }.onEnded { _ in pointerX = nil })
                .accessibilityElement(children: .ignore).accessibilityLabel(DesktopInterfaceText.value("Poster dock magnification"))
                .accessibilityValue(items.isEmpty ? "" : items[min(accessibleIndex, items.count - 1)].name)
                .accessibilityAdjustableAction { change in
                    guard !items.isEmpty else { return }
                    switch change { case .increment: accessibleIndex = min(items.count - 1, accessibleIndex + 1); case .decrement: accessibleIndex = max(0, accessibleIndex - 1); @unknown default: return }
                    let index = direction == .rightToLeft ? 3 - accessibleIndex : accessibleIndex
                    pointerX = Double(index) * (Double(width) + 12) + Double(width) / 2
                }
                .accessibilityIdentifier("poster-dock-preview")
        }.aspectRatio(8.0 / 3, contentMode: .fit)
    }
    private func poster(_ media: Media, index: Int, width: CGFloat, viewport: CGSize) -> some View {
        let physicalIndex = direction == .rightToLeft ? 3 - index : index
        let frame = CGRect(x: CGFloat(physicalIndex) * (width + 12), y: 0, width: width, height: width * 1.5)
        let dock = reduceMotion ? PosterDockTransform() : PosterBehaviorPolicy.dock(pointerX: pointerX, frame: frame,
            viewport: CGRect(origin: .zero, size: viewport), first: index == 0, last: index == items.count - 1, rtl: direction == .rightToLeft)
        let anchor = UnitPoint(x: dock.origin == .left ? 0 : dock.origin == .right ? 1 : 0.5, y: 1)
        return Artwork(url: media.poster, maxPixels: 500).aspectRatio(2.0 / 3, contentMode: .fit)
            .clipShape(.rect(cornerRadius: 10)).frame(width: width)
            .scaleEffect(CGFloat(dock.scale), anchor: anchor).offset(x: CGFloat(dock.x), y: CGFloat(dock.y)).zIndex(dock.zIndex)
            .animation(reduceMotion ? nil : .timingCurve(0.22, 0.61, 0.36, 1, duration: PosterBehaviorPolicy.transitionMilliseconds(milliseconds) / 1_000), value: dock)
    }
}

import SwiftUI

struct HarborSettingsSegmented<Value: Hashable>: View {
    @Binding var selection: Value
    let choices: [(String, Value)]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var coordinates
    @State private var frames: [Int: CGRect] = [:]
    @State private var thumb = CGRect.zero
    @State private var movement: Task<Void, Never>?
    private var selected: Int { choices.firstIndex { $0.1 == selection } ?? -1 }

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 6).fill(HarborTheme.ink)
                .frame(width: thumb.width, height: thumb.height)
                .offset(x: thumb.minX, y: thumb.minY).allowsHitTesting(false).accessibilityHidden(true)
            SegmentLayout {
                ForEach(choices.indices, id: \.self) { index in
                    Button { selection = choices[index].1 } label: {
                        Text(choices[index].0).font(HarborTheme.font(15, weight: .semibold)).tracking(0.15)
                            .fixedSize(horizontal: false, vertical: true).multilineTextAlignment(.center)
                            .padding(.horizontal, 16).frame(minHeight: 44)
                            .foregroundStyle(index == selected ? HarborTheme.background : ThemePreferences.shared.color("ink-subtle"))
                            .contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityAddTraits(index == selected ? [.isSelected] : [])
                        .background {
                            GeometryReader { geometry in
                                Color.clear.preference(key: SegmentFrames.self, value: [index: geometry.frame(in: .named(coordinates))])
                            }
                        }
                }
            }
        }.coordinateSpace(name: coordinates).padding(4)
            .background(HarborTheme.background, in: .rect(cornerRadius: 10))
            .onPreferenceChange(SegmentFrames.self) { next in
                frames = next
                if movement == nil { thumb = next[selected] ?? .zero }
            }
            .onChange(of: selection) { _, _ in moveThumb() }
            .onChange(of: reduceMotion) { _, reduced in
                if reduced { movement?.cancel(); movement = nil; thumb = frames[selected] ?? .zero }
            }
            .onAppear { thumb = frames[selected] ?? .zero }
            .onDisappear { movement?.cancel(); movement = nil }
    }

    private func moveThumb() {
        movement?.cancel(); movement = nil
        guard let target = frames[selected] else { return }
        guard !reduceMotion, !thumb.isEmpty, thumb != target else { thumb = target; return }
        if abs(thumb.minY - target.minY) < 0.5 {
            // Desktop stretches to cover both choices, then contracts to the new one.
            let expanded = thumb.union(target)
            withAnimation(.easeInOut(duration: 0.21)) { thumb = expanded }
            movement = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(210))
                guard !Task.isCancelled else { return }
                withAnimation(.easeInOut(duration: 0.21)) { thumb = target }
                try? await Task.sleep(for: .milliseconds(210))
                guard !Task.isCancelled else { return }
                movement = nil
                thumb = frames[selected] ?? target
            }
        } else {
            withAnimation(.easeInOut(duration: 0.32)) { thumb = target }
            movement = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(320))
                guard !Task.isCancelled else { return }
                movement = nil
                thumb = frames[selected] ?? target
            }
        }
    }
}

private struct SegmentFrames: PreferenceKey {
    static let defaultValue: [Int: CGRect] = [:]
    static func reduce(value: inout [Int: CGRect], nextValue: () -> [Int: CGRect]) { value.merge(nextValue(), uniquingKeysWith: { _, next in next }) }
}

private struct SegmentLayout: Layout {
    private func positions(_ width: CGFloat, _ subviews: Subviews) -> [(CGPoint, CGSize)] {
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        return subviews.map { view in
            let size = view.sizeThatFits(ProposedViewSize(width: width, height: nil))
            if x > 0 && x + size.width > width { x = 0; y += rowHeight + 2; rowHeight = 0 }
            let point = CGPoint(x: x, y: y)
            x += size.width + 2; rowHeight = max(rowHeight, size.height)
            return (point, size)
        }
    }
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let naturalWidth = subviews.map { $0.sizeThatFits(.unspecified).width }.reduce(0, +) + CGFloat(max(0, subviews.count - 1)) * 2
        let items = positions(proposal.width ?? naturalWidth, subviews)
        return CGSize(width: items.map { $0.0.x + $0.1.width }.max() ?? 0, height: items.map { $0.0.y + $0.1.height }.max() ?? 0)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (view, item) in zip(subviews, positions(bounds.width, subviews)) {
            view.place(at: CGPoint(x: bounds.minX + item.0.x, y: bounds.minY + item.0.y), anchor: .topLeading, proposal: ProposedViewSize(item.1))
        }
    }
}

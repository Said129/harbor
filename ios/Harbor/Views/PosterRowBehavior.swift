import SwiftUI
import Observation

@MainActor @Observable final class PosterAttentionState {
    static let shared = PosterAttentionState()
    enum Input: Equatable { case keyboard, pointer }
    var input: Input = .keyboard
    private(set) var active: UUID?
    func focus(_ id: UUID, enabled: Bool, focused: Bool) {
        if enabled && focused && input == .keyboard { if active != id { active = id } }
        else if active == id { active = nil }
    }
    func pointerMoved() { if input != .pointer { input = .pointer }; if active != nil { active = nil } }
}

@MainActor @Observable final class PosterRowContext {
    struct Reveal: Hashable { let card: UUID; let token = UUID() }
    let id = UUID()
    var frames: [UUID: CGRect] = [:]
    var viewport: CGRect = .zero
    var pointerX: Double?
    var dragging = false
    var reveal: Reveal?
    func dock(_ card: UUID, rtl: Bool) -> PosterDockTransform {
        guard let frame = frames[card] else { return .init() }
        let order = frames.sorted { rtl ? $0.value.midX > $1.value.midX : $0.value.midX < $1.value.midX }
        return PosterBehaviorPolicy.dock(pointerX: pointerX, frame: frame, viewport: viewport,
            first: order.first?.key == card, last: order.last?.key == card, rtl: rtl)
    }
    func requestReveal(_ card: UUID) { if !dragging { reveal = Reveal(card: card) } }
    func cancelReveal(_ card: UUID) { if reveal?.card == card { reveal = nil } }
}

private struct PosterRowContextKey: EnvironmentKey { static let defaultValue: PosterRowContext? = nil }
extension EnvironmentValues {
    var posterRowContext: PosterRowContext? {
        get { self[PosterRowContextKey.self] }
        set { self[PosterRowContextKey.self] = newValue }
    }
}
struct PosterRowFrames: PreferenceKey {
    static let defaultValue: [UUID: CGRect] = [:]
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) { value.merge(nextValue()) { _, next in next } }
}

@MainActor private struct PosterRowBehavior: ViewModifier {
    @AppStorage("posterBackdropExpansion") private var expansion = false
    @AppStorage("posterDockMagnification") private var dock = false
    @AppStorage("rowCardStyle") private var style = "poster"
    @State private var row: PosterRowContext
    init(context: PosterRowContext?) { _row = State(initialValue: context ?? PosterRowContext()) }
    private var active: Bool { style != "tv" && (expansion || dock) }
    func body(content: Content) -> some View {
        ScrollViewReader { proxy in
            content.environment(\.posterRowContext, row).coordinateSpace(name: row.id)
                .scrollClipDisabled(active)
                .background {
                    if active {
                        GeometryReader { geometry in
                            Color.clear.onAppear { row.viewport = CGRect(origin: .zero, size: geometry.size) }
                                .onChange(of: geometry.size) { _, size in row.viewport = CGRect(origin: .zero, size: size) }
                        }
                    }
                }
                .onPreferenceChange(PosterRowFrames.self) { if row.frames != $0 { row.frames = $0 } }
                .onContinuousHover(coordinateSpace: .named(row.id)) { phase in
                    switch phase {
                    case .active(let point):
                        PosterAttentionState.shared.pointerMoved()
                        if active && dock { row.pointerX = Double(point.x) }
                    case .ended: row.pointerX = nil
                    }
                }
                .onKeyPress(phases: .down) { _ in if PosterAttentionState.shared.input != .keyboard { PosterAttentionState.shared.input = .keyboard }; return .ignored }
                .simultaneousGesture(DragGesture(minimumDistance: 10).onChanged { _ in
                    if active && !row.dragging { row.dragging = true; row.reveal = nil }
                }.onEnded { _ in row.dragging = false }, including: active ? .all : .none)
                .onChange(of: active) { _, enabled in if !enabled { row.pointerX = nil; row.reveal = nil } }
                .task(id: row.reveal) {
                    guard let request = row.reveal, active else { return }
                    for _ in 0..<14 {
                        guard !Task.isCancelled, !row.dragging, row.reveal == request else { return }
                        if let frame = row.frames[request.card], abs(PosterBehaviorPolicy.scrollDelta(card: frame, viewport: row.viewport, gutter: 12)) > 0.5 {
                            proxy.scrollTo(request.card, anchor: .center)
                        }
                        try? await Task.sleep(for: .milliseconds(40))
                    }
                }
                .onDisappear { row.pointerX = nil; row.reveal = nil }
        }
    }
}
extension View {
    func posterRowBehavior(context: PosterRowContext? = nil) -> some View { modifier(PosterRowBehavior(context: context)) }
}

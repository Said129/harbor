import SwiftUI

struct SubtitleTimingView: View {
    let state: PlayerState
    @State private var custom = "25"
    @State private var inputError: String?
    @State private var customOpen = false
    @State private var automatic = false
    @State private var requested: Choice?
    @FocusState private var editingCustom: Bool

    private struct Choice { let value: Double; let automatic: Bool }

    private var reason: String? { SubtitleTiming.unavailable(state) }
    private var disabled: Bool { reason != nil || state.subtitleChanging }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(text("Choose the frame rate the subtitle was authored for."))
                    .font(HarborTheme.font(12)).foregroundStyle(.secondary)
                Menu {
                    Button(text("No correction (default)")) { apply(0) }
                    Button(autoLabel) { if let fps = state.videoFPS { apply(fps, automatic: true) } }.disabled(state.videoFPS == nil)
                    ForEach(SubtitleTiming.presets) { preset in Button(preset.label) { apply(preset.value) } }
                    Button(text("Custom...")) {
                        custom = SubtitleTiming.format((state.subtitleFPS ?? 0) > 0 ? state.subtitleFPS : state.videoFPS ?? 25)
                        customOpen = true; editingCustom = true
                    }
                } label: {
                    HStack(spacing: 12) {
                        Text(selectedLabel).font(HarborTheme.font(13, weight: .medium))
                        Spacer(minLength: 0)
                        if state.subtitleChanging { ProgressView().controlSize(.small).accessibilityLabel(text("Saving")) }
                        Image("desktop-chevron-right").resizable().scaledToFit().frame(width: 14, height: 14).rotationEffect(.degrees(90))
                    }.padding(.horizontal, 12).frame(minHeight: 44)
                        .background(HarborTheme.surface, in: .rect(cornerRadius: 6))
                }.disabled(disabled).opacity(disabled ? 0.45 : 1).accessibilityIdentifier("subtitle-fps-choice")
                if customOpen {
                    HStack(spacing: 8) {
                        TextField(text("Custom subtitle FPS"), text: Binding(get: { custom }, set: { custom = String($0.prefix(16)); inputError = nil }))
                            .keyboardType(.decimalPad).focused($editingCustom).multilineTextAlignment(.trailing)
                            .font(HarborTheme.font(13)).monospacedDigit().padding(.horizontal, 12).frame(minHeight: 44)
                            .background(HarborTheme.surface, in: .rect(cornerRadius: 6))
                            .accessibilityIdentifier("subtitle-fps-custom").onSubmit(commitCustom)
                        Button(action: commitCustom) {
                            Image("subtitle-fps-apply").resizable().scaledToFit().frame(width: 15, height: 15)
                                .foregroundStyle(HarborTheme.background).frame(width: 44, height: 44)
                                .background(HarborTheme.ink, in: .rect(cornerRadius: 6))
                        }.buttonStyle(.plain).accessibilityLabel(text("Apply custom subtitle FPS"))
                    }.disabled(disabled)
                }
                Divider().padding(.top, 4)
                HStack {
                    Text(text("Video FPS")).foregroundStyle(.secondary)
                    Spacer()
                    Text(SubtitleTiming.format(state.videoFPS)).fontWeight(.semibold).monospacedDigit()
                }
                HStack {
                    Text(text("Subtitle source FPS")).foregroundStyle(.secondary)
                    Spacer()
                    Text(sourceFPSLabel).fontWeight(.semibold).monospacedDigit()
                }
                if let message = inputError ?? state.subtitleIssue ?? reason {
                    Text(message).foregroundStyle(inputError != nil || state.subtitleIssue != nil ? Color.red : HarborTheme.ink.opacity(0.55))
                        .accessibilityIdentifier("subtitle-fps-message")
                }
            }.font(HarborTheme.font(12)).padding(18)
        }.background(HarborTheme.background)
            .navigationTitle(text("Subtitle FPS")).navigationBarTitleDisplayMode(.inline)
            .onAppear(perform: refresh)
            .onChange(of: state.primarySubtitle?.id) { _, _ in refresh() }
            .onChange(of: state.subtitleChanging) { _, _ in confirmChoice() }
            .onChange(of: state.subtitleFPS) { _, _ in confirmChoice() }
    }

    private func text(_ original: String) -> String { DesktopInterfaceText.value(original) }
    private var autoLabel: String {
        let label = text("Auto (match video)")
        return state.videoFPS.map { label + " · " + SubtitleTiming.format($0) } ?? label
    }
    private var sourceFPSLabel: String {
        guard let value = state.subtitleFPS else { return "—" }
        return value == 0 ? text("No correction") : SubtitleTiming.format(value)
    }
    private var selectedLabel: String {
        if customOpen { return text("Custom...") }
        guard let value = state.subtitleFPS, value > 0 else { return text("No correction (default)") }
        if automatic && SubtitleTiming.matches(value, state.videoFPS) { return autoLabel }
        return SubtitleTiming.presets.first { SubtitleTiming.matches(value, $0.value) }?.label ?? text("Custom...")
    }
    private func refresh() {
        requested = nil; inputError = nil
        let value = state.subtitleFPS
        automatic = SubtitleTiming.matches(value, state.videoFPS)
        customOpen = (value ?? 0) > 0 && !automatic && !SubtitleTiming.presets.contains { SubtitleTiming.matches(value, $0.value) }
        custom = SubtitleTiming.format((value ?? 0) > 0 ? value : state.videoFPS ?? 25)
    }
    private func apply(_ value: Double, automatic: Bool = false) {
        guard !disabled else { return }
        inputError = nil; requested = Choice(value: value, automatic: automatic)
        editingCustom = false
        state.controller?.applySubtitleFPS(value)
    }
    private func confirmChoice() {
        guard !state.subtitleChanging, let requested else { return }
        if state.subtitleIssue != nil { self.requested = nil; return }
        guard SubtitleTiming.matches(state.subtitleFPS, requested.value) else { return }
        automatic = requested.automatic
        customOpen = requested.value > 0 && !automatic && !SubtitleTiming.presets.contains { SubtitleTiming.matches(requested.value, $0.value) }
        self.requested = nil
    }
    private func commitCustom() {
        guard let value = SubtitleTiming.parse(custom) else { inputError = text("Enter an FPS from 1 to 240."); return }
        apply(value)
    }
}

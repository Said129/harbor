import SwiftUI

private struct PlayerSurface: UIViewControllerRepresentable {
    let source: PlaybackSource
    let startMs: Double
    let state: PlayerState
    func makeUIViewController(context: Context) -> MPVController { MPVController(source: source, state: state, startMs: startMs) }
    func updateUIViewController(_ controller: MPVController, context: Context) {}
    static func dismantleUIViewController(_ controller: MPVController, coordinator: ()) { controller.close() }
}

struct PlayerView: View {
    let session: PlaybackSession
    let resume: ResumeStore
    let title: String
    var media: Media? = nil
    var library: LibraryModel? = nil
    @State private var state = PlayerState()
    @State private var seek: Double = 0
    @State private var editingSeek = false
    @State private var progressError: String?
    @State private var lastSavedMs: Double = 0
    @State private var controlsVisible = true
    @State private var hideRevision = 0
    @State private var settingsPage: PlayerSettingsPage?
    @State private var previousIdleTimer = false
    @State private var active = false
    @Bindable private var preferences = PlaybackPreferences.shared
    @AppStorage("mpvHwdec") private var hardwareDecoding = HardwareDecoding.auto
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            PlayerSurface(source: session.source, startMs: session.startMs, state: state).ignoresSafeArea().accessibilityHidden(true)
            // This sibling receives taps only on the video, so a transport
            // button or a slider never also toggles the entire interface.
            Color.clear.ignoresSafeArea().contentShape(Rectangle())
                .onTapGesture { withAnimation(.easeInOut(duration: 0.2)) { controlsVisible.toggle() }; restartHideTimer() }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Reproductor. \(controlsVisible ? "Ocultar" : "Mostrar") controles")
                .accessibilityValue(state.renderReady ? "Preparado" : "Iniciando")
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { controlsVisible.toggle(); restartHideTimer() }
                .accessibilityIdentifier("player-surface")
            VStack(spacing: 12) {
                if (state.buffering || !state.loaded) && !state.ended && state.error == nil { ProgressView().tint(.white) }
                if state.ended && state.error == nil { Text("La reproducción ha terminado.").padding().background(.black.opacity(0.6)) }
                if let error = state.error { Text(error).padding().background(.black.opacity(0.8)).accessibilityIdentifier("player-error") }
                if let error = progressError ?? session.storageWarning { Text(error).font(.caption).padding().background(.black.opacity(0.8)) }
            }.padding().allowsHitTesting(false)
            if controlsVisible { controls.transition(.opacity) }
        }
        .foregroundStyle(.white)
        .statusBarHidden(!controlsVisible)
        .persistentSystemOverlays(controlsVisible ? .visible : .hidden)
        .sheet(item: $settingsPage, onDismiss: restartHideTimer) { page in
            NavigationStack {
                PlayerSettingsView(page: page, state: state)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Listo") { settingsPage = nil } } }
            }.tint(HarborTheme.accent).preferredColorScheme(.dark)
        }
        .task(id: hideRevision) {
            guard canAutoHide else { return }
            do { try await Task.sleep(for: .seconds(4)) } catch { return }
            guard canAutoHide else { return }
            withAnimation(.easeInOut(duration: 0.2)) { controlsVisible = false }
        }
        .task {
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(4)) }
                catch { return }
                if state.loaded && !state.paused { await checkpoint(exiting: false) }
            }
        }
        .onChange(of: state.paused) { _, paused in
            if paused { controlsVisible = true; saveCheckpoint(exiting: false) }
            restartHideTimer(); updateIdleTimer()
        }
        .onChange(of: state.loaded) { _, _ in restartHideTimer(); updateIdleTimer() }
        .onChange(of: state.buffering) { _, _ in restartHideTimer() }
        .onChange(of: state.error) { _, error in if error != nil { controlsVisible = true }; restartHideTimer() }
        .onChange(of: preferences.options) { old, new in
            let previous = Dictionary(uniqueKeysWithValues: old.mpvOptions)
            for (name, value) in new.mpvOptions where previous[name] != value { state.controller?.set(name, value) }
            if !new.autoHideControls { controlsVisible = true }
            restartHideTimer(); updateIdleTimer()
        }
        .onChange(of: voiceOver) { _, enabled in if enabled { controlsVisible = true }; restartHideTimer() }
        .onChange(of: hardwareDecoding) { _, mode in state.controller?.set("hwdec", mode.mpvValue) }
        .onChange(of: state.ended) { _, ended in if ended { controlsVisible = true; saveCheckpoint(exiting: false) }; updateIdleTimer() }
        .onChange(of: scenePhase) { _, phase in if phase != .active { saveCheckpoint(exiting: false) }; restartHideTimer(); updateIdleTimer() }
        .onAppear { previousIdleTimer = UIApplication.shared.isIdleTimerDisabled; active = true; updateIdleTimer() }
        .onDisappear { active = false; UIApplication.shared.isIdleTimerDisabled = previousIdleTimer; saveCheckpoint(exiting: true) }
    }

    private var canAutoHide: Bool {
        controlsVisible && preferences.options.autoHideControls && state.loaded && !state.paused && !state.buffering && !state.ended && state.error == nil && !editingSeek && settingsPage == nil && !voiceOver && scenePhase == .active
    }
    private func restartHideTimer() { hideRevision += 1 }
    private func updateIdleTimer() {
        guard active else { return }
        UIApplication.shared.isIdleTimerDisabled = previousIdleTimer || (preferences.options.keepScreenAwake && state.loaded && !state.paused && !state.ended && scenePhase == .active)
    }

    private var controls: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Button { dismiss() } label: { Image(systemName: "chevron.down").frame(width: 44, height: 44) }
                    .accessibilityLabel("Cerrar reproductor").accessibilityIdentifier("player-close")
                Text(title).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                Button { settingsPage = .audio } label: { Image(systemName: "waveform").frame(width: 44, height: 44) }.accessibilityLabel("Audio")
                Button { settingsPage = .subtitles } label: { Image(systemName: "captions.bubble").frame(width: 44, height: 44) }.accessibilityLabel("Subtítulos")
                Button { settingsPage = .options } label: { Image("nav-settings").frame(width: 44, height: 44) }
                    .accessibilityLabel("Opciones del reproductor").accessibilityIdentifier("player-options")
            }.padding(.horizontal, 8).padding(.vertical, 4).background(.black.opacity(0.7))
            Spacer()
            VStack(spacing: 4) {
                Slider(value: Binding(get: { editingSeek ? seek : min(state.position, max(1, state.duration)) }, set: { seek = $0 }), in: 0...max(1, state.duration), onEditingChanged: { editing in
                    editingSeek = editing
                    if !editing { state.controller?.run(["seek", String(seek), "absolute+exact"]) }
                    restartHideTimer()
                }).disabled(state.duration <= 0 || !state.loaded).accessibilityLabel("Posición de reproducción")
                HStack(spacing: 8) {
                    Text(time(state.position)).monospacedDigit().accessibilityLabel("Tiempo reproducido").accessibilityIdentifier("player-position")
                    Spacer(minLength: 0)
                    Button { jump(-preferences.options.seekBackSeconds) } label: { Image(systemName: "gobackward").overlay(Text("\(Int(preferences.options.seekBackSeconds))").font(.system(size: 9)).offset(y: 2)) }.frame(width: 44, height: 44).accessibilityLabel("Retroceder \(Int(preferences.options.seekBackSeconds)) segundos")
                    Button {
                        if state.ended { state.controller?.replay() }
                        else { state.controller?.run(["cycle", "pause"]) }
                        restartHideTimer()
                    } label: { Image(systemName: state.ended ? "arrow.counterclockwise" : state.paused ? "play.fill" : "pause.fill").font(.title) }
                        .frame(width: 44, height: 44).accessibilityLabel(state.ended ? "Repetir" : state.paused ? "Reproducir" : "Pausar").accessibilityIdentifier("player-pause")
                    Button { jump(preferences.options.seekForwardSeconds) } label: { Image(systemName: "goforward").overlay(Text("\(Int(preferences.options.seekForwardSeconds))").font(.system(size: 9)).offset(y: 2)) }.frame(width: 44, height: 44).accessibilityLabel("Avanzar \(Int(preferences.options.seekForwardSeconds)) segundos")
                    Spacer(minLength: 0)
                    Button { settingsPage = .video } label: { Image(systemName: "slider.horizontal.3").frame(width: 36, height: 44) }.accessibilityLabel("Imagen y formato").accessibilityIdentifier("player-picture")
                    Button("\(state.speed.formatted())×") { settingsPage = .playback }.accessibilityLabel("Velocidad").frame(minWidth: 32, minHeight: 44)
                    Text(time(state.duration)).monospacedDigit()
                }.font(.caption)
            }.padding(.horizontal).padding(.bottom, 8).background(.black.opacity(0.7))
        }
    }
    private func jump(_ seconds: Double) { state.controller?.run(["seek", String(seconds), "relative"]); restartHideTimer() }

    @MainActor private func snapshot(exiting: Bool) -> ResumeSnapshot? {
        guard session.progressEnabled, state.hasPosition, state.position.isFinite, state.duration.isFinite else { return nil }
        return ResumeSnapshot(positionMs: state.position * 1000, durationMs: state.duration * 1000, timestampMs: UInt64(max(0, Date().timeIntervalSince1970 * 1000)), exiting: exiting)
    }

    @MainActor private func saveCheckpoint(exiting: Bool) {
        guard let value = snapshot(exiting: exiting) else { return }
        Task { await persist(value) }
    }

    @MainActor private func checkpoint(exiting: Bool) async {
        guard let value = snapshot(exiting: exiting), abs(value.positionMs - lastSavedMs) >= 1500 else { return }
        await persist(value)
    }

    @MainActor private func persist(_ value: ResumeSnapshot) async {
        do {
            if try await resume.save(session.target, snapshot: value) {
                lastSavedMs = value.positionMs
                progressError = nil
                Diagnostics.shared.record(.progressSaved)
            }
        } catch {
            progressError = safeMessage(error)
            Diagnostics.shared.recordFailure(error)
        }
        if let media, let library { await library.saveProgress(media, target: session.target, snapshot: value) }
    }
    private func time(_ value: Double) -> String {
        guard value.isFinite && value >= 0 && value < Double(Int.max) else { return "0:00" }
        let seconds = Int(value)
        return seconds >= 3600 ? String(format: "%d:%02d:%02d", seconds / 3600, (seconds / 60) % 60, seconds % 60) : String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

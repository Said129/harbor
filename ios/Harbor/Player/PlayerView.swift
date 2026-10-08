import SwiftUI

private struct PlayerSurface: UIViewControllerRepresentable {
    let source: PlaybackSource
    let startMs: Double
    let preservePosition: Bool
    let state: PlayerState
    func makeUIViewController(context: Context) -> MPVController { MPVController(source: source, state: state, startMs: startMs, preservePosition: preservePosition) }
    func updateUIViewController(_ controller: MPVController, context: Context) {}
    static func dismantleUIViewController(_ controller: MPVController, coordinator: ()) { controller.close() }
}

private struct PlayerGlyph: View {
    let name: String
    var size: CGFloat = 24
    var body: some View {
        Image("player-" + name).resizable().scaledToFit().frame(width: size, height: size).accessibilityHidden(true)
    }
}

private struct PlayerSeekGlyph: View {
    let direction: String
    let seconds: Double
    private static let originalIntervals: Set<Double> = [1, 3, 5, 10, 15, 30, 60, 90]
    var body: some View {
        if Self.originalIntervals.contains(seconds) {
            PlayerGlyph(name: "seek-" + direction + "-" + String(Int(seconds)), size: 26)
        } else {
            PlayerGlyph(name: "seek-" + direction + "-custom", size: 26)
                .overlay {
                    Text(seconds.formatted(.number.precision(.fractionLength(0...1))))
                        .font(.system(size: 9, weight: .semibold)).monospacedDigit().offset(y: 3)
                        .accessibilityHidden(true)
                }
        }
    }
}

struct PlayerView: View {
    let session: PlaybackSession
    let resume: ResumeStore
    let title: String
    var media: Media? = nil
    var library: LibraryModel? = nil
    var changeEpisode: ((Episode) -> Void)? = nil
    var changeSource: ((ResumeSnapshot?) -> Void)? = nil
    @State private var state = PlayerState()
    @State private var editingSeek = false
    @State private var progressError: String?
    @State private var lastSavedMs: Double = 0
    @State private var controlsVisible = true
    @State private var hideRevision = 0
    @State private var settingsPage: PlayerSettingsPage?
    @State private var showEpisodes = false
    @State private var pendingEpisode: Episode?
    @State private var episodeChanging = false
    @State private var sourceChanging = false
    @State private var retrying = false
    @State private var pendingSourceChange = false
    @State private var autoNextCancelled = false
    @State private var adjacent: (previous: Episode?, next: Episode?) = (nil, nil)
    @State private var previousIdleTimer = false
    @State private var active = false
    @Bindable private var preferences = PlaybackPreferences.shared
    @AppStorage("mpvHwdec") private var hardwareDecoding = HardwareDecoding.auto
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    var body: some View {
        withLifecycle(surface
            .foregroundStyle(.white)
            .statusBarHidden(!controlsVisible)
            .persistentSystemOverlays(controlsVisible ? .visible : .hidden)
            .sheet(item: $settingsPage, onDismiss: {
                restartHideTimer()
                if pendingSourceChange { pendingSourceChange = false; requestSourceChange() }
            }) { page in
                NavigationStack {
                    Group {
                        if page == .audio || page == .subtitles { PlayerTrackPanel(page: page, state: state) }
                        else { PlayerSettingsView(page: page, state: state, changeSource: changeSource == nil ? nil : {
                            pendingSourceChange = true
                            settingsPage = nil
                        }) }
                    }
                        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Listo") { settingsPage = nil } } }
                }.tint(HarborTheme.accent).preferredColorScheme(.dark).presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showEpisodes, onDismiss: {
                restartHideTimer()
                if let episode = pendingEpisode { pendingEpisode = nil; requestEpisode(episode) }
            }) { episodePanel })
    }

    private var surface: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            PlayerSurface(source: session.source, startMs: session.startMs, preservePosition: session.preservePosition, state: state).ignoresSafeArea().accessibilityHidden(true)
            // This sibling receives taps only on the video, so a transport
            // button or a slider never also toggles the entire interface.
            Color.clear.ignoresSafeArea().contentShape(Rectangle())
                .onTapGesture { withAnimation(.easeInOut(duration: 0.2)) { controlsVisible.toggle() }; restartHideTimer() }
                .simultaneousGesture(MagnifyGesture().onEnded { value in
                    guard state.loaded, state.error == nil, scenePhase == .active else { return }
                    let scale = value.magnification
                    guard scale.isFinite else { return }
                    if scale < 0.9 {
                        preferences.options.fit = .original; preferences.options.zoom = 0
                    } else if scale > 1.1 {
                        preferences.options.fit = .fill; preferences.options.zoom = 0
                    } else { return }
                    restartHideTimer()
                })
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Reproductor. \(controlsVisible ? "Ocultar" : "Mostrar") controles")
                .accessibilityValue(state.renderReady ? "Preparado" : "Iniciando")
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { controlsVisible.toggle(); restartHideTimer() }
                .accessibilityIdentifier("player-surface")
            VStack(spacing: 12) {
                if state.buffering && state.loaded && !state.ended && state.error == nil { HarborLoader() }
                if state.ended && state.error == nil { Text("La reproducción ha terminado.").padding().background(.black.opacity(0.6)) }
                if let error = progressError ?? session.storageWarning { Text(error).font(.caption).padding().background(.black.opacity(0.8)) }
                if let issue = state.playbackIssue { Text(issue).font(.caption).padding().background(.black.opacity(0.8)) }
            }.padding().allowsHitTesting(false)
            if !state.loaded && !state.ended && state.error == nil { HarborPlaybackConnecting(media: media, cancelIdentifier: "player-close") { dismiss() } }
            if let error = state.error { failureNotice(error) }
            if controlsVisible && (state.loaded || state.error != nil) { controls.transition(.opacity) }
            if let next = adjacent.next, showUpNext {
                VStack {
                    Spacer()
                    HStack {
                        Spacer(minLength: 0)
                        PlayerUpNextView(episode: next, remaining: max(0, state.duration - state.position), automatic: automaticAdvanceEnabled,
                            hideSpoiler: InterfacePreferences.shared.hideSpoilers && library?.watchedEpisodes(media ?? Media(id: session.target.id, type: "series", name: title)).contains(next.watchedKey) != true,
                            play: { requestEpisode(next) }, cancel: { autoNextCancelled = true })
                    }
                }.padding(.horizontal, 12).padding(.bottom, controlsVisible ? 160 : 24).transition(.opacity)
            }
        }
    }

    private func failureNotice(_ message: String) -> some View {
        let layout = verticalSizeClass == .compact ? AnyLayout(HStackLayout(spacing: 16)) : AnyLayout(VStackLayout(spacing: 10))
        return VStack(spacing: 14) {
            Text(message).multilineTextAlignment(.center).accessibilityIdentifier("player-error")
            layout {
                if state.controller?.canRestartPlayback == true {
                    Button(retrying || state.restarting ? "Reintentando…" : "Reintentar") { requestRetry() }
                        .frame(maxWidth: .infinity)
                        .disabled(retrying || state.restarting || sourceChanging || episodeChanging)
                        .accessibilityIdentifier("player-error-retry")
                }
                if changeSource != nil {
                    Button("Cambiar fuente") { requestSourceChange() }.frame(maxWidth: .infinity)
                        .disabled(retrying || state.restarting || sourceChanging || episodeChanging)
                        .accessibilityIdentifier("player-error-change-source")
                }
                Button("Cerrar") { dismiss() }.frame(maxWidth: .infinity).accessibilityIdentifier("player-error-close")
            }.font(.subheadline.weight(.semibold)).buttonStyle(.bordered)
        }.padding(20).frame(maxWidth: 420).background(.black.opacity(0.88), in: .rect(cornerRadius: 14)).padding()
    }

    @ViewBuilder private var episodePanel: some View {
        if let media {
            NavigationStack {
                PlayerEpisodesView(media: media, current: session.target, library: library) { episode in
                    pendingEpisode = episode
                    showEpisodes = false
                }.toolbar { ToolbarItem(placement: .confirmationAction) { Button("Listo") { showEpisodes = false } } }
            }.tint(HarborTheme.accent).preferredColorScheme(.dark)
        }
    }

    private func withLifecycle<V: View>(_ content: V) -> some View {
        content.task(id: autoAdvanceReady) {
            guard autoAdvanceReady, let next = adjacent.next else { return }
            requestEpisode(next)
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
        .onChange(of: state.choosingAudioRoute) { _, _ in controlsVisible = true; restartHideTimer() }
        .onChange(of: state.pictureInPictureChanging) { _, _ in controlsVisible = true; restartHideTimer() }
        .onChange(of: state.error) { _, error in if error != nil { controlsVisible = true }; restartHideTimer() }
        .onChange(of: preferences.options) { old, new in
            let previous = Dictionary(uniqueKeysWithValues: old.mpvOptions)
            for (name, value) in new.mpvOptions where previous[name] != value { state.controller?.set(name, value) }
            if old.secondarySubtitleLanguage != new.secondarySubtitleLanguage { state.controller?.applyPreferredSecondary(reset: true) }
            if !new.autoHideControls { controlsVisible = true }
            restartHideTimer(); updateIdleTimer()
        }
        .onChange(of: voiceOver) { _, enabled in if enabled { controlsVisible = true }; restartHideTimer() }
        .onChange(of: hardwareDecoding) { _, mode in state.controller?.set("hwdec", mode.mpvValue) }
        .onChange(of: state.ended) { _, ended in
            if ended { controlsVisible = true; saveCheckpoint(exiting: false); if scenePhase != .active { autoNextCancelled = true } }
            updateIdleTimer()
        }
        .onChange(of: scenePhase) { _, phase in if phase != .active { saveCheckpoint(exiting: false) }; restartHideTimer(); updateIdleTimer() }
        .onAppear {
            adjacent = EpisodeSequence.adjacent(media?.videos ?? [], current: session.target)
            previousIdleTimer = UIApplication.shared.isIdleTimerDisabled; active = true; updateIdleTimer()
        }
        .onDisappear { active = false; UIApplication.shared.isIdleTimerDisabled = previousIdleTimer; saveCheckpoint(exiting: true) }
    }

    private var canAutoHide: Bool {
        controlsVisible && preferences.options.autoHideControls && state.loaded && !state.paused && !state.buffering && !state.ended && state.error == nil && !editingSeek && !state.choosingAudioRoute && !state.pictureInPictureChanging && settingsPage == nil && !showEpisodes && !episodeChanging && !sourceChanging && !retrying && !state.restarting && !voiceOver && scenePhase == .active
    }
    private var canChangeEpisode: Bool { changeEpisode != nil && media?.episodic == true && !(media?.videos?.isEmpty ?? true) && (library.map { $0.owner == session.owner } ?? true) }
    private var automaticAdvanceEnabled: Bool {
        preferences.options.autoPlayNextEpisode && !autoNextCancelled && EpisodeSequence.permitsAutomaticAdvance(duration: state.duration, startedAtMs: session.advanceStartedAtMs ?? session.startMs, ended: true, hasError: state.error != nil)
    }
    private var autoAdvanceReady: Bool {
        active && canChangeEpisode && adjacent.next != nil && automaticAdvanceEnabled && state.endedNaturally && !episodeChanging && !sourceChanging && !retrying && !state.restarting && !pendingSourceChange && pendingEpisode == nil && settingsPage == nil && !showEpisodes && scenePhase == .active
    }
    private var showUpNext: Bool {
        let remaining = state.duration - state.position
        let lead = EpisodeSequence.leadSeconds(setting: preferences.options.nextEpisodeLeadSeconds, duration: state.duration)
        return canChangeEpisode && !episodeChanging && !sourceChanging && !retrying && !state.restarting && !pendingSourceChange && !autoNextCancelled && state.loaded && state.error == nil && settingsPage == nil && !showEpisodes && scenePhase == .active && lead > 0 && remaining > 0.5 && remaining <= lead && !state.ended
    }
    private func requestEpisode(_ episode: Episode) {
        guard active, canChangeEpisode, !episodeChanging, !sourceChanging, !retrying, !state.restarting, episode.available, scenePhase == .active, let changeEpisode else { return }
        episodeChanging = true
        saveCheckpoint(exiting: true)
        changeEpisode(episode)
    }
    private func requestSourceChange() {
        guard active, !sourceChanging, !episodeChanging, !retrying, !state.restarting, scenePhase == .active, library.map({ $0.owner == session.owner }) ?? true, let changeSource else { return }
        sourceChanging = true
        let value = snapshot(exiting: true)
        state.controller?.set("pause", "yes")
        Task {
            // Save locally before dismissal. The existing disappearance
            // checkpoint synchronizes cloud progress without delaying the picker.
            if let value { await persist(value, syncCloud: false) }
            guard active, scenePhase == .active, library.map({ $0.owner == session.owner }) ?? true else { sourceChanging = false; return }
            changeSource(value)
        }
    }
    private func requestRetry() {
        guard active, !retrying, !state.restarting, !sourceChanging, !episodeChanging, scenePhase == .active, library.map({ $0.owner == session.owner }) ?? true else { return }
        guard let controller = state.controller, controller.canRestartPlayback else { return }
        let value = snapshot(exiting: true)
        let position = value?.positionMs ?? session.startMs
        guard position.isFinite, position >= 0 else { return }
        retrying = true
        Task {
            defer { retrying = false }
            if let value { await persist(value, syncCloud: false) }
            guard active, scenePhase == .active, library.map({ $0.owner == session.owner }) ?? true else { return }
            controller.retry(positionMs: position)
            controlsVisible = true; restartHideTimer()
        }
    }
    private func restartHideTimer() { hideRevision += 1 }
    private func updateIdleTimer() {
        guard active else { return }
        UIApplication.shared.isIdleTimerDisabled = previousIdleTimer || (preferences.options.keepScreenAwake && state.loaded && !state.paused && !state.ended && scenePhase == .active)
    }

    private var controls: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Button { dismiss() } label: { PlayerGlyph(name: "back").frame(width: 44, height: 44) }
                    .accessibilityLabel("Cerrar reproductor").accessibilityIdentifier("player-close")
                Text(title).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                if canChangeEpisode {
                    Button { showEpisodes = true; restartHideTimer() } label: { Image("nav-shows").resizable().scaledToFit().frame(width: 24, height: 24).frame(width: 44, height: 44) }
                        .accessibilityLabel("Temporadas y episodios").accessibilityIdentifier("player-episodes")
                }
                Button { settingsPage = .options } label: { Image("nav-settings").frame(width: 44, height: 44) }
                    .accessibilityLabel("Opciones del reproductor").accessibilityIdentifier("player-options")
            }.padding(.horizontal, 8).padding(.vertical, 4).background(.black.opacity(0.7))
            Spacer()
            VStack(spacing: 4) {
                if canChangeEpisode {
                    HStack {
                        Button { if let previous = adjacent.previous { requestEpisode(previous) } } label: {
                            HStack(spacing: 6) { PlayerGlyph(name: "prev-episode", size: 17); Text("Anterior") }
                        }.frame(minHeight: 44).disabled(adjacent.previous == nil || episodeChanging).accessibilityIdentifier("player-previous-episode")
                        Spacer()
                        Text("T\(session.target.season ?? 0) · E\(session.target.episode ?? 0)").foregroundStyle(.secondary)
                        Spacer()
                        Button { if let next = adjacent.next { requestEpisode(next) } } label: {
                            HStack(spacing: 6) { Text("Siguiente"); PlayerGlyph(name: "next-episode", size: 17) }
                        }.frame(minHeight: 44).disabled(adjacent.next == nil || episodeChanging).accessibilityIdentifier("player-next-episode")
                    }.font(.caption)
                }
                HStack(spacing: 10) {
                    Text(time(state.position)).monospacedDigit().accessibilityLabel("Tiempo reproducido").accessibilityIdentifier("player-position")
                    HarborSeekBar(position: state.position, duration: state.duration,
                        enabled: state.loaded && !retrying && !state.restarting && !sourceChanging && !episodeChanging,
                        editing: { editingSeek = $0; restartHideTimer() },
                        seek: { state.controller?.run(["seek", String($0), "absolute+exact"]); restartHideTimer() })
                    Text(time(state.duration)).monospacedDigit()
                }.font(HarborTheme.font(12, weight: .medium))
                HStack(spacing: 8) {
                    Button { state.controller?.set("mute", state.muted ? "no" : "yes") } label: { PlayerGlyph(name: state.muted ? "volume--mute" : "volume").frame(width: 44, height: 44) }.accessibilityLabel(state.muted ? "Activar sonido" : "Silenciar")
                    Spacer(minLength: 0)
                    Button { jump(-preferences.options.seekBackSeconds) } label: { PlayerSeekGlyph(direction: "back", seconds: preferences.options.seekBackSeconds) }.frame(width: 44, height: 44).accessibilityLabel("Retroceder \(Int(preferences.options.seekBackSeconds)) segundos")
                    Button {
                        if state.ended { state.controller?.replay() }
                        else { state.controller?.togglePause() }
                        restartHideTimer()
                    } label: { PlayerGlyph(name: state.ended ? "seek-back-custom" : state.paused ? "play-pause--paused" : "play-pause--playing", size: 28) }
                        .disabled(retrying || state.restarting || sourceChanging || episodeChanging)
                        .frame(width: 44, height: 44).accessibilityLabel(state.ended ? "Repetir" : state.paused ? "Reproducir" : "Pausar").accessibilityIdentifier("player-pause")
                    Button { jump(preferences.options.seekForwardSeconds) } label: { PlayerSeekGlyph(direction: "forward", seconds: preferences.options.seekForwardSeconds) }.frame(width: 44, height: 44).accessibilityLabel("Avanzar \(Int(preferences.options.seekForwardSeconds)) segundos")
                    Spacer(minLength: 0)
                    if verticalSizeClass == .compact { trackControls }
                }.font(.caption)
                if verticalSizeClass != .compact { HStack { Spacer(); trackControls; Spacer() } }
            }.padding(.horizontal).padding(.bottom, 8).background(.black.opacity(0.7))
        }
    }
    private var trackControls: some View {
        HStack(spacing: 10) {
            Button { settingsPage = .audio } label: { PlayerGlyph(name: "audio").frame(width: 44, height: 44) }.accessibilityLabel("Audio").accessibilityIdentifier("player-audio")
            Button { settingsPage = .subtitles } label: { PlayerGlyph(name: "subtitle").frame(width: 44, height: 44) }.accessibilityLabel("Subtítulos").accessibilityIdentifier("player-subtitles")
            Button { settingsPage = .video } label: { PlayerGlyph(name: "aspect").frame(width: 44, height: 44) }.accessibilityLabel("Imagen y formato").accessibilityIdentifier("player-picture")
            Button { settingsPage = .playback } label: { VStack(spacing: 1) { PlayerGlyph(name: "speed", size: 19); Text("\(state.speed.formatted())×").font(.system(size: 9)) } }.accessibilityLabel("Velocidad").accessibilityValue("\(state.speed.formatted())×").frame(minWidth: 44, minHeight: 44)
            AudioRoutePicker(state: state)
            if state.pictureInPictureSupported {
                Button { state.controller?.togglePictureInPicture(); restartHideTimer() } label: {
                    PlayerGlyph(name: "pip", size: 22).frame(width: 44, height: 44)
                }
                .disabled(state.pictureInPictureChanging || state.subtitleChanging || retrying || state.restarting || sourceChanging || episodeChanging || !state.loaded || state.ended || !state.tracks.contains(where: { $0.type == "video" && $0.selected }))
                .accessibilityLabel(DesktopInterfaceText.text(state.pictureInPictureActive ? "Exit Picture in Picture" : "Picture in Picture"))
                .accessibilityIdentifier("player-pip")
            }
        }
    }
    private func jump(_ seconds: Double) {
        guard !retrying, !state.restarting, !sourceChanging, !episodeChanging, state.loaded else { return }
        state.controller?.run(["seek", String(seconds), "relative"]); restartHideTimer()
    }

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

    @MainActor private func persist(_ value: ResumeSnapshot, syncCloud: Bool = true) async {
        do {
            if try await resume.save(session.target, snapshot: value) {
                lastSavedMs = value.positionMs
                progressError = nil
                Diagnostics.shared.record(.progressSaved)
                library?.noteLocalProgress(session.target, snapshot: value, owner: session.owner)
            }
        } catch {
            progressError = safeMessage(error)
            Diagnostics.shared.recordFailure(error)
        }
        if syncCloud, let media, let library { await library.saveProgress(media, target: session.target, snapshot: value, owner: session.owner) }
    }
    private func time(_ value: Double) -> String { HarborSeekBar.time(value) }
}

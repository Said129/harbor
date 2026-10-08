import AVFoundation
import AVKit
import CoreVideo
import Darwin
import GLKit
import Libmpv

/// Render/event access is serialized on the main actor. Playback commands and
/// properties use mpv's asynchronous API: the render thread must not wait for
/// the mpv core. No escaping C callbacks reference UIKit objects.
@MainActor
final class MPVController: GLKViewController {
    let state: PlayerState
    private let source: PlaybackSource
    private let startMs: Double
    private var handle: OpaquePointer?
    private var renderer: OpaquePointer?
    private var context: EAGLContext?
    private var didClose = false
    private var checkedResumeDuration = false
    private struct PendingOperation {
        let continuation: CheckedContinuation<Void, Error>
        let timeout: Task<Void, Never>
    }
    private var pendingOperations: [UInt64: PendingOperation] = [:]
    private var nextOperation: UInt64 = 1
    private var subtitleTail: Task<Void, Never>?
    private var subtitleOperations = 0
    private var mediaRevision = 0
    private var acknowledgedSubtitleFPS = 0.0
    private var preferredSecondaryHandled = false
    private let subtitleSession = UUID()
    private var lifecycleTokens: [NSObjectProtocol] = []
    private var deferredCloseToken: NSObjectProtocol?
    private var suspendedEvents: Task<Void, Never>?
    private var renderSuspended = false
    private var interrupted = false
    private var interruptionResumeWanted = false
    private var interruptionResumeAllowed = false
    private var foregroundResumeWanted = false
    private var sampleOutput: MPVSampleBufferRenderer?
    private var sampleEvents: Task<Void, Never>?
    private var pictureInPicture: MPVPictureInPicture?
    private var pictureInPictureTask: Task<Void, Never>?
    private var inlineRestoreTask: Task<Void, Never>?
    private var renderSwitching = false
    private var inlineRestorePending = false
    private var videoOutputName = ""
    var sampleFrame: CVPixelBuffer? { pictureInPicture?.lastFrame }
    var sampleRenderCalls: Int { pictureInPicture?.renderedFrames ?? 0 }

    init(source: PlaybackSource, state: PlayerState, startMs: Double = 0, preservePosition: Bool = false) {
        self.source = source; self.state = state
        self.startMs = startMs
        checkedResumeDuration = preservePosition
        super.init(nibName: nil, bundle: nil)
        state.controller = self
    }
    required init?(coder: NSCoder) { return nil }

    override func loadView() {
#if targetEnvironment(simulator)
        // Use MPVKit's GLES2 demo path on the Intel software renderer. Its
        // GLES3 path intermittently produces grid-shaped missing pixels.
        let candidate = EAGLContext(api: .openGLES2)
#else
        let candidate = EAGLContext(api: .openGLES3) ?? EAGLContext(api: .openGLES2)
#endif
        guard let context = candidate else {
            view = UIView(); state.error = "No se pudo iniciar el render de vídeo."; return
        }
        self.context = context
        let surface = GLKView(frame: .zero, context: context)
        surface.delegate = self
        surface.drawableColorFormat = .RGBA8888
        surface.drawableDepthFormat = .formatNone
        surface.backgroundColor = .black
        view = surface
        preferredFramesPerSecond = 60
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        do { try initialize() } catch { state.error = safeMessage(error); close() }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        pictureInPicture?.layout(view.bounds)
    }

    private func check(_ code: Int32) throws {
        guard code >= 0 else {
            Diagnostics.shared.record(.playerFailed, count: Int(code))
            throw HarborError(code: "mpv-\(code)")
        }
    }

    private func initialize() throws {
        guard let context, EAGLContext.setCurrent(context) else { throw HarborError(code: "player-init") }
        MusicPlayback.shared.pauseForVideo()
        try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try AVAudioSession.sharedInstance().setActive(true)
        updateAudioRoute()
        let mpv = try MPVConfiguration.createHandle(startMs: startMs)
        handle = mpv
        try check(mpv_request_log_messages(mpv, "no"))
#if targetEnvironment(simulator)
        if source.via == "test-fixture" {
            for name in ["video-dec-params", "video-out-params", "vf"] { try check(mpv_observe_property(mpv, 0, name, MPV_FORMAT_NODE)) }
        }
#endif
        try createGLRenderer(mpv)
        state.pictureInPictureSupported = AVPictureInPictureController.isPictureInPictureSupported()
        for name in ["dwidth", "dheight"] { _ = mpv_observe_property(mpv, 0, name, MPV_FORMAT_INT64) }
        _ = mpv_observe_property(mpv, 0, "current-vo", MPV_FORMAT_STRING)
        for name in ["time-pos", "duration", "speed", "volume", "audio-delay", "sub-delay"] { try check(mpv_observe_property(mpv, 0, name, MPV_FORMAT_DOUBLE)) }
        for name in ["pause", "paused-for-cache", "mute"] { try check(mpv_observe_property(mpv, 0, name, MPV_FORMAT_FLAG)) }
        try check(mpv_observe_property(mpv, 0, "track-list", MPV_FORMAT_NODE))
        try check(mpv_observe_property(mpv, 0, "chapter-list", MPV_FORMAT_NODE))
        // Optional timing properties must not prevent ordinary playback on an
        // older runtime. Availability comes from their actual property events.
        for name in ["sub-fps", "estimated-vf-fps", "container-fps"] { _ = mpv_observe_property(mpv, 0, name, MPV_FORMAT_DOUBLE) }
        for name in ["sub-text", "secondary-sub-text"] { _ = mpv_observe_property(mpv, 0, name, MPV_FORMAT_STRING) }
        if let headers = source.headers {
            // mpv string-list escapes commas by doubling; reject CR/LF in Rust.
            let value = headers.sorted(by: { $0.key < $1.key }).map { "\($0.key): \($0.value)".replacingOccurrences(of: ",", with: ",,") }.joined(separator: ",")
            try check(mpv_set_property_string(mpv, "http-header-fields", value))
        }
        try command(["loadfile", source.url, "replace"])
        state.renderReady = true
        observePlaybackLifecycle()
        Diagnostics.shared.record(.playerStarted)
    }

    private func createGLRenderer(_ mpv: OpaquePointer) throws {
        guard UIApplication.shared.applicationState != .background, let context, EAGLContext.setCurrent(context), renderer == nil, sampleOutput == nil else { throw HarborError(code: "player-init") }
        var initialization = mpv_opengl_init_params(get_proc_address: { _, name in
            // Resolve this context's GLES entry points, as the pinned MPVKit
            // demo does. A process-wide lookup can find another GL backend.
            guard let name, let bundle = CFBundleGetBundleWithIdentifier("com.apple.opengles" as CFString) else { return nil }
            return CFBundleGetFunctionPointerForName(bundle, String(cString: name) as CFString)
        }, get_proc_address_ctx: nil)
        let status = "opengl".withCString { api in
            withUnsafeMutablePointer(to: &initialization) { initialization in
                var parameters = [
                    mpv_render_param(type: MPV_RENDER_PARAM_API_TYPE, data: UnsafeMutableRawPointer(mutating: api)),
                    mpv_render_param(type: MPV_RENDER_PARAM_OPENGL_INIT_PARAMS, data: initialization),
                    mpv_render_param(type: MPV_RENDER_PARAM_INVALID, data: nil)
                ]
                return mpv_render_context_create(&renderer, mpv, &parameters)
            }
        }
        try check(status)
    }

    func command(_ values: [String]) throws {
        guard let handle else { throw HarborError(code: "player-not-ready") }
        let allocations = values.map { strdup($0) }
        defer { for allocation in allocations { free(allocation) } }
        guard allocations.allSatisfy({ $0 != nil }) else { throw HarborError(code: "player-allocation") }
        var pointers: [UnsafePointer<CChar>?] = allocations.map { $0.map { UnsafePointer<CChar>($0) } } + [nil]
        try check(mpv_command_async(handle, 0, &pointers))
    }

    func set(_ name: String, _ value: String) {
        if name == "sid" || name == "secondary-sid" { selectSubtitle(value, secondary: name == "secondary-sid"); return }
        guard let handle else { return }
        do {
            let result = value.withCString { pointer in
                var string: UnsafePointer<CChar>? = pointer
                return withUnsafeMutablePointer(to: &string) { mpv_set_property_async(handle, 0, name, MPV_FORMAT_STRING, $0) }
            }
            try check(result)
        } catch { state.error = safeMessage(error) }
    }
    func run(_ values: [String]) {
        do { try command(values) } catch { state.error = safeMessage(error) }
    }
    func replay() {
        restartPlayback(positionMs: nil, autoplay: nil)
    }
    var canRestartPlayback: Bool { !didClose && !renderSwitching && handle != nil && (renderer != nil || sampleOutput != nil) }
    func retry(positionMs: Double, autoplay: Bool = true) {
        guard positionMs.isFinite, positionMs >= 0 else { return }
        restartPlayback(positionMs: positionMs, autoplay: autoplay)
    }
    private func restartPlayback(positionMs: Double?, autoplay: Bool?) {
        guard canRestartPlayback, !state.restarting else { return }
        guard activateAudio() else { return }
        interruptionResumeWanted = false; interruptionResumeAllowed = false; foregroundResumeWanted = false
        state.error = nil
        state.ended = false; state.endedNaturally = false; state.buffering = true
        checkedResumeDuration = true
        enqueueSubtitleOperation(playbackRestart: true) { controller in
            try await controller.resetSubtitleFPS()
            try await controller.setChecked("start", positionMs.map { String($0 / 1_000) } ?? "none")
            if let autoplay { try await controller.setChecked("pause", autoplay ? "no" : "yes") }
            try await controller.commandChecked(["loadfile", controller.source.url, "replace"], startsMedia: true)
        }
    }

    func togglePause() {
        interruptionResumeWanted = false; interruptionResumeAllowed = false; foregroundResumeWanted = false
        if state.paused {
            guard activateAudio() else { return }
        }
        run(["cycle", "pause"])
    }

    private func activateAudio() -> Bool {
        guard !didClose, UIApplication.shared.applicationState == .active || pictureInPicture?.active == true else { return false }
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
            try AVAudioSession.sharedInstance().setActive(true)
            updateAudioRoute()
            interrupted = false
            state.playbackIssue = nil
            return true
        } catch { state.playbackIssue = "No se pudo recuperar la salida de audio. Puedes volver a pulsar Reproducir."; return false }
    }

    func togglePictureInPicture() {
        if pictureInPicture?.active == true { pictureInPicture?.stop(); return }
        guard state.pictureInPictureSupported, state.loaded, !state.ended, !state.pictureInPictureChanging, !state.subtitleChanging,
              state.tracks.contains(where: { $0.type == "video" && $0.selected }), UIApplication.shared.applicationState == .active else { return }
        state.pictureInPictureChanging = true; state.playbackIssue = nil
        pictureInPictureTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.state.pictureInPictureChanging = false; self.pictureInPictureTask = nil }
            do {
                try await self.prepareSampleRendering()
                guard let picture = self.pictureInPicture else { throw HarborError(code: "pip-unavailable") }
                try await picture.start()
            } catch {
                guard !self.didClose else { return }
                self.pictureInPicture?.stop()
                if !(error is CancellationError) { self.state.playbackIssue = safeMessage(error) }
                self.restoreAfterPictureInPicture()
            }
        }
    }

    /// A renderer transition never reloads the source or creates another core.
    /// Use mpv's null output while replacing its single render context so a
    /// video-only file also retains a selected video track and its timeline.
    func prepareSampleRendering() async throws {
        guard !didClose, !renderSwitching, sampleOutput == nil, let handle, renderer != nil,
              state.loaded, !state.ended, !state.subtitleChanging, UIApplication.shared.applicationState == .active,
              state.tracks.contains(where: { $0.type == "video" && $0.selected }) else { throw HarborError(code: "player-not-ready") }
        renderSwitching = true
        defer { renderSwitching = false }
        do {
            try await setChecked("vo", "null")
            try await waitForVideoOutput("null")
            try Task.checkCancellation()
            guard !didClose, UIApplication.shared.applicationState == .active, let context, EAGLContext.setCurrent(context) else { throw HarborError(code: "player-not-ready") }
            renderSuspended = true; isPaused = true
            suspendedEvents?.cancel(); suspendedEvents = nil
            startSampleEvents()
            if let renderer { mpv_render_context_free(renderer); self.renderer = nil }
            sampleOutput = try MPVSampleBufferRenderer(handle: handle)
            pictureInPicture = try MPVPictureInPicture(owner: self, view: view)
            try await setChecked("vo", "libmpv")
            try await waitForVideoOutput("libmpv")
            try Task.checkCancellation()
        } catch {
            if !didClose, UIApplication.shared.applicationState == .active {
                do {
                    try await setChecked("vo", "null")
                    try await waitForVideoOutput("null")
                    sampleOutput?.close(); sampleOutput = nil
                    pictureInPicture?.close(); pictureInPicture = nil
                    if renderer == nil { try createGLRenderer(handle) }
                    try await setChecked("vo", "libmpv")
                    try await waitForVideoOutput("libmpv")
                    sampleEvents?.cancel(); sampleEvents = nil
                    renderSuspended = false; isPaused = false
                } catch { state.error = safeMessage(error) }
            } else if !didClose { inlineRestorePending = true; set("pause", "yes") }
            throw error
        }
    }

    private func startSampleEvents() {
        sampleEvents?.cancel()
        sampleEvents = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self, !self.didClose, let handle = self.handle else { return }
                self.drainEvents(handle)
                self.pictureInPicture?.synchronizeClock()
                let canDraw = UIApplication.shared.applicationState != .background || self.pictureInPicture?.active == true
                if !self.renderSwitching, canDraw, let output = self.sampleOutput {
                    let width = self.state.videoWidth, height = self.state.videoHeight
                    let ratio = width > 0 && height > 0 ? Double(width) / Double(height) : 16.0 / 9.0
                    let boundedRatio = min(20, max(0.05, ratio))
                    let targetWidth = boundedRatio >= 1 ? 640 : max(32, Int(640 * boundedRatio))
                    let targetHeight = boundedRatio >= 1 ? max(32, Int(640 / boundedRatio)) : 640
                    do {
                        if let frame = try output.draw(width: targetWidth, height: targetHeight) { try self.pictureInPicture?.enqueue(frame) }
                    } catch {
                        self.state.playbackIssue = safeMessage(error)
                        self.pictureInPicture?.stop()
                        self.restoreAfterPictureInPicture()
                    }
                }
                do { try await Task.sleep(for: .milliseconds(33)) } catch { return }
            }
        }
    }

    func restoreAfterPictureInPicture() {
        guard !didClose, sampleOutput != nil || renderer == nil else { return }
        if UIApplication.shared.applicationState != .active {
            inlineRestorePending = true
            foregroundResumeWanted = foregroundResumeWanted || (!interrupted && state.loaded && !state.paused && !state.ended)
            set("pause", "yes")
            return
        }
        guard !renderSwitching else { inlineRestorePending = true; return }
        guard inlineRestoreTask == nil else { return }
        inlineRestoreTask = Task { @MainActor [weak self] in
            guard let self, !self.didClose else { return }
            defer { self.inlineRestoreTask = nil }
            do { try await self.restoreInlineRendering() }
            catch { if !self.didClose { self.state.error = safeMessage(error) } }
        }
    }

    func restoreInlineRendering() async throws {
        guard !didClose, !renderSwitching, sampleOutput != nil || renderer == nil, let handle,
              UIApplication.shared.applicationState == .active else { throw HarborError(code: "player-not-ready") }
        renderSwitching = true; inlineRestorePending = false
        defer { renderSwitching = false }
        try await setChecked("vo", "null")
        try await waitForVideoOutput("null")
        try Task.checkCancellation()
        guard !didClose, UIApplication.shared.applicationState == .active else { inlineRestorePending = true; throw HarborError(code: "player-not-ready") }
        pictureInPicture?.close(); pictureInPicture = nil
        sampleOutput?.close(); sampleOutput = nil
        try createGLRenderer(handle)
        try await setChecked("vo", "libmpv")
        try await waitForVideoOutput("libmpv")
        sampleEvents?.cancel(); sampleEvents = nil
        if UIApplication.shared.applicationState == .active {
            renderSuspended = false; isPaused = false
            resumeConfiguredForegroundPlayback()
        }
        else { set("pause", "yes") }
    }

    func seekForPictureInPicture(_ seconds: Double) async throws {
        guard seconds.isFinite, !didClose, sampleOutput != nil, !renderSwitching, state.loaded, !state.ended, state.duration.isFinite, state.duration > 0 else { throw HarborError(code: "player-not-ready") }
        try await commandChecked(["seek", String(seconds), "relative+exact"])
    }

    private func waitForVideoOutput(_ name: String) async throws {
        let deadline = Date().addingTimeInterval(5)
        while videoOutputName != name && Date() < deadline {
            try Task.checkCancellation()
            guard !didClose, !state.ended, let handle else { throw HarborError(code: "player-not-ready") }
            drainEvents(handle)
            try await Task.sleep(for: .milliseconds(20))
        }
        guard !didClose, videoOutputName == name else { throw HarborError(code: "player-output-timeout") }
    }

    private func observePlaybackLifecycle() {
        let center = NotificationCenter.default
        lifecycleTokens.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: nil) { [weak self] notification in
            let type = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            let options = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            Task { @MainActor [weak self] in self?.audioInterruption(type: type, options: options) }
        })
        lifecycleTokens.append(center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: nil) { [weak self] notification in
            let reason = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            Task { @MainActor [weak self] in
                guard let self, !self.didClose else { return }
                self.updateAudioRoute()
                if reason == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue {
                    self.interruptionResumeWanted = false; self.interruptionResumeAllowed = false; self.foregroundResumeWanted = false
                    self.set("pause", "yes")
                }
            }
        })
        lifecycleTokens.append(center.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.suspendForApp() }
        })
        lifecycleTokens.append(center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.restoreForApp() }
        })
    }

    private func updateAudioRoute() {
        let outputs = AVAudioSession.sharedInstance().currentRoute.outputs
        state.audioOutput = outputs.map(\.portName).joined(separator: ", ")
        state.wirelessAudio = outputs.contains { $0.portType == .airPlay }
    }

    private func audioInterruption(type: UInt?, options: UInt) {
        guard !didClose, let type else { return }
        if type == AVAudioSession.InterruptionType.began.rawValue {
            if !interrupted { interruptionResumeWanted = state.loaded && !state.ended && (!state.paused || foregroundResumeWanted) }
            interruptionResumeAllowed = false
            interrupted = true
            set("pause", "yes")
        } else if type == AVAudioSession.InterruptionType.ended.rawValue {
            interrupted = false
            interruptionResumeAllowed = interruptionResumeWanted && AVAudioSession.InterruptionOptions(rawValue: options).contains(.shouldResume) && PlaybackPreferences.shared.options.resumeAfterInterruption
            interruptionResumeWanted = false
            if interruptionResumeAllowed && ((!renderSuspended && UIApplication.shared.applicationState == .active) || pictureInPicture?.active == true) {
                interruptionResumeAllowed = false
                if activateAudio() { set("pause", "no") }
            }
        }
    }

    private func suspendForApp() {
        if !didClose, sampleOutput != nil {
            if pictureInPicture?.active != true {
                foregroundResumeWanted = !interrupted && state.loaded && !state.paused && !state.ended
                set("pause", "yes")
            }
            return
        }
        guard !didClose, !renderSuspended else { return }
        foregroundResumeWanted = !interrupted && state.loaded && !state.paused && !state.ended
        set("pause", "yes")
        renderSuspended = true
        isPaused = true
        if UIApplication.shared.applicationState != .background, let context, EAGLContext.setCurrent(context) { glFinish() }
        // Property/command acknowledgements remain available while the
        // drawable is suspended. This loop never touches OpenGL.
        suspendedEvents = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self, !self.didClose, self.renderSuspended else { return }
                if let handle = self.handle { self.drainEvents(handle) }
                do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
            }
        }
    }

    private func restoreForApp() {
        guard !didClose else { return }
        if sampleOutput != nil || inlineRestorePending || renderer == nil {
            if let handle { drainEvents(handle) }
            if inlineRestorePending || pictureInPicture?.active != true { restoreAfterPictureInPicture() }
            return
        }
        suspendedEvents?.cancel(); suspendedEvents = nil
        renderSuspended = false; isPaused = false
        if let handle { drainEvents(handle) }
        resumeConfiguredForegroundPlayback()
    }

    private func resumeConfiguredForegroundPlayback() {
        let resume = !interrupted && (interruptionResumeAllowed || (foregroundResumeWanted && PlaybackPreferences.shared.options.resumeOnForeground))
        interruptionResumeAllowed = false; foregroundResumeWanted = false
        if resume && !state.ended && activateAudio() { set("pause", "no") }
    }

    func applySubtitleFPS(_ value: Double) {
        guard value == 0 || SubtitleTiming.valid(value) else { state.subtitleIssue = "Introduce unos FPS entre 1 y 240."; return }
        let trackID = state.primarySubtitle?.id
        enqueueSubtitleOperation { controller in
            guard SubtitleTiming.unavailable(controller.state) == nil,
                  controller.state.primarySubtitle?.id == trackID else { throw HarborError(code: "subtitle-context") }
            try await controller.setChecked("sub-fps", String(value))
            controller.acknowledgedSubtitleFPS = value
            guard controller.state.primarySubtitle?.id == trackID else {
                try await controller.resetSubtitleFPS()
                throw HarborError(code: "subtitle-context")
            }
        }
    }

    func selectSubtitle(_ value: String, secondary: Bool = false) {
        guard value == "no" || value == "auto" || Int(value).map({ $0 > 0 }) == true else { return }
        if secondary { preferredSecondaryHandled = true }
        enqueueSubtitleOperation { controller in
            if let id = Int(value) {
                guard let track = controller.state.tracks.first(where: { $0.type == "sub" && $0.id == id }) else { throw HarborError(code: "subtitle-context") }
                if secondary && (track.isImageSubtitle || controller.state.primarySubtitle?.id == id) { throw HarborError(code: "subtitle-secondary") }
            }
            // Desktop aborts a track transition if the source-FPS reset fails.
            // Wait for the real mpv reply instead of announcing an optimistic
            // selection or racing a pending timing write.
            try await controller.resetSubtitleFPS()
            if !secondary, let id = Int(value), id == controller.state.secondarySubtitle?.id {
                try await controller.setChecked("secondary-sid", "no")
            }
            try await controller.setChecked(secondary ? "secondary-sid" : "sid", value)
        }
    }

    func applyPreferredSecondary(reset: Bool = false) {
        if reset { preferredSecondaryHandled = false }
        guard !preferredSecondaryHandled, state.loaded else { return }
        let languages = PlaybackPreferences.shared.options.secondarySubtitleLanguage
        guard !SubtitleLanguages.preferredCodes(languages).isEmpty else {
            if reset { selectSubtitle("no", secondary: true) }
            return
        }
        guard let main = state.primarySubtitle else { return }
        if let track = SubtitleLanguages.preferredSecondary(in: state.tracks, excluding: main.id, languages: languages) {
            selectSubtitle(String(track.id), secondary: true)
        }
    }

    func importLocalSubtitle(_ input: URL) {
        let revision = mediaRevision
        enqueueSubtitleOperation { controller in
            guard controller.state.loaded else { throw HarborError(code: "subtitle-context") }
            controller.state.subtitleImportMessage = nil
            let subtitle = try await SubtitleFileService.shared.copy(input, session: controller.subtitleSession)
            do {
                guard !controller.didClose, controller.mediaRevision == revision else { throw HarborError(code: "subtitle-context") }
                try await controller.resetSubtitleFPS()
                try await controller.commandChecked(["sub-add", subtitle.url.absoluteString, "select", subtitle.title])
                let deadline = Date().addingTimeInterval(7)
                var importedTrack: Int?
                while Date() < deadline {
                    try Task.checkCancellation()
                    guard !controller.didClose, controller.mediaRevision == revision else { throw HarborError(code: "subtitle-context") }
                    if let track = controller.state.tracks.first(where: { track in track.type == "sub" && (track.externalFilename == subtitle.url.path || track.externalFilename == subtitle.url.absoluteString) }),
                       controller.state.primarySubtitle?.id == track.id { importedTrack = track.id; break }
                    try await Task.sleep(for: .milliseconds(50))
                }
                guard let importedTrack else { throw HarborError(code: "subtitle-file") }
                controller.state.importedSubtitleIDs.insert(importedTrack)
                controller.state.subtitleImportMessage = "Importado: " + subtitle.title
            } catch {
                if !controller.didClose, controller.mediaRevision == revision,
                   let track = controller.state.tracks.first(where: { $0.type == "sub" && ($0.externalFilename == subtitle.url.path || $0.externalFilename == subtitle.url.absoluteString) }) {
                    try? await controller.commandChecked(["sub-remove", String(track.id)])
                }
                await SubtitleFileService.shared.discard(subtitle, session: controller.subtitleSession)
                throw error
            }
        }
    }

    private func enqueueSubtitleOperation(playbackRestart: Bool = false, _ operation: @escaping @MainActor (MPVController) async throws -> Void) {
        guard !didClose, handle != nil else { return }
        let previous = subtitleTail
        let revision = mediaRevision
        subtitleOperations += 1
        state.subtitleChanging = true
        if playbackRestart { state.restarting = true }
        state.subtitleIssue = nil
        subtitleTail = Task { @MainActor [weak self] in
            await previous?.value
            guard let self else { return }
            defer {
                subtitleOperations -= 1; state.subtitleChanging = subtitleOperations > 0
                if playbackRestart { state.restarting = false }
            }
            guard !Task.isCancelled, !didClose, revision == mediaRevision else { return }
            state.subtitleIssue = nil
            do { try await operation(self) }
            catch {
                if !didClose, revision == mediaRevision {
                    if playbackRestart {
                        state.error = "No se pudo volver a abrir la fuente. Prueba con otro enlace."
                        state.buffering = false
                        Diagnostics.shared.recordFailure(error)
                    }
                    // An optional subtitle operation must not stop the film.
                    else if let failure = error as? HarborError, ["subtitle-file", "subtitle-capacity"].contains(failure.code) { state.subtitleIssue = safeMessage(error) }
                    else { state.subtitleIssue = "No se pudo aplicar el cambio de subtítulos. La reproducción continúa; vuelve a intentarlo." }
                }
            }
        }
    }

    private func resetSubtitleFPS() async throws {
        guard acknowledgedSubtitleFPS != 0 || (state.subtitleFPS ?? 0) != 0 else { return }
        try await setChecked("sub-fps", "0")
        acknowledgedSubtitleFPS = 0
    }

    private func setChecked(_ name: String, _ value: String) async throws {
        try await performChecked(timeoutCode: name == "vo" ? "player-output-timeout" : "subtitle-timeout") { handle, identifier in
            value.withCString { pointer in
                var string: UnsafePointer<CChar>? = pointer
                return withUnsafeMutablePointer(to: &string) { mpv_set_property_async(handle, identifier, name, MPV_FORMAT_STRING, $0) }
            }
        }
    }

    private func commandChecked(_ values: [String], startsMedia: Bool = false) async throws {
        let allocations = values.map { strdup($0) }
        defer { for allocation in allocations { free(allocation) } }
        guard allocations.allSatisfy({ $0 != nil }) else { throw HarborError(code: "player-allocation") }
        var pointers: [UnsafePointer<CChar>?] = allocations.map { $0.map { UnsafePointer<CChar>($0) } } + [nil]
        try await performChecked(startsMedia: startsMedia) { handle, identifier in mpv_command_async(handle, identifier, &pointers) }
    }

    private func performChecked(startsMedia: Bool = false, timeoutCode: String = "subtitle-timeout", _ send: (OpaquePointer, UInt64) -> Int32) async throws {
        guard let handle, !didClose else { throw HarborError(code: "player-not-ready") }
        let identifier = nextOperation
        let revision = mediaRevision
        nextOperation &+= 1
        if nextOperation == 0 { nextOperation = 1 }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let result = send(handle, identifier)
            guard result >= 0 else { continuation.resume(throwing: HarborError(code: "mpv-\(result)")); return }
            let timeout = Task { @MainActor [weak self] in
                do { try await Task.sleep(for: .seconds(5)) } catch { return }
                self?.finishOperation(identifier, error: HarborError(code: timeoutCode))
            }
            pendingOperations[identifier] = PendingOperation(continuation: continuation, timeout: timeout)
        }
        // A successful loadfile acknowledgement may follow START_FILE. Other
        // operations still belong to the exact media revision they changed.
        guard !didClose, startsMedia || revision == mediaRevision else { throw HarborError(code: "subtitle-context") }
    }

    private func finishOperation(_ identifier: UInt64, error: Error? = nil) {
        guard let operation = pendingOperations.removeValue(forKey: identifier) else { return }
        operation.timeout.cancel()
        if let error { operation.continuation.resume(throwing: error) }
        else { operation.continuation.resume() }
    }

    @available(iOS, deprecated: 12.0)
    override func glkView(_ surface: GLKView, drawIn rect: CGRect) {
        guard !didClose, !renderSuspended, UIApplication.shared.applicationState != .background else { return }
        guard let context, EAGLContext.setCurrent(context), surface.drawableWidth > 0, surface.drawableHeight > 0 else { return }
        // libmpv requires default GL state on entry and does not restore the
        // viewport/scissor rectangle. GLKView also draws during snapshots and
        // layout changes; start every frame with the full incoming drawable.
        glViewport(0, 0, GLsizei(surface.drawableWidth), GLsizei(surface.drawableHeight))
        glDisable(GLenum(GL_SCISSOR_TEST))
        glDisable(GLenum(GL_BLEND))
        glDisable(GLenum(GL_DEPTH_TEST))
        glDisable(GLenum(GL_STENCIL_TEST))
        glDisable(GLenum(GL_CULL_FACE))
        glDisable(GLenum(GL_SAMPLE_ALPHA_TO_COVERAGE))
        glDisable(GLenum(GL_SAMPLE_COVERAGE))
        if context.api == .openGLES3 { glDisable(GLenum(GL_RASTERIZER_DISCARD)) }
        glColorMask(GLboolean(GL_TRUE), GLboolean(GL_TRUE), GLboolean(GL_TRUE), GLboolean(GL_TRUE))
        glClearColor(0, 0, 0, 1)
        glClear(GLbitfield(GL_COLOR_BUFFER_BIT))
        guard let renderer, let handle else { return }
        state.renderCalls += 1
        drainEvents(handle)
        var framebuffer: GLint = 0
        var renderbuffer: GLint = 0
        glGetIntegerv(GLenum(GL_FRAMEBUFFER_BINDING), &framebuffer)
        glGetIntegerv(GLenum(GL_RENDERBUFFER_BINDING), &renderbuffer)
        // GLKView's drawable is explicitly RGBA8888. Do not leave mpv to infer
        // the color format through the simulator's software GL driver.
        var fbo = mpv_opengl_fbo(fbo: framebuffer, w: Int32(surface.drawableWidth), h: Int32(surface.drawableHeight), internal_format: Int32(GL_RGBA8))
        var flip: Int32 = 1
        withUnsafeMutablePointer(to: &fbo) { fbo in
            withUnsafeMutablePointer(to: &flip) { flip in
                var parameters = [mpv_render_param(type: MPV_RENDER_PARAM_OPENGL_FBO, data: fbo), mpv_render_param(type: MPV_RENDER_PARAM_FLIP_Y, data: flip), mpv_render_param(type: MPV_RENDER_PARAM_INVALID, data: nil)]
                let result = mpv_render_context_render(renderer, &parameters)
                if result < 0 {
                    if state.error == nil { Diagnostics.shared.record(.playerFailed, count: Int(result)) }
                    state.error = "No se pudo mostrar el vídeo. Prueba con otra fuente."
                }
            }
        }
        mpv_render_context_report_swap(renderer)
        // mpv leaves bindings at its defaults. GLKView owns nonzero buffers;
        // restore them before it presents or reads back this drawable.
        glBindFramebuffer(GLenum(GL_FRAMEBUFFER), GLuint(framebuffer))
        glBindRenderbuffer(GLenum(GL_RENDERBUFFER), GLuint(renderbuffer))
        glViewport(0, 0, GLsizei(surface.drawableWidth), GLsizei(surface.drawableHeight))
    }

    private func drainEvents(_ handle: OpaquePointer) {
        for _ in 0..<64 {
            guard let event = mpv_wait_event(handle, 0)?.pointee, event.event_id != MPV_EVENT_NONE else { return }
            switch event.event_id {
            case MPV_EVENT_COMMAND_REPLY, MPV_EVENT_SET_PROPERTY_REPLY:
                if event.reply_userdata != 0 {
                    finishOperation(event.reply_userdata, error: event.error < 0 ? HarborError(code: "mpv-\(event.error)") : nil)
                    continue
                }
                if event.error < 0 {
                    Diagnostics.shared.record(.playerFailed, count: Int(event.error))
                    state.error = "No se pudo completar la operación del reproductor. Vuelve a intentarlo."
                }
            case MPV_EVENT_START_FILE:
                mediaRevision += 1
                preferredSecondaryHandled = false
                state.mediaGeneration = mediaRevision
                state.tracks = []
                state.estimatedVideoFPS = nil
                state.containerVideoFPS = nil
                state.primarySubtitleText = ""
                state.secondarySubtitleText = ""
                state.subtitleIssue = nil
                state.importedSubtitleIDs = []
                state.subtitleImportMessage = nil
                state.ended = false
                state.endedNaturally = false
                state.loaded = false
                state.hasPosition = false
                state.position = 0
                state.duration = 0
            case MPV_EVENT_FILE_LOADED:
                state.loaded = true
                for subtitle in source.subtitles ?? [] {
                    run(["sub-add", subtitle.url, "auto", subtitle.lang ?? "", subtitle.lang ?? ""])
                }
            case MPV_EVENT_PROPERTY_CHANGE:
                guard let data = event.data else { continue }
                let property = data.assumingMemoryBound(to: mpv_event_property.self).pointee
                guard let name = property.name else { continue }
                let key = String(cString: name)
                guard let value = property.data, property.format != MPV_FORMAT_NONE else {
                    if key == "sub-fps" { state.subtitleFPS = nil }
                    if key == "estimated-vf-fps" { state.estimatedVideoFPS = nil }
                    if key == "container-fps" { state.containerVideoFPS = nil }
                    if key == "sub-text" { state.primarySubtitleText = "" }
                    if key == "secondary-sub-text" { state.secondarySubtitleText = "" }
                    continue
                }
                if property.format == MPV_FORMAT_DOUBLE {
                    let number = value.assumingMemoryBound(to: Double.self).pointee
                    guard number.isFinite else { continue }
                    if key == "speed" { state.speed = number }
                    if key == "volume" { state.volume = number }
                    if key == "audio-delay" { state.audioDelay = number }
                    if key == "sub-delay" { state.subtitleDelay = number }
                    if key == "sub-fps" { state.subtitleFPS = number >= 0 ? number : nil }
                    if key == "estimated-vf-fps" { state.estimatedVideoFPS = number > 0 ? number : nil }
                    if key == "container-fps" { state.containerVideoFPS = number > 0 ? number : nil }
                    if key == "time-pos" && state.loaded && number >= 0 { state.position = number; state.hasPosition = true }
                    if key == "duration" && number >= 0 {
                        state.duration = number
                        if !checkedResumeDuration && number > 0 {
                            checkedResumeDuration = true
                            // Desktop restarts a saved position in the last 20s.
                            if startMs > 5000 && startMs / 1000 >= number - 20 { run(["seek", "0", "absolute+exact"]) }
                        }
                    }
                } else if property.format == MPV_FORMAT_FLAG {
                    let flag = value.assumingMemoryBound(to: Int32.self).pointee != 0
                    if key == "pause" { state.paused = flag }
                    if key == "paused-for-cache" { state.buffering = flag }
                    if key == "mute" { state.muted = flag }
                } else if property.format == MPV_FORMAT_INT64 {
                    let number = value.assumingMemoryBound(to: Int64.self).pointee
                    if (1...32_768).contains(number) {
                        if key == "dwidth" { state.videoWidth = Int(number) }
                        if key == "dheight" { state.videoHeight = Int(number) }
                    }
                } else if key == "track-list" && property.format == MPV_FORMAT_NODE {
                    updateTracks(value.assumingMemoryBound(to: mpv_node.self).pointee)
                } else if key == "chapter-list" && property.format == MPV_FORMAT_NODE {
                    updateChapters(value.assumingMemoryBound(to: mpv_node.self).pointee)
                } else if property.format == MPV_FORMAT_STRING {
                    let text = value.assumingMemoryBound(to: UnsafePointer<CChar>?.self).pointee.map { String(cString: $0) } ?? ""
                    if key == "sub-text" { state.primarySubtitleText = text }
                    if key == "secondary-sub-text" { state.secondarySubtitleText = text }
                    if key == "current-vo" { videoOutputName = text }
                } else if property.format == MPV_FORMAT_NODE {
#if targetEnvironment(simulator)
                    if source.via == "test-fixture", ["video-dec-params", "video-out-params", "vf"].contains(key) {
                        print("Native fixture \(key): \(fixtureDescription(value.assumingMemoryBound(to: mpv_node.self).pointee))")
                    }
#endif
                }
            case MPV_EVENT_END_FILE:
                state.endedNaturally = false
                if let data = event.data {
                    let end = data.assumingMemoryBound(to: mpv_event_end_file.self).pointee
                    state.endedNaturally = end.reason == MPV_END_FILE_REASON_EOF && end.error >= 0
                    if end.error < 0 {
                        Diagnostics.shared.record(.playerFailed, count: Int(end.error))
                        state.error = "No se pudo abrir esta fuente. Prueba con otro enlace."
                    }
                }
                state.loaded = false
                state.ended = true
                state.buffering = false
                Diagnostics.shared.record(.playerEnded)
            case MPV_EVENT_SHUTDOWN: state.loaded = false
            default: break
            }
        }
    }

#if targetEnvironment(simulator)
    private func fixtureDescription(_ node: mpv_node, depth: Int = 0) -> String {
        guard depth < 4 else { return "…" }
        switch node.format {
        case MPV_FORMAT_STRING: return node.u.string.map { String(String(cString: $0).prefix(128)) } ?? ""
        case MPV_FORMAT_INT64: return String(node.u.int64)
        case MPV_FORMAT_DOUBLE: return String(node.u.double_)
        case MPV_FORMAT_FLAG: return node.u.flag == 0 ? "false" : "true"
        case MPV_FORMAT_NODE_MAP, MPV_FORMAT_NODE_ARRAY:
            guard let list = node.u.list, let values = list.pointee.values else { return "[]" }
            var fields: [String] = []
            for index in 0..<max(0, min(Int(list.pointee.num), 24)) {
                let name: String
                if let keys = list.pointee.keys, let key = keys[index] { name = String(cString: key) }
                else { name = String(index) }
                fields.append(name + "=" + fixtureDescription(values[index], depth: depth + 1))
            }
            return "[" + fields.joined(separator: ", ") + "]"
        default: return "unavailable"
        }
    }
#endif

    private func updateTracks(_ node: mpv_node) {
        guard node.format == MPV_FORMAT_NODE_ARRAY, let list = node.u.list, let values = list.pointee.values else { return }
        var tracks: [PlayerState.Track] = []
        for index in 0..<Int(list.pointee.num) {
            let item = values[index]
            guard item.format == MPV_FORMAT_NODE_MAP, let map = item.u.list, let keys = map.pointee.keys, let values = map.pointee.values else { continue }
            var fields: [String: mpv_node] = [:]
            for field in 0..<Int(map.pointee.num) {
                guard let name = keys[field] else { continue }
                fields[String(cString: name)] = values[field]
            }
            let string: (String) -> String? = { key in
                guard let value = fields[key], value.format == MPV_FORMAT_STRING, let pointer = value.u.string else { return nil }
                return String(cString: pointer)
            }
            guard let id = fields["id"], id.format == MPV_FORMAT_INT64, let type = string("type") else { continue }
            let label = [string("title"), string("lang"), string("codec")].compactMap { $0 }.joined(separator: " · ")
            let selected = fields["selected"].map { $0.format == MPV_FORMAT_FLAG && $0.u.flag != 0 } ?? false
            let flag: (String) -> Bool = { key in fields[key].map { $0.format == MPV_FORMAT_FLAG && $0.u.flag != 0 } ?? false }
            let selection = fields["main-selection"].flatMap { $0.format == MPV_FORMAT_INT64 ? Int($0.u.int64) : nil }
            tracks.append(.init(id: Int(id.u.int64), type: type, label: label.isEmpty ? "Pista \(id.u.int64)" : label, selected: selected,
                                codec: string("codec") ?? "", language: string("lang") ?? "", title: string("title") ?? "", externalFilename: string("external-filename") ?? "", mainSelection: selection,
                                external: flag("external"), forced: flag("forced"), hearingImpaired: flag("hearing-impaired"), defaultTrack: flag("default")))
        }
        state.tracks = tracks
        applyPreferredSecondary()
    }

    private func updateChapters(_ node: mpv_node) {
        guard node.format == MPV_FORMAT_NODE_ARRAY, let list = node.u.list, let values = list.pointee.values else { return }
        var chapters: [PlayerState.Chapter] = []
        for index in 0..<Int(list.pointee.num) {
            let item = values[index]
            guard item.format == MPV_FORMAT_NODE_MAP, let map = item.u.list, let keys = map.pointee.keys, let fields = map.pointee.values else { continue }
            var title = "Capítulo \(index + 1)"
            var time: Double?
            for field in 0..<Int(map.pointee.num) {
                guard let key = keys[field] else { continue }
                if String(cString: key) == "title", fields[field].format == MPV_FORMAT_STRING, let string = fields[field].u.string { title = String(cString: string) }
                if String(cString: key) == "time", fields[field].format == MPV_FORMAT_DOUBLE { time = fields[field].u.double_ }
            }
            if let time, time.isFinite, time >= 0 { chapters.append(.init(id: index, title: title, time: time)) }
        }
        state.chapters = chapters
    }

    func close() {
        guard !didClose else { return }
        set("pause", "yes")
        didClose = true
        pictureInPictureTask?.cancel(); pictureInPictureTask = nil
        inlineRestoreTask?.cancel(); inlineRestoreTask = nil
        sampleEvents?.cancel(); sampleEvents = nil
        pictureInPicture?.close(); pictureInPicture = nil
        sampleOutput?.close(); sampleOutput = nil
        state.pictureInPictureActive = false; state.pictureInPictureChanging = false; state.pictureInPictureSupported = false
        suspendedEvents?.cancel(); suspendedEvents = nil
        for token in lifecycleTokens { NotificationCenter.default.removeObserver(token) }
        lifecycleTokens = []
        mediaRevision += 1
        subtitleTail?.cancel()
        subtitleTail = nil
        for identifier in Array(pendingOperations.keys) { finishOperation(identifier, error: CancellationError()) }
        state.renderReady = false
        isPaused = true
        if UIApplication.shared.applicationState == .background, renderer != nil {
            // Freeing the mpv render context also issues GL commands. Retain
            // this closed surface until UIKit permits graphics work again.
            deferredCloseToken = NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [self] _ in
                MainActor.assumeIsolated { finishClosing() }
            }
        } else { finishClosing() }
        state.controller = nil
        do { try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation) }
        catch { state.playbackIssue = "No se pudo cerrar la sesión de audio." }
    }

    private func finishClosing() {
        guard UIApplication.shared.applicationState != .background || renderer == nil else { return }
        if let token = deferredCloseToken { NotificationCenter.default.removeObserver(token); deferredCloseToken = nil }
        if renderer != nil, let context { EAGLContext.setCurrent(context) }
        if let renderer { mpv_render_context_free(renderer); self.renderer = nil }
        if let handle { MPVConfiguration.destroy(handle); self.handle = nil }
        let session = subtitleSession
        Task { await SubtitleFileService.shared.cleanup(session) }
    }
}

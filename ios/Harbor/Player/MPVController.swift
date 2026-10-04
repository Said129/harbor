import AVFoundation
import Darwin
import GLKit
import Libmpv

/// All client/render/event access is serialized on the main actor. No escaping
/// C callbacks reference UIKit objects. mpv events, not button taps, own state.
@MainActor
final class MPVController: GLKViewController {
    let state: PlayerState
    private let source: PlaybackSource
    private var handle: OpaquePointer?
    private var renderer: OpaquePointer?
    private var context: EAGLContext?
    private var didClose = false

    init(source: PlaybackSource, state: PlayerState) {
        self.source = source; self.state = state
        super.init(nibName: nil, bundle: nil)
        state.controller = self
    }
    required init?(coder: NSCoder) { return nil }

    override func loadView() {
        guard let context = EAGLContext(api: .openGLES3) ?? EAGLContext(api: .openGLES2) else {
            view = UIView(); state.error = "No se pudo iniciar el render de vídeo."; return
        }
        self.context = context
        let surface = GLKView(frame: .zero, context: context)
        surface.drawableDepthFormat = .formatNone
        surface.backgroundColor = .black
        view = surface
        preferredFramesPerSecond = 60
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        do { try initialize() } catch { state.error = safeMessage(error); close() }
    }

    private func check(_ code: Int32) throws {
        guard code >= 0 else { throw HarborError(code: "mpv-\(code)") }
    }

    private func initialize() throws {
        guard let context, EAGLContext.setCurrent(context), let mpv = mpv_create() else { throw HarborError(code: "player-init") }
        handle = mpv
        try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try AVAudioSession.sharedInstance().setActive(true)
        for (key, value) in ["vo":"libmpv", "hwdec":"auto-safe", "config":"no", "ytdl":"no", "terminal":"no", "msg-level":"all=no", "cache":"yes", "demuxer-max-bytes":"64MiB", "network-timeout":"60"] {
            try check(mpv_set_option_string(mpv, key, value))
        }
        try check(mpv_initialize(mpv))
        try check(mpv_request_log_messages(mpv, "no"))
        var initialization = mpv_opengl_init_params(get_proc_address: { _, name in
            guard let name else { return nil }
            return dlsym(UnsafeMutableRawPointer(bitPattern: -2), name)
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
        for name in ["time-pos", "duration"] { try check(mpv_observe_property(mpv, 0, name, MPV_FORMAT_DOUBLE)) }
        for name in ["pause", "paused-for-cache"] { try check(mpv_observe_property(mpv, 0, name, MPV_FORMAT_FLAG)) }
        try check(mpv_observe_property(mpv, 0, "track-list", MPV_FORMAT_NODE))
        if let headers = source.headers {
            // mpv string-list escapes commas by doubling; reject CR/LF in Rust.
            let value = headers.sorted(by: { $0.key < $1.key }).map { "\($0.key): \($0.value)".replacingOccurrences(of: ",", with: ",,") }.joined(separator: ",")
            try check(mpv_set_property_string(mpv, "http-header-fields", value))
        }
        try command(["loadfile", source.url, "replace"])
        Diagnostics.shared.record(.playerStarted)
    }

    func command(_ values: [String]) throws {
        guard let handle else { throw HarborError(code: "player-not-ready") }
        let allocations = values.map { strdup($0) }
        defer { for allocation in allocations { free(allocation) } }
        var pointers: [UnsafePointer<CChar>?] = allocations.map { $0.map(UnsafePointer.init) } + [nil]
        try check(mpv_command(handle, &pointers))
    }

    func set(_ name: String, _ value: String) {
        guard let handle else { return }
        do { try check(mpv_set_property_string(handle, name, value)) } catch { state.error = safeMessage(error) }
    }
    func run(_ values: [String]) {
        do { try command(values) } catch { state.error = safeMessage(error) }
    }

    override func glkView(_ surface: GLKView, drawIn rect: CGRect) {
        guard let renderer, let handle, let context else { return }
        EAGLContext.setCurrent(context)
        drainEvents(handle)
        var framebuffer: GLint = 0
        glGetIntegerv(GLenum(GL_FRAMEBUFFER_BINDING), &framebuffer)
        var fbo = mpv_opengl_fbo(fbo: framebuffer, w: Int32(surface.drawableWidth), h: Int32(surface.drawableHeight), internal_format: 0)
        var flip: Int32 = 1
        withUnsafeMutablePointer(to: &fbo) { fbo in
            withUnsafeMutablePointer(to: &flip) { flip in
                var parameters = [mpv_render_param(type: MPV_RENDER_PARAM_OPENGL_FBO, data: fbo), mpv_render_param(type: MPV_RENDER_PARAM_FLIP_Y, data: flip), mpv_render_param(type: MPV_RENDER_PARAM_INVALID, data: nil)]
                let result = mpv_render_context_render(renderer, &parameters)
                if result < 0 { state.error = "Error de render mpv: \(result)" }
            }
        }
        mpv_render_context_report_swap(renderer)
    }

    private func drainEvents(_ handle: OpaquePointer) {
        for _ in 0..<64 {
            guard let event = mpv_wait_event(handle, 0)?.pointee, event.event_id != MPV_EVENT_NONE else { return }
            switch event.event_id {
            case MPV_EVENT_FILE_LOADED:
                state.loaded = true
                for subtitle in source.subtitles ?? [] {
                    run(["sub-add", subtitle.url, "auto", subtitle.lang ?? "", subtitle.lang ?? ""])
                }
            case MPV_EVENT_PROPERTY_CHANGE:
                guard let data = event.data else { continue }
                let property = data.assumingMemoryBound(to: mpv_event_property.self).pointee
                guard let name = property.name, let value = property.data else { continue }
                let key = String(cString: name)
                if property.format == MPV_FORMAT_DOUBLE {
                    let number = value.assumingMemoryBound(to: Double.self).pointee
                    if key == "time-pos" { state.position = max(0, number) }
                    if key == "duration" { state.duration = max(0, number) }
                } else if property.format == MPV_FORMAT_FLAG {
                    let flag = value.assumingMemoryBound(to: Int32.self).pointee != 0
                    if key == "pause" { state.paused = flag }
                    if key == "paused-for-cache" { state.buffering = flag }
                } else if key == "track-list" && property.format == MPV_FORMAT_NODE {
                    updateTracks(value.assumingMemoryBound(to: mpv_node.self).pointee)
                }
            case MPV_EVENT_END_FILE:
                if let data = event.data {
                    let end = data.assumingMemoryBound(to: mpv_event_end_file.self).pointee
                    if end.error < 0 { state.error = "No se pudo reproducir esta fuente (mpv \(end.error))." }
                }
                state.loaded = false
                Diagnostics.shared.record(.playerEnded)
            case MPV_EVENT_SHUTDOWN: state.loaded = false
            default: break
            }
        }
    }

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
            tracks.append(.init(id: Int(id.u.int64), type: type, label: label.isEmpty ? "Pista \(id.u.int64)" : label, selected: selected))
        }
        state.tracks = tracks
    }

    func close() {
        guard !didClose else { return }
        didClose = true
        isPaused = true
        if let context { EAGLContext.setCurrent(context) }
        if let renderer { mpv_render_context_free(renderer); self.renderer = nil }
        if let handle { mpv_terminate_destroy(handle); self.handle = nil }
        state.controller = nil
        do { try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation) }
        catch { state.error = "No se pudo cerrar la sesión de audio." }
    }
}

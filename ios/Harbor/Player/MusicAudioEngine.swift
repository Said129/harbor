import Foundation
import Libmpv

enum MusicAudioEvent: Sendable {
    case started, loaded, failed
    case time(Double), duration(Double), paused(Bool), volume(Double)
    case ended(natural: Bool, failed: Bool)
}
enum MusicAudioCommand: Sendable { case paused(Bool), seek(Double), volume(Double) }
protocol MusicAudioEngineOperating: Sendable {
    func configure(_ plan: MusicAudioPlan, request: UInt64) async throws
    func open(_ stream: MusicAudioStream, request: UInt64, volume: Double, paused: Bool) async throws
    func read(request: UInt64) async -> [MusicAudioEvent]
    func command(_ command: MusicAudioCommand, request: UInt64) async throws
    func signal(request: UInt64) async -> MusicAudioSignal?
    func stop(request: UInt64) async
}
extension MusicAudioEngineOperating {
    func signal(request: UInt64) async -> MusicAudioSignal? { nil }
    func configure(_ plan: MusicAudioPlan, request: UInt64) async throws {
        guard plan == .defaults else { throw HarborError(code: "music-audio-unavailable") }
    }
}

/// One serialized owner for libmpv. Core construction and teardown never run on
/// the main actor. A fresh core also fences old events and source HTTP headers.
actor MusicAudioEngine: MusicAudioEngineOperating {
    private var handle: OpaquePointer?
    private var newest: UInt64 = 0
    private var processing = MusicAudioPlan.defaults
    func configure(_ plan: MusicAudioPlan, request: UInt64) async throws {
        guard request >= newest else { throw CancellationError() }
        guard MusicAudioRuntime.supports(plan) else { throw HarborError(code: "music-audio-unavailable") }
        if let handle, request == newest {
            do { try apply(plan, to: handle) }
            catch { try? apply(processing, to: handle); throw error }
        }
        processing = plan
    }
    private func apply(_ plan: MusicAudioPlan, to handle: OpaquePointer) throws {
        for (name, value) in [("af", plan.filter), ("replaygain", plan.settings.dspBypass || plan.settings.replayGain == "off" ? "no" : plan.settings.replayGain),
                              ("replaygain-clip", "no"), ("replaygain-preamp", "0"), ("replaygain-fallback", "0"),
                              ("speed", String(plan.settings.speed)), ("audio-pitch-correction", plan.settings.keepPitch ? "yes" : "no"),
                              ("audio-samplerate", String(plan.settings.sampleRate)),
                              ("volume-max", String(plan.volumeMaximum))] {
            guard mpv_set_property_string(handle, name, value) >= 0 else { throw HarborError(code: "music-audio-unavailable") }
        }
    }
    func open(_ stream: MusicAudioStream, request: UInt64, volume: Double, paused: Bool) async throws {
        try Task.checkCancellation()
        guard request >= newest else { throw CancellationError() }
        guard volume.isFinite, !stream.url.absoluteString.isEmpty else { throw HarborError(code: "music-player") }
        _ = try MusicStreamHeaders.fields(stream.httpHeaders)
        newest = request; retire()
        guard let created = mpv_create() else { throw HarborError(code: "music-player") }
        do {
            for (name, value) in [("config", "no"), ("terminal", "no"), ("msg-level", "all=no"), ("vo", "null"), ("vid", "no"), ("audio-display", "no"), ("access-references", "no"), ("keep-open", "no")] {
                guard mpv_set_option_string(created, name, value) >= 0 else { throw HarborError(code: "music-player") }
            }
            for (name, value) in [("ytdl", "no"), ("cache", "yes"), ("cache-secs", "30"), ("cache-pause", "yes"), ("network-timeout", "30")] { _ = mpv_set_option_string(created, name, value) }
            guard mpv_initialize(created) >= 0 else { throw HarborError(code: "music-player") }
            try apply(processing, to: created)
            let agent: String
            if let value = mpv_get_property_string(created, "user-agent") { agent = String(cString: value); mpv_free(value) }
            else { agent = "Harbor/1.0" }
            try MusicStreamHeaders.apply(stream.httpHeaders, to: created, defaultAgent: agent)
            for property in ["time-pos", "duration", "volume"] {
                guard mpv_observe_property(created, 0, property, MPV_FORMAT_DOUBLE) >= 0 else { throw HarborError(code: "music-player") }
            }
            guard mpv_observe_property(created, 0, "pause", MPV_FORMAT_FLAG) >= 0 else { throw HarborError(code: "music-player") }
            guard mpv_set_property_string(created, "volume", String(min(processing.volumeMaximum, max(0, volume)))) >= 0,
                  mpv_set_property_string(created, "pause", paused ? "yes" : "no") >= 0 else { throw HarborError(code: "music-player") }
            try Task.checkCancellation()
            try MusicMPV.command(created, ["loadfile", stream.url.isFileURL ? stream.url.path : stream.url.absoluteString, "replace"])
            try Task.checkCancellation()
            handle = created
        } catch { mpv_terminate_destroy(created); throw error }
    }
    func stop(request: UInt64) async {
        guard request >= newest else { return }; newest = request; retire()
    }
    private func retire() {
        let previous = handle; handle = nil
        if let previous { mpv_terminate_destroy(previous) }
    }
    func signal(request: UInt64) async -> MusicAudioSignal? {
        guard request == newest, let handle else { return nil }
        func string(_ name: String) -> String? {
            guard let value = mpv_get_property_string(handle, name) else { return nil }
            defer { mpv_free(value) }; let text = String(cString: value)
            return text.isEmpty ? nil : text
        }
        func number(_ name: String) -> Double? {
            var value = 0.0
            guard mpv_get_property(handle, name, MPV_FORMAT_DOUBLE, &value) >= 0, value.isFinite else { return nil }
            return value
        }
        return MusicAudioSignal(codec: string("audio-codec-name"), sourceRate: number("audio-params/samplerate"), outputRate: number("audio-out-params/samplerate"),
                                sourceChannels: string("audio-params/hr-channels"), outputChannels: string("audio-out-params/hr-channels"),
                                format: string("audio-params/format"), bitrate: number("audio-bitrate"), backend: string("current-ao"),
                                filters: string("af"), speed: number("speed"), replayGain: string("replaygain"))
    }
    func command(_ command: MusicAudioCommand, request: UInt64) async throws {
        guard request == newest, let handle else { return }
        let result: Int32
        switch command {
        case .paused(let value):
            var flag: Int32 = value ? 1 : 0
            result = mpv_set_property_async(handle, 0, "pause", MPV_FORMAT_FLAG, &flag)
        case .volume(let value):
            guard value.isFinite else { throw HarborError(code: "music-player") }; var volume = min(processing.volumeMaximum, max(0, value))
            result = mpv_set_property_async(handle, 0, "volume", MPV_FORMAT_DOUBLE, &volume)
        case .seek(let value):
            guard value.isFinite, value >= 0 else { throw HarborError(code: "music-player") }
            try MusicMPV.command(handle, ["seek", String(value), "absolute+exact"]); return
        }
        guard result >= 0 else { throw HarborError(code: "music-player") }
    }
    func read(request: UInt64) async -> [MusicAudioEvent] {
        guard request == newest, let handle else { return [] }
        var result: [MusicAudioEvent] = []
        for _ in 0..<64 {
            guard let event = mpv_wait_event(handle, 0)?.pointee, event.event_id != MPV_EVENT_NONE else { break }
            switch event.event_id {
            case MPV_EVENT_START_FILE: result.append(.started)
            case MPV_EVENT_FILE_LOADED: result.append(.loaded)
            case MPV_EVENT_END_FILE:
                if let data = event.data {
                    let end = data.assumingMemoryBound(to: mpv_event_end_file.self).pointee
                    result.append(.ended(natural: end.reason == MPV_END_FILE_REASON_EOF, failed: end.error < 0))
                }
            case MPV_EVENT_PROPERTY_CHANGE:
                guard let data = event.data else { continue }
                let property = data.assumingMemoryBound(to: mpv_event_property.self).pointee
                guard let raw = property.name, let value = property.data else { continue }
                let name = String(cString: raw)
                if property.format == MPV_FORMAT_DOUBLE {
                    let number = value.assumingMemoryBound(to: Double.self).pointee
                    guard number.isFinite, number >= 0 else { continue }
                    switch name {
                    case "time-pos": result.append(.time(number))
                    case "duration": result.append(.duration(number))
                    case "volume": result.append(.volume(number))
                    default: break
                    }
                } else if name == "pause", property.format == MPV_FORMAT_FLAG { result.append(.paused(value.assumingMemoryBound(to: Int32.self).pointee != 0)) }
            case MPV_EVENT_COMMAND_REPLY, MPV_EVENT_SET_PROPERTY_REPLY:
                if event.error < 0 { result.append(.failed) }
            default: break
            }
        }
        return result
    }
}

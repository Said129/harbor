import Darwin
import Foundation
import Libmpv

struct MusicMeterChannel: Sendable {
    let rmsDb: Double
    let peakDb: Double
}
struct MusicMeterMeasurement: Sendable {
    let active: Bool
    let channels: [MusicMeterChannel]
    let spectrumDb: [Double]
    let outputRate: Double?
    let outputChannels: String?
    let outputDevice: String?
    let outputBackend: String?
}
struct MusicMeterSnapshot: Sendable {
    let trackID: String
    let connectorID: String?
    let measurement: MusicMeterMeasurement
}

/// The pinned Desktop telemetry/spectrum graph: analysis is split from the
/// audible branch and measured in 50 ms windows, not inferred from volume.
enum MusicAudioMeter {
    static let label = "harbor_meter"
    static let frequencies = [60, 120, 250, 500, 1000, 2000, 4000, 8000]
    static let filters = ["asplit", "aresample", "asetnsamples", "bandpass", "astats", "ametadata", "anullsink"]
    static var supported: Bool { MusicAudioRuntime.supports(filters) }
    static let filter: String = {
        let stats = "astats=metadata=1:reset=1:measure_perchannel=RMS_level+Peak_level:measure_overall=none"
        var graph = "[in]asplit=2[main][analysis];[main]\(stats)[out];[analysis]aresample=24000,asetnsamples=n=1200:p=0,asplit=8"
        for index in frequencies.indices { graph += "[b\(index)]" }
        for (index, frequency) in frequencies.enumerated() {
            graph += ";[b\(index)]bandpass=f=\(frequency):t=o:w=1,astats=metadata=1:reset=1:measure_perchannel=none:measure_overall=RMS_level,ametadata@harbor_band_\(index)=print:key=lavfi.astats.Overall.RMS_level,anullsink"
        }
        return "@\(label):lavfi=[\(graph)]"
    }()
    static func chain(_ processing: String, enabled: Bool) -> String {
        !enabled ? processing : processing.isEmpty ? filter : processing + "," + filter
    }
    /// Desktop's telemetry::set_enabled: add or remove only the labelled
    /// analysis branch, synchronously, without rewriting audible processing.
    static func toggle(_ handle: OpaquePointer, enabled: Bool) -> Int32 {
        let values = enabled ? ["af", "add", filter] : ["af", "remove", "@" + label]
        let allocations = values.map { strdup($0) }
        defer { allocations.forEach { free($0) } }
        guard allocations.allSatisfy({ $0 != nil }) else { return -1 }
        var pointers: [UnsafePointer<CChar>?] = allocations.map { $0.map { UnsafePointer<CChar>($0) } } + [nil]
        return mpv_command(handle, &pointers)
    }
    static func failure(_ operation: String, _ status: Int32) -> String {
        operation + ": " + String(status) + " " + String(cString: mpv_error_string(status))
    }
    static func decibels(_ value: String) -> Double? {
        guard let number = Double(value.trimmingCharacters(in: .whitespacesAndNewlines)) else { return nil }
        if number == -.infinity { return -120 }
        return number.isFinite ? min(24, max(-120, number)) : nil
    }
    static func bounded(_ pointer: UnsafePointer<CChar>?, limit: Int) -> String? {
        guard let pointer else { return nil }
        let length = strnlen(pointer, limit + 1)
        guard length <= limit else { return nil }
        return String(bytes: UnsafeBufferPointer(start: UnsafeRawPointer(pointer).assumingMemoryBound(to: UInt8.self), count: length), encoding: .utf8)
    }
    static func string(_ handle: OpaquePointer, _ key: String) -> String? {
        guard let pointer = mpv_get_property_string(handle, key) else { return nil }
        defer { mpv_free(pointer) }
        return bounded(UnsafePointer(pointer), limit: 512).flatMap { $0.isEmpty ? nil : $0 }
    }
    static func number(_ handle: OpaquePointer, _ key: String) -> Double? {
        var value = 0.0
        guard mpv_get_property(handle, key, MPV_FORMAT_DOUBLE, &value) >= 0, value.isFinite else { return nil }
        return value
    }
    static func snapshot(_ handle: OpaquePointer, spectrum: MusicAudioSpectrum) -> MusicMeterMeasurement {
        var rms = Array<Double?>(repeating: nil, count: 8)
        var peaks = rms
        var node = mpv_node()
        if mpv_get_property(handle, "af-metadata/" + label, MPV_FORMAT_NODE, &node) >= 0 {
            defer { mpv_free_node_contents(&node) }
            if node.format == MPV_FORMAT_NODE_MAP, let list = node.u.list, let keys = list.pointee.keys, let values = list.pointee.values {
                for index in 0..<max(0, min(Int(list.pointee.num), 32)) {
                    guard let rawKey = keys[index], let key = bounded(UnsafePointer(rawKey), limit: 128), key.hasPrefix("lavfi.astats."),
                          values[index].format == MPV_FORMAT_STRING,
                          let rawValue = values[index].u.string,
                          let text = bounded(UnsafePointer(rawValue), limit: 128), let level = decibels(text) else { continue }
                    let field = key.dropFirst("lavfi.astats.".count).split(separator: ".", maxSplits: 1)
                    guard field.count == 2, let channel = Int(field[0]), (1...8).contains(channel) else { continue }
                    if field[1] == "RMS_level" { rms[channel - 1] = level }
                    if field[1] == "Peak_level" { peaks[channel - 1] = level }
                }
            }
        }
        var channels: [MusicMeterChannel] = []
        for index in 0..<8 {
            guard let average = rms[index], let peak = peaks[index] else { break }
            channels.append(.init(rmsDb: average, peakDb: peak))
        }
        let active = ["pause", "paused-for-cache", "eof-reached", "seeking"].allSatisfy { name in
            var flag: Int32 = 0
            return mpv_get_property(handle, name, MPV_FORMAT_FLAG, &flag) < 0 || flag == 0
        }
        let rate = number(handle, "audio-out-params/samplerate").flatMap { (0...3_072_000).contains($0) && $0 > 0 ? $0 : nil }
        let bands = active ? number(handle, "time-pos").map { spectrum.at($0) } ?? [] : []
        return .init(active: active, channels: channels, spectrumDb: bands, outputRate: rate,
                     outputChannels: string(handle, "audio-out-params/channels"), outputDevice: string(handle, "audio-device"),
                     outputBackend: string(handle, "current-ao"))
    }
}

/// Desktop's bounded timestamped history. Decode-ahead samples cannot animate
/// the current frame; only exact named metadata is retained from decoder logs.
struct MusicAudioSpectrum: Sendable {
    private struct Sample: Sendable { let time: Double; let level: Double }
    private var pending = Array<Double?>(repeating: nil, count: 8)
    private var samples = Array(repeating: [Sample](), count: 8)
    mutating func clear() { self = .init() }
    mutating func ingest(_ text: String) {
        let prefix = "ametadata@harbor_band_"
        guard text.hasPrefix(prefix), let separator = text.range(of: ": ") else { return }
        let start = text.index(text.startIndex, offsetBy: prefix.count)
        guard separator.lowerBound >= start, let index = Int(text[start..<separator.lowerBound]), (0..<8).contains(index) else { return }
        let value = String(text[separator.upperBound...])
        if let marker = value.range(of: "pts_time:") {
            pending[index] = Double(value[marker.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isFinite ? $0 : nil }
        } else if value.hasPrefix("lavfi.astats.Overall.RMS_level=") {
            guard let time = pending[index] else { return }
            pending[index] = nil
            guard let level = MusicAudioMeter.decibels(String(value.dropFirst("lavfi.astats.Overall.RMS_level=".count))) else { return }
            if let last = samples[index].last, last.time > time { samples[index].removeAll(keepingCapacity: true) }
            samples[index].append(.init(time: time, level: level))
            if samples[index].count > 128 { samples[index].removeFirst(samples[index].count - 128) }
        }
    }
    func at(_ position: Double) -> [Double] {
        guard position.isFinite else { return [] }
        return samples.map { values in
            values.reversed().first { $0.time <= position + 0.025 && position - $0.time < 0.25 }?.level ?? -120
        }
    }
}

import Accelerate
import Foundation
import Libmpv

/// An independent, silent libmpv handle decodes only audio on a utility task.
/// The playback handle and its rendering/event callbacks never wait for analysis.
enum SubtitleAutoSync {
    struct Window: Sendable { let start: Double; let length: Double }
    static func windows(_ duration: Double) -> [Window] {
        if duration < 900 {
            let start = max(5, duration * 0.05)
            return [.init(start: start, length: max(30, duration * 0.9 - start))]
        }
        let late = max(780, duration - 720)
        return [.init(start: 180, length: 600), .init(start: late, length: min(600, duration - late))]
    }

    static func analyze(source: PlaybackSource, subtitle: String, duration: Double, audioID: Int?) async throws -> (SubtitleDocument, SubtitleSyncResult?) {
        guard duration.isFinite, (60...28_800).contains(duration) else { throw HarborError(code: "subtitle-sync-duration") }
        let document = try await load(subtitle)
        let windows = windows(duration)
        var intervals: [(Double, Double)] = []
        for window in windows {
            try Task.checkCancellation()
            intervals += try speech(source, window: window, audioID: audioID)
        }
        try Task.checkCancellation()
        return (document, try solve(audio: intervals, cues: document.cues.map { ($0.start, $0.end) }, duration: duration, windows: windows))
    }

    private static func load(_ path: String) async throws -> SubtitleDocument {
        let url = path.hasPrefix("/") ? URL(fileURLWithPath: path) : URL(string: path)
        guard let url else { throw HarborError(code: "subtitle-sync-format") }
        let limit = 8 * 1_024 * 1_024
        let data: Data
        if url.isFileURL {
            guard let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > 0, size <= limit else { throw HarborError(code: "subtitle-sync-format") }
            data = try Data(contentsOf: url)
        } else {
            guard ["https", "http"].contains(url.scheme?.lowercased() ?? "") else { throw HarborError(code: "subtitle-sync-format") }
            let configuration = URLSessionConfiguration.ephemeral
            configuration.httpShouldSetCookies = false; configuration.httpCookieStorage = nil; configuration.urlCache = nil
            let session = URLSession(configuration: configuration)
            defer { session.invalidateAndCancel() }
            let (bytes, response) = try await session.bytes(for: URLRequest(url: url, timeoutInterval: 20))
            guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode), response.expectedContentLength <= Int64(limit) else { throw HarborError(code: "subtitle-sync-format") }
            var received = Data()
            for try await byte in bytes {
                try Task.checkCancellation()
                guard received.count < limit else { throw HarborError(code: "subtitle-sync-format") }
                received.append(byte)
            }
            data = received
        }
        return try SubtitleDocument(decode(data))
    }

    static func decode(_ data: Data) throws -> String {
        let prefix = data.prefix(2)
        let encoding: String.Encoding = prefix == Data([0xff, 0xfe]) || prefix == Data([0xfe, 0xff]) ? .utf16 : .utf8
        // Do not guess a legacy encoding and silently replace the subtitle's
        // text. Unsupported byte sequences leave the original track intact.
        guard let text = String(data: data, encoding: encoding) else { throw HarborError(code: "subtitle-sync-encoding") }
        return text
    }

    private static func speechPCM(_ data: Data, window: Window) throws -> [(Double, Double)] {
        // MPVKit excludes silencedetect/highpass/lowpass/ametadata. Decode mono
        // s16 PCM with mpv's file output, then measure voice-band energy here.
        let rate = 8_000, frame = 160
        let count = min(data.count / 2, Int(window.length * Double(rate)))
        guard count > 0, data.count.isMultiple(of: 2) else { throw HarborError(code: "subtitle-sync-pcm") }
        let highAlpha = 1 / (1 + 2 * Double.pi * 200 / Double(rate))
        let lowAlpha = 1 / (1 + Double(rate) / (2 * Double.pi * 3_000))
        var previous = 0.0, high = 0.0, low = 0.0, energy = 0.0
        var active: Double?, lastVoice = window.start
        var result: [(Double, Double)] = []
        try data.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) -> Void in
            for index in 0..<count {
                if index.isMultiple(of: rate) { try Task.checkCancellation() }
                let sample = Double(Int16(littleEndian: bytes.loadUnaligned(fromByteOffset: index * 2, as: Int16.self))) / 32_768
                high = highAlpha * (high + sample - previous); previous = sample
                low += lowAlpha * (high - low); energy += low * low
                if (index + 1).isMultiple(of: frame) || index + 1 == count {
                    let samples = index % frame + 1
                    let start = window.start + Double(index + 1 - samples) / Double(rate)
                    let end = window.start + Double(index + 1) / Double(rate)
                    if sqrt(energy / Double(samples)) >= 0.0316227766 {
                        if active == nil { active = start }
                        lastVoice = end
                    } else if let begin = active, end - lastVoice >= 0.35 {
                        result.append((begin, lastVoice)); active = nil
                    }
                    energy = 0
                }
            }
        }
        if let begin = active { result.append((begin, lastVoice)) }
        return result
    }

    static func speech(_ source: PlaybackSource, window: Window, audioID: Int?) throws -> [(Double, Double)] {
        let pcm = FileManager.default.temporaryDirectory.appendingPathComponent("harbor-sub-sync-" + UUID().uuidString + ".pcm")
        guard FileManager.default.createFile(atPath: pcm.path, contents: nil, attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]) else { throw HarborError(code: "subtitle-sync-file") }
        defer { try? FileManager.default.removeItem(at: pcm) }
        guard let handle = mpv_create() else { throw HarborError(code: "subtitle-sync-audio") }
        var destroyed = false
        defer { if !destroyed { mpv_terminate_destroy(handle) } }
        let options = [("config", "no"), ("load-scripts", "no"), ("terminal", "no"), ("vid", "no"), ("sid", "no"),
                       ("ao", "pcm"), ("ao-pcm-file", pcm.path), ("ao-pcm-waveheader", "no"),
                       ("audio-format", "s16"), ("audio-samplerate", "8000"), ("audio-channels", "mono"),
                       ("untimed", "yes"), ("audio-pitch-correction", "no"), ("keep-open", "no"),
                       ("network-timeout", "10"), ("cache", "no"), ("demuxer-max-bytes", "16MiB"),
                       ("aid", audioID.map(String.init) ?? "auto"), ("start", String(window.start)), ("length", String(window.length)),
                       ("msg-level", "all=no")]
        for (name, value) in options { guard mpv_set_option_string(handle, name, value) >= 0 else { throw HarborError(code: "subtitle-sync-option-" + name) } }
        if let headers = source.headers, !headers.isEmpty {
            let value = headers.sorted { $0.key < $1.key }.map { "\($0.key): \($0.value)".replacingOccurrences(of: ",", with: ",,") }.joined(separator: ",")
            guard !value.contains("\r"), !value.contains("\n"), mpv_set_option_string(handle, "http-header-fields", value) >= 0 else { throw HarborError(code: "subtitle-sync-audio") }
        }
        guard mpv_initialize(handle) >= 0 else { throw HarborError(code: "subtitle-sync-audio") }
        let command = ["loadfile", source.url]
        let arguments = command.map { strdup($0) }
        defer { arguments.forEach { free($0) } }
        guard arguments.allSatisfy({ $0 != nil }) else { throw HarborError(code: "subtitle-sync-audio") }
        var pointers = arguments.map { $0.map { UnsafePointer<CChar>($0) } } + [nil]
        guard mpv_command_async(handle, 1, &pointers) >= 0 else { throw HarborError(code: "subtitle-sync-audio") }
        let deadline = Date().addingTimeInterval(90)
        while Date() < deadline {
            try Task.checkCancellation()
            guard let event = mpv_wait_event(handle, 0.1)?.pointee else { continue }
            if event.event_id == MPV_EVENT_END_FILE {
                guard let data = event.data else { throw HarborError(code: "subtitle-sync-audio") }
                let end = data.assumingMemoryBound(to: mpv_event_end_file.self).pointee
                guard end.error >= 0, end.reason == MPV_END_FILE_REASON_EOF else { throw HarborError(code: "subtitle-sync-decode-\(end.error)") }
                mpv_terminate_destroy(handle); destroyed = true
                let limit = Int((window.length + 1) * 8_000 * 2)
                guard let size = try pcm.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > 0, size <= limit else { throw HarborError(code: "subtitle-sync-pcm-size") }
                return try speechPCM(Data(contentsOf: pcm), window: window)
            }
            if event.event_id == MPV_EVENT_COMMAND_REPLY && event.error < 0 { throw HarborError(code: "subtitle-sync-audio") }
        }
        throw HarborError(code: "subtitle-sync-timeout")
    }

    // Desktop's offset/FPS hypotheses and confidence gates, at a 100 ms grid.
    // FFT correlation avoids quadratic work on an iPhone. Only analyzed windows
    // contribute to confidence; unobserved audio is not mistaken for silence.
    static func solve(audio: [(Double, Double)], cues: [(Double, Double)], duration: Double, windows: [Window]) throws -> SubtitleSyncResult? {
        let hz = 10.0, maxLag = 600
        guard duration.isFinite, duration > 0, duration <= 28_800, cues.count >= 4, !audio.isEmpty else { return nil }
        let length = Int((duration * hz).rounded()) + 1
        let power = Int(ceil(log2(Double(length + maxLag + 1))))
        let count = 1 << power
        guard let setup = vDSP_create_fftsetup(vDSP_Length(power), FFTRadix(kFFTRadix2)) else { throw HarborError(code: "subtitle-sync-audio") }
        defer { vDSP_destroy_fftsetup(setup) }
        func raster(_ intervals: [(Double, Double)], ratio: Double) -> [Float] {
            var values = [Float](repeating: 0, count: count)
            for (start, end) in intervals where start.isFinite && end.isFinite && end > start {
                let first = Int(max(0, min(Double(length), (start * ratio * hz).rounded())))
                let last = Int(max(0, min(Double(length), (end * ratio * hz).rounded())))
                if last > first { for index in first..<last { values[index] = 1 } }
            }
            return values
        }
        func fft(_ real: inout [Float], _ imaginary: inout [Float], _ direction: FFTDirection) {
            real.withUnsafeMutableBufferPointer { r in
                imaginary.withUnsafeMutableBufferPointer { i in
                    var split = DSPSplitComplex(realp: r.baseAddress!, imagp: i.baseAddress!)
                    vDSP_fft_zip(setup, &split, 1, vDSP_Length(power), direction)
                }
            }
        }
        let audioMask = raster(audio, ratio: 1)
        let observed = raster(windows.map { ($0.start, $0.start + $0.length) }, ratio: 1)
        var audioReal = audioMask, audioImaginary = [Float](repeating: 0, count: count)
        fft(&audioReal, &audioImaginary, FFTDirection(FFT_FORWARD))
        var ratios: [Double] = []
        for value in [1.0, 1.25, 0.8, 1.0427, 1.00092, 1.04167] {
            for ratio in [value, 1 / value] where !ratios.contains(where: { abs($0 - ratio) < 0.00001 }) { ratios.append(ratio) }
        }
        var best: SubtitleSyncResult?
        for ratio in ratios {
            try Task.checkCancellation()
            let mask = raster(cues, ratio: ratio)
            var real = mask, imaginary = [Float](repeating: 0, count: count)
            fft(&real, &imaginary, FFTDirection(FFT_FORWARD))
            for index in 0..<count {
                let r = audioReal[index] * real[index] + audioImaginary[index] * imaginary[index]
                let i = audioImaginary[index] * real[index] - audioReal[index] * imaginary[index]
                real[index] = r; imaginary[index] = i
            }
            fft(&real, &imaginary, FFTDirection(FFT_INVERSE))
            let correlation = (-maxLag...maxLag).map { lag in Double(real[lag >= 0 ? lag : count + lag]) / Double(count) }
            guard let peakIndex = correlation.indices.max(by: { correlation[$0] < correlation[$1] }) else { continue }
            let peak = correlation[peakIndex], lag = peakIndex - maxLag
            let mean = correlation.reduce(0, +) / Double(correlation.count)
            let deviation = sqrt(correlation.reduce(0) { $0 + pow($1 - mean, 2) } / Double(correlation.count))
            let second = correlation.enumerated().filter { abs($0.offset - peakIndex) > Int(hz) }.map(\.element).max() ?? 0
            var sx = 0.0, sy = 0.0, xy = 0.0, n = 0.0
            for index in 0..<length where observed[index] > 0 {
                let other = index - lag
                guard other >= 0, other < length else { continue }
                let x = Double(audioMask[index]), y = Double(mask[other])
                sx += x; sy += y; xy += x * y; n += 1
            }
            guard n > 0 else { continue }
            let denominator = sqrt(max(0, (sx - sx * sx / n) * (sy - sy * sy / n)))
            let confidence = denominator > 0 ? (xy - sx * sy / n) / denominator : 0
            guard confidence >= 0.55, deviation > 0, (peak - mean) / deviation >= 6,
                  second <= 0 || peak / second >= 1.3 else { continue }
            if confidence > (best?.confidence ?? 0) { best = .init(offset: Double(lag) / hz, ratio: ratio, confidence: confidence) }
        }
        return best
    }
}

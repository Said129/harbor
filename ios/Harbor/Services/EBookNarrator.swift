import AVFoundation
import Foundation
import Observation

@MainActor @Observable final class EBookNarrator: NSObject, AVAudioPlayerDelegate, AVSpeechSynthesizerDelegate {
    private(set) var speaking = false
    private(set) var paused = false
    private(set) var loading = false
    private(set) var progress = 0
    private(set) var position = 0.0
    private(set) var duration = 0.0
    private(set) var currentBlock: Int?
    private(set) var notice: String?
    private(set) var previewID: String?
    private(set) var voices: [EBookNarrationVoice] = []
    private(set) var loadingVoices = false
    private(set) var voiceFailure = false
    @ObservationIgnored private var client: EBookNarrationClient?
    @ObservationIgnored private var catalog: EBookNarrationCatalog?
    @ObservationIgnored private var owner: String?
    @ObservationIgnored private let transport: any EBookNarrationTransport
    @ObservationIgnored private var voiceRun = UUID()
    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private let speech = AVSpeechSynthesizer()
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var clock: Task<Void, Never>?
    @ObservationIgnored private var ahead: (start: Int, task: Task<EBookNarrationAudio, Error>)?
    @ObservationIgnored private var run = UUID()
    @ObservationIgnored private var paragraphs: [EBookSearchParagraph] = []
    @ObservationIgnored private var window: EBookNarrationWindow?
    @ObservationIgnored private var boundaries: [EBookNarrationBoundary] = []
    @ObservationIgnored private var selectedVoice: EBookNarrationVoice?
    @ObservationIgnored private var step = 0
    @ObservationIgnored private var speed = 1.0
    @ObservationIgnored private var device = false
    @ObservationIgnored private var utterance: ObjectIdentifier?
    @ObservationIgnored private var deviceLine = 0
    @ObservationIgnored private var audioActive = false
    @ObservationIgnored private var notifications: [NSObjectProtocol] = []
    init(transport: any EBookNarrationTransport = EBookEdgeTransport()) {
        self.transport = transport; super.init(); speech.delegate = self
        let center = NotificationCenter.default
        notifications.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: nil) { [weak self] notification in
            let began = (notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt) == AVAudioSession.InterruptionType.began.rawValue
            if began { Task { @MainActor in self?.pause() } }
        })
        notifications.append(center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: nil) { [weak self] notification in
            let removed = (notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt) == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue
            if removed { Task { @MainActor in self?.pause() } }
        })
    }
    deinit { for token in notifications { NotificationCenter.default.removeObserver(token) } }
    func prepare(owner: String) {
        guard self.owner != owner else { return }; stop(); self.owner = owner; notice = nil; voiceFailure = false; loadingVoices = false; voiceRun = UUID()
        catalog = try? EBookNarrationCatalog.load(); voices = catalog?.voices ?? []
        do { client = try EBookNarrationClient(owner: owner, transport: transport) }
        catch { client = nil; notice = DesktopInterfaceText.value("Edge TTS failed") }
    }
    func loadVoices() async {
        guard !loadingVoices, let client else { return }; loadingVoices = true; let scope = voiceRun
        defer { if voiceRun == scope { loadingVoices = false } }
        do {
            let values = try await client.voices(); try Task.checkCancellation(); guard voiceRun == scope else { return }
            var seen = Set<String>(); voices = (values + (catalog?.voices ?? [])).filter { seen.insert($0.id).inserted }; voiceFailure = false
        } catch { if !Task.isCancelled, voiceRun == scope { voiceFailure = true } }
    }
    static var deviceVoices: [EBookNarrationVoice] { AVSpeechSynthesisVoice.speechVoices().map { .init(id: $0.identifier, locale: $0.language, gender: $0.gender == .male ? "Male" : $0.gender == .female ? "Female" : "", name: $0.name) } }
    func start(blocks: [EBookBlock], block: Int, voice: String, device: Bool, speed: Double) {
        stop(); paragraphs = EBookSearchParagraph.make(blocks); self.device = device; self.speed = Self.bounded(speed); notice = nil
        guard !paragraphs.isEmpty else { notice = DesktopInterfaceText.value("There is nothing to read aloud on this page."); return }
        let start = paragraphs.firstIndex { $0.block == block } ?? 0
        selectedVoice = (device ? Self.deviceVoices : voices).first { $0.id == voice } ?? (device ? Self.deviceVoices.first : catalog?.voices.first)
        guard selectedVoice != nil else { notice = DesktopInterfaceText.value("Edge TTS failed"); return }
        speaking = true; step = 0
        if device { deviceLine = start; speakDeviceLine() }
        else { let id = run; task = Task { await advance(start: start, step: 0, run: id) } }
    }
    func preview(_ voice: EBookNarrationVoice, device: Bool, fallback: String) {
        if previewID == voice.id { stop(); return }; stop(); notice = nil; previewID = voice.id; self.device = device
        let sample = catalog?.sample(locale: voice.locale, fallback: fallback) ?? fallback
        if device {
            do {
                try activateAudio(); let value = AVSpeechUtterance(string: sample); value.voice = AVSpeechSynthesisVoice(identifier: voice.id)
                utterance = ObjectIdentifier(value); speech.speak(value)
            } catch { fail() }
        } else {
            guard let client else { fail(); return }; loading = true; let id = run
            task = Task {
                do {
                    let result = try await client.synthesize(sample, voice: voice.id, locale: voice.locale)
                    try Task.checkCancellation(); guard id == run else { return }; try play(result, run: id); loading = false
                } catch { if id == run, !Task.isCancelled { fail() } }
            }
        }
    }
    func stop() {
        run = UUID(); task?.cancel(); task = nil; clock?.cancel(); clock = nil; ahead?.task.cancel(); ahead = nil
        player?.stop(); player = nil; utterance = nil; speech.stopSpeaking(at: .immediate)
        speaking = false; paused = false; loading = false; progress = 0; position = 0; duration = 0; currentBlock = nil; previewID = nil
        window = nil; boundaries = []; paragraphs = []
        if audioActive { try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation); audioActive = false }
    }
    func togglePause() {
        guard speaking, !loading else { return }
        if !paused { pause() }
        else {
            do {
                try activateAudio()
                if device { guard speech.continueSpeaking() else { return } }
                else { guard player?.play() == true else { fail(); return } }
                paused = false
            } catch { fail() }
        }
    }
    func pause() {
        guard speaking || previewID != nil else { return }
        if loading { stop(); return }
        player?.pause(); if device { speech.pauseSpeaking(at: .immediate) }; paused = true
    }
    func seek(_ value: Double) {
        guard value.isFinite, let player, duration > 0, !device else { return }
        player.currentTime = min(duration, max(0, value)); updatePosition()
    }
    func setSpeed(_ value: Double) {
        speed = Self.bounded(value); player?.enableRate = true; player?.rate = Float(speed)
        if device, speaking, utterance != nil {
            utterance = nil; speech.stopSpeaking(at: .immediate); speakDeviceLine()
            if paused { speech.pauseSpeaking(at: .immediate) }
        }
    }
    func clearCache() async {
        guard let client else { return }; stop()
        do { try await client.clearCache() } catch { notice = DesktopInterfaceText.value("Error") }
    }
    private static func bounded(_ value: Double) -> Double { value.isFinite ? min(2, max(0.5, value)) : 1 }
    private func activateAudio() throws { try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio); try AVAudioSession.sharedInstance().setActive(true); audioActive = true }
    private func fail() { stop(); notice = DesktopInterfaceText.value("Edge TTS failed") }
    private func advance(start: Int, step: Int, run id: UUID) async {
        guard id == run, let voice = selectedVoice, let client else { return }
        guard let window = await EBookNarrationWindow.prepare(paragraphs, start: start, step: step, locale: voice.locale), id == run else { return }
        self.window = window; self.step = step; loading = true; progress = 1
        do {
            let result: EBookNarrationAudio
            if let ahead, ahead.start == start {
                self.ahead = nil
                do { result = try await ahead.task.value }
                catch { try Task.checkCancellation(); result = try await client.synthesize(window.text, voice: voice.id, locale: voice.locale) }
            }
            else {
                result = try await client.synthesize(window.text, voice: voice.id, locale: voice.locale) { [weak self] value in
                    await self?.updateProgress(value, run: id)
                }
            }
            try Task.checkCancellation(); guard id == run else { return }; boundaries = result.boundaries
            try play(result, run: id); loading = false; currentBlock = paragraphs[start].block
            if let next = await EBookNarrationWindow.prepare(paragraphs, start: window.end, step: step + 1, locale: voice.locale), id == run, self.window?.start == window.start {
                ahead = (next.start, Task { try await client.synthesize(next.text, voice: voice.id, locale: voice.locale) })
            }
        } catch { if id == run, !Task.isCancelled { fail() } }
    }
    private func play(_ value: EBookNarrationAudio, run id: UUID) throws {
        try activateAudio(); let audio = try AVAudioPlayer(data: value.audio, fileTypeHint: AVFileType.mp3.rawValue)
        audio.delegate = self; audio.enableRate = true; audio.rate = Float(speed); audio.prepareToPlay()
        guard audio.play() else { throw EBookNarrationError.emptyAudio }; player = audio; duration = audio.duration; position = 0
        clock?.cancel(); clock = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(150)) } catch { return }
                guard let self, self.run == id else { return }; self.updatePosition()
            }
        }
    }
    private func updateProgress(_ value: EBookNarrationProgress, run id: UUID) { if run == id { progress = value.percent } }
    private func updatePosition() {
        guard let player else { return }; let time = player.currentTime; if position != time { position = time }
        if let window, previewID == nil {
            let line = window.paragraph(position: position, duration: duration, boundaries: boundaries)
            if paragraphs.indices.contains(line), currentBlock != paragraphs[line].block { currentBlock = paragraphs[line].block }
        }
    }
    private func speakDeviceLine() {
        guard paragraphs.indices.contains(deviceLine), let voice = selectedVoice else { stop(); return }
        do {
            try activateAudio(); let value = AVSpeechUtterance(string: paragraphs[deviceLine].text)
            value.voice = AVSpeechSynthesisVoice(identifier: voice.id); value.rate = min(AVSpeechUtteranceMaximumSpeechRate, max(AVSpeechUtteranceMinimumSpeechRate, AVSpeechUtteranceDefaultSpeechRate * Float(speed)))
            utterance = ObjectIdentifier(value); currentBlock = paragraphs[deviceLine].block; speech.speak(value)
        } catch { fail() }
    }
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        let identity = ObjectIdentifier(player)
        Task { @MainActor [weak self] in
            guard let self, let active = self.player, ObjectIdentifier(active) == identity else { return }
            guard flag else { self.fail(); return }
            if self.previewID != nil { self.stop(); return }
            guard let window = self.window, window.end < self.paragraphs.count else { self.stop(); return }
            self.player = nil; self.clock?.cancel(); let id = self.run, start = window.end, step = self.step + 1
            self.task = Task { await self.advance(start: start, step: step, run: id) }
        }
    }
    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        let identity = ObjectIdentifier(player)
        Task { @MainActor [weak self] in if let self, let active = self.player, ObjectIdentifier(active) == identity { self.fail() } }
    }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let identity = ObjectIdentifier(utterance)
        Task { @MainActor [weak self] in
            guard let self, self.utterance == identity else { return }
            if self.previewID != nil { self.stop(); return }; self.deviceLine += 1; self.speakDeviceLine()
        }
    }
}

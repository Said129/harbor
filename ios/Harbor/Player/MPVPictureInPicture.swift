@preconcurrency import AVKit
import CoreMedia
import CoreVideo

/// AVKit controls the floating window; the existing mpv core continues to own
/// decoding, audio, track selection, seeking and playback state.
@MainActor
final class MPVPictureInPicture: NSObject, @preconcurrency AVPictureInPictureControllerDelegate, @preconcurrency AVPictureInPictureSampleBufferPlaybackDelegate {
    private weak var owner: MPVController?
    private let layer = AVSampleBufferDisplayLayer()
    private var controller: AVPictureInPictureController?
    private var timebase: CMTimebase?
    private var previousPaused: Bool?
    private var previousDuration = 0.0
    private var startFailure: Error?
    private(set) var lastFrame: CVPixelBuffer?
    private(set) var renderedFrames = 0

    init(owner: MPVController, view: UIView) throws {
        self.owner = owner
        super.init()
        layer.videoGravity = .resizeAspect
        layer.backgroundColor = UIColor.clear.cgColor
        layer.frame = view.bounds
        view.layer.addSublayer(layer)
        var clock: CMTimebase?
        guard CMTimebaseCreateWithSourceClock(allocator: kCFAllocatorDefault, sourceClock: CMClockGetHostTimeClock(), timebaseOut: &clock) == noErr,
              let clock else { layer.removeFromSuperlayer(); throw HarborError(code: "player-frame-time") }
        timebase = clock; layer.controlTimebase = clock
        CMTimebaseSetRate(clock, rate: 0)
        if AVPictureInPictureController.isPictureInPictureSupported() {
            let source = AVPictureInPictureController.ContentSource(sampleBufferDisplayLayer: layer, playbackDelegate: self)
            let controller = AVPictureInPictureController(contentSource: source)
            controller.delegate = self
            controller.canStartPictureInPictureAutomaticallyFromInline = false
            self.controller = controller
        }
    }

    var active: Bool { controller?.isPictureInPictureActive == true }
    func layout(_ bounds: CGRect) { layer.frame = bounds }

    func enqueue(_ buffer: CVPixelBuffer) throws {
        guard let owner else { return }
        let sample = try MPVSampleBufferRenderer.sample(buffer, position: owner.state.position)
        let renderer = layer.sampleBufferRenderer
        if renderer.status == .failed { renderer.flush() }
        synchronizeClock()
        guard renderer.isReadyForMoreMediaData else { return }
        renderer.enqueue(sample)
        layer.backgroundColor = UIColor.black.cgColor
        lastFrame = buffer; renderedFrames += 1
    }

    func synchronizeClock() {
        guard let owner, let timebase else { return }
        let state = owner.state
        let paused = state.paused || state.buffering || state.ended || !state.loaded
        if state.position.isFinite && state.position >= 0 {
            CMTimebaseSetTime(timebase, time: CMTime(seconds: state.position, preferredTimescale: 60_000))
        }
        CMTimebaseSetRate(timebase, rate: paused ? 0 : state.speed)
        if paused != previousPaused || previousDuration != state.duration {
            previousPaused = paused; previousDuration = state.duration
            controller?.requiresLinearPlayback = !state.duration.isFinite || state.duration <= 0
            controller?.invalidatePlaybackState()
        }
    }

    func start() async throws {
        guard let controller else { throw HarborError(code: "pip-unavailable") }
        startFailure = nil
        let ready = Date().addingTimeInterval(5)
        while (lastFrame == nil || !controller.isPictureInPicturePossible) && Date() < ready {
            try Task.checkCancellation()
            try await Task.sleep(for: .milliseconds(50))
        }
        guard lastFrame != nil, controller.isPictureInPicturePossible else { throw HarborError(code: "pip-unavailable") }
        controller.startPictureInPicture()
        let deadline = Date().addingTimeInterval(5)
        while !controller.isPictureInPictureActive && startFailure == nil && Date() < deadline {
            try Task.checkCancellation()
            try await Task.sleep(for: .milliseconds(50))
        }
        if let startFailure { throw startFailure }
        guard controller.isPictureInPictureActive else { throw HarborError(code: "pip-unavailable") }
    }

    func stop() { controller?.stopPictureInPicture() }
    func resetFrames() {
        layer.sampleBufferRenderer.flush(removingDisplayedImage: true, completionHandler: nil)
        layer.backgroundColor = UIColor.clear.cgColor
        lastFrame = nil; previousPaused = nil; previousDuration = 0
    }
    func close() {
        controller?.delegate = nil
        controller?.stopPictureInPicture()
        controller = nil; owner = nil
        layer.sampleBufferRenderer.flush()
        layer.removeFromSuperlayer()
        lastFrame = nil; timebase = nil
    }

    func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        owner?.state.pictureInPictureActive = pictureInPictureController.isPictureInPictureActive
    }
    func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        guard let owner else { return }
        owner.state.pictureInPictureActive = false
        owner.restoreAfterPictureInPicture()
    }
    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, failedToStartPictureInPictureWithError error: Error) {
        guard let owner else { return }
        owner.state.pictureInPictureActive = false
        startFailure = HarborError(code: "pip-unavailable")
        Diagnostics.shared.record(.playerFailed, count: (error as NSError).code)
        // The awaiting start task performs one restoration after this callback.
    }
    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void) {
        completionHandler(owner?.viewIfLoaded?.window != nil)
    }
    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, setPlaying playing: Bool) {
        owner?.set("pause", playing ? "no" : "yes")
    }
    func pictureInPictureControllerTimeRangeForPlayback(_ pictureInPictureController: AVPictureInPictureController) -> CMTimeRange {
        guard let state = owner?.state else { return .invalid }
        if state.duration.isFinite && state.duration > 0 {
            return CMTimeRange(start: .zero, duration: CMTime(seconds: max(state.duration, state.position), preferredTimescale: 60_000))
        }
        return CMTimeRange(start: .zero, duration: .positiveInfinity)
    }
    func pictureInPictureControllerIsPlaybackPaused(_ pictureInPictureController: AVPictureInPictureController) -> Bool {
        guard let state = owner?.state else { return true }
        return state.paused || state.buffering || state.ended || !state.loaded
    }
    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, didTransitionToRenderSize newRenderSize: CMVideoDimensions) {
        // Frames follow the real video aspect and stay within a 640px budget.
        // A change of window size does not restart decoding or grow the pool.
        synchronizeClock()
    }
    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, skipByInterval skipInterval: CMTime, completion completionHandler: @escaping () -> Void) {
        guard let owner, CMTimeGetSeconds(skipInterval).isFinite else { completionHandler(); return }
        Task { @MainActor in
            defer { completionHandler() }
            do { try await owner.seekForPictureInPicture(CMTimeGetSeconds(skipInterval)) }
            catch { owner.state.playbackIssue = safeMessage(error) }
        }
    }
}

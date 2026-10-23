import Foundation
import Observation

/// Desktop reveals its reader chrome on interaction and hides it after 2.2 seconds in focus mode.
@MainActor @Observable final class EBookReaderChrome {
    private(set) var visible = true
    @ObservationIgnored private var timer: Task<Void, Never>?
    private let delay: Duration
    init(delay: Duration = .milliseconds(2200)) { self.delay = delay }
    func reveal(focus: Bool, suspended: Bool = false) {
        stop()
        guard focus, !suspended else { return }
        let delay = delay
        timer = Task { [weak self] in
            do { try await Task.sleep(for: delay) } catch { return }
            guard !Task.isCancelled, let self else { return }
            self.visible = false; self.timer = nil
        }
    }
    func stop() { timer?.cancel(); timer = nil; visible = true }
    deinit { timer?.cancel() }
}

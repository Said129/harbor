import Foundation
import Observation

@MainActor @Observable
final class PlayerState {
    var position: Double = 0
    var hasPosition = false
    var duration: Double = 0
    var paused = false
    var buffering = false
    var loaded = false
    var renderReady = false
    var ended = false
    var error: String?
    var tracks: [Track] = []
    weak var controller: MPVController?
    struct Track: Identifiable {
        let id: Int
        let type: String
        let label: String
        let selected: Bool
    }
}

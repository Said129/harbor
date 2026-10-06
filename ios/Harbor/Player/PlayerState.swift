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
    var renderCalls = 0
    var ended = false
    var error: String?
    var tracks: [Track] = []
    var chapters: [Chapter] = []
    var speed = 1.0
    var volume = 100.0
    var muted = false
    var audioDelay = 0.0
    var subtitleDelay = 0.0
    weak var controller: MPVController?
    struct Track: Identifiable {
        let id: Int
        let type: String
        let label: String
        let selected: Bool
    }
    struct Chapter: Identifiable {
        let id: Int
        let title: String
        let time: Double
    }
}

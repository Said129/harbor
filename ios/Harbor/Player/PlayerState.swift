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
    var mediaGeneration = 0
    var renderReady = false
    var renderCalls = 0
    var ended = false
    var endedNaturally = false
    var error: String?
    var tracks: [Track] = []
    var chapters: [Chapter] = []
    var speed = 1.0
    var volume = 100.0
    var muted = false
    var audioDelay = 0.0
    var subtitleDelay = 0.0
    var subtitleFPS: Double?
    var estimatedVideoFPS: Double?
    var containerVideoFPS: Double?
    var subtitleChanging = false
    var subtitleIssue: String?
    var importedSubtitleIDs: Set<Int> = []
    var subtitleImportMessage: String?
    var primarySubtitleText = ""
    var secondarySubtitleText = ""
    var videoFPS: Double? { estimatedVideoFPS ?? containerVideoFPS }
    var primarySubtitle: Track? { tracks.first { $0.type == "sub" && $0.mainSelection == 0 } }
    var secondarySubtitle: Track? { tracks.first { $0.type == "sub" && $0.mainSelection == 1 } }
    weak var controller: MPVController?
    struct Track: Identifiable, Sendable {
        let id: Int
        let type: String
        let label: String
        let selected: Bool
        var codec = ""
        var language = ""
        var title = ""
        var externalFilename = ""
        var mainSelection: Int? = nil
        var external = false
        var forced = false
        var hearingImpaired = false
        var defaultTrack = false
    }
    struct Chapter: Identifiable {
        let id: Int
        let title: String
        let time: Double
    }
}

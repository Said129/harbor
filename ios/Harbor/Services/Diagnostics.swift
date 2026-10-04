import Foundation
import OSLog

@MainActor
final class Diagnostics {
    static let shared = Diagnostics()
    private let logger = Logger(subsystem: "site.harbor.iphone", category: "lifecycle")
    private var events: [String] = []
    enum Event: String { case startup, coreReady, catalogsLoaded, addonInstalled, streamsLoaded, playerStarted, playerEnded, failure }
    func record(_ event: Event, count: Int = 0) {
        // Closed event vocabulary: callers cannot insert payloads, URLs or credentials.
        let line = "\(Date().ISO8601Format()) \(event.rawValue) count=\(count)"
        logger.info("\(line, privacy: .public)")
        events.append(line)
        if events.count > 300 { events.removeFirst(events.count - 300) }
    }
    func export() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("harbor-ios-diagnostics.txt")
        try Data(events.joined(separator: "\n").utf8).write(to: url, options: [.atomic, .completeFileProtection])
        return url
    }
}

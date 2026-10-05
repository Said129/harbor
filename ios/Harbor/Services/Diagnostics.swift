import Foundation
import OSLog

@MainActor
final class Diagnostics {
    static let shared = Diagnostics()
    private let logger = Logger(subsystem: "site.harbor.iphone", category: "lifecycle")
    private var events: [String] = []
    enum Event: String { case startup, coreReady, catalogsLoaded, addonInstalled, streamsLoaded, requestStarted, requestCompleted, playerStarted, playerEnded, playerFailed, progressSaved, accountSignedIn, accountSynced, accountSignedOut, failure }
    func record(_ event: Event, count: Int = 0) {
        // Closed event vocabulary: callers cannot insert payloads, URLs or credentials.
        let line = "\(Date().ISO8601Format()) \(event.rawValue) count=\(count)"
        append(line)
    }
    func recordFailure(_ error: Error) {
        let code = (error as? HarborError)?.code ?? "unknown"
        let known: Set<String> = ["unknown", "network", "invalid-http-response", "response-too-large", "invalid-request", "invalid-request-size", "core-panic", "invalid-addon-url", "invalid-manifest", "invalid-resource", "invalid-stream-response", "invalid-playback-url", "invalid-playback-header", "invalid-subtitle-url", "torrent-resolver-pending", "youtube-resolver-pending", "nzb-resolver-pending", "external-url-only", "addon-not-configured", "no-source", "no-streams", "no-metadata", "abi-version", "core-no-response", "storage-unavailable"]
        let resumeCodes: Set<String> = ["invalid-resume-target", "invalid-resume-position", "invalid-resume-store", "unsupported-resume-version", "resume-store-unavailable", "resume-store-too-large", "resume-read-failed", "resume-write-failed"]
        let accountCodes: Set<String> = ["invalid-account-request", "invalid-account-response", "invalid-account-store", "account-auth-response", "account-addons-response", "account-addons-save-response", "account-rejected", "account-busy", "account-cancelled", "account-browser-unavailable", "account-timeout", "account-local-save-failed"]
        let libraryCodes: Set<String> = ["invalid-library-response", "library-cache-too-large", "library-cache-read-failed", "library-cache-write-failed", "invalid-catalog-response", "invalid-artwork", "artwork-unavailable", "artwork-too-large"]
        var safe = known.contains(code) || resumeCodes.contains(code) || accountCodes.contains(code) || libraryCodes.contains(code) ? code : "unknown"
        if code.hasPrefix("http-"), let status = Int(code.dropFirst(5)), (100...599).contains(status) { safe = "http-\(status)" }
        if code.hasPrefix("mpv-"), let status = Int(code.dropFirst(4)), (-1024...0).contains(status) { safe = "mpv-\(status)" }
        for prefix in ["keychain-read-", "keychain-write-", "keychain-delete-", "keychain-"] {
            if code.hasPrefix(prefix), let status = Int32(code.dropFirst(prefix.count)) {
                safe = "\(prefix)\(status)"
                break
            }
        }
        // Only whitelisted codes or bounded numbers reach exported diagnostics.
        append("\(Date().ISO8601Format()) failure code=\(safe)")
    }
    private func append(_ line: String) {
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
